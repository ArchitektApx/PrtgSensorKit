#!/usr/bin/env bash
#
# deploy_to_testvm.sh - one-shot deploy of the working tree to a Windows test VM, so the
# integration sensors can be checked by hand against a real PRTG probe.
#
# What it does:
#   1. delete the old repo copy on the VM and copy the current working tree over
#   2. run lint and build once, then the test suite under three Windows hosts
#      (WinPS 5.1 x64, pwsh 7, WinPS 5.1 x86), each run rebuilding for itself, then the
#      fuzzer under two
#   3. install the freshly built module to the WinPS + pwsh AllUsers module paths, removing
#      any previous version, and verify each edition resolves the copy just installed
#   4. clear the PRTG EXEXML directory and copy the integration sensors in flat, with a
#      '<category>_' name prefix (PRTG does not list scripts in nested folders)
#   5. run Test-MalformedDoctor.ps1 on the VM to confirm the Doctor flags every malformed_*
#      sensor as expected
#
# Any failure at any step aborts the deploy.
#
# Usage (from the repo root):
#   ./Tools/deploy_to_testvm.sh [-NoFuzzing]
#
#   -NoFuzzing / --no-fuzz   Skip the fuzz runs. They dominate the wall time, so this is for
#                            the edit/deploy/check loop. ALWAYS run a full pass (no switch)
#                            before a release.
#
# For developing on macOS, Linux, or WSL, where the tools cannot run against a Windows host
# locally. Developing on Windows, run ./tasks.ps1 directly instead.
#
# Requirements:
#   - key-based ssh to the VM (the script is non-interactive and never prompts)
#   - a '.testvm' file in the repo root holding the host, e.g.  IP=prtgsensorkit-testvm
#     (gitignored: the VM is yours, not the project's)
#   - on the VM: the repo's dev requirements installed for BOTH editions, and PRTG installed
#
# The remote paths below match that VM layout. Override them per environment with the
# TESTVM_* environment variables rather than editing this file. TESTVM_REPO must not contain
# spaces (it is an scp destination); TESTVM_EXEXML may, and does by default.

set -euo pipefail

# --- config -------------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SELF="./Tools/$(basename "${BASH_SOURCE[0]}")"

RUN_FUZZ=1
for arg in "$@"; do
  case "$arg" in
    -NoFuzzing|--no-fuzz|-nofuzz) RUN_FUZZ=0 ;;
    -h|--help)
      echo "usage: ${SELF} [-NoFuzzing]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument '$arg' (see -h)." >&2
      exit 1
      ;;
  esac
done

if [[ ! -f .testvm ]]; then
  echo "ERROR: .testvm not found in the repo root (expected a line like 'IP=<host-or-address>')." >&2
  exit 1
fi
# shellcheck disable=SC1091
source ./.testvm
VM="${IP:?IP not set in .testvm}"

# Remote layout (see TESTVM_* in the header).
REMOTE_REPO="${TESTVM_REPO:-C:\\Users\\TestUser\\PrtgSensorKit}"
REMOTE_EXEXML="${TESTVM_EXEXML:-C:\\Program Files (x86)\\PRTG Network Monitor\\Custom Sensors\\EXEXML}"
# scp needs the same location with forward slashes; anything else lands relative to the ssh
# user's home instead of where every later step looks.
REMOTE_REPO_SCP="${REMOTE_REPO//\\//}"

# Items needed on the VM for build/test plus the integration sensors.
COPY_ITEMS=(Source Tests Tools Examples tasks.ps1 build.psd1)

echo "==> Deploying working tree to test VM ${VM}"

# --- 1. delete old repo copy on the VM ----------------------------------------------------
echo "==> [1/5] Removing old repo copy at ${REMOTE_REPO}"
ssh "$VM" "powershell -NoProfile -NonInteractive -Command \"if (Test-Path '${REMOTE_REPO}') { Remove-Item '${REMOTE_REPO}' -Recurse -Force }; New-Item -ItemType Directory -Path '${REMOTE_REPO}' -Force | Out-Null\""

# --- 2. copy the working tree -------------------------------------------------------------
echo "==> [2/5] Copying working tree to the VM"
scp -q -r "${COPY_ITEMS[@]}" "${VM}:${REMOTE_REPO_SCP}/"

# --- 3. lint, build, test on the VM -------------------------------------------------------
# Windows PowerShell 5.1 is the real PRTG sensor runtime; pwsh 7 catches Desktop-vs-Core
# regressions; 32-bit WinPS is what PRTG actually starts unless a sensor relaunches itself, and
# is the only host exercising WOW64 redirection. Lint runs once because it is host-independent.
# The explicit build fails the deploy on a build error before any host runs tests; each test run
# rebuilds for itself, so the three hosts each verify the behaviour tests against the source tree
# and the artifact tests against the build that host just made. Step 4 therefore installs the
# build the last test run left behind, not the explicit one.
run_remote_task() {
  local task="$1"
  local host="${2:-powershell}"
  local label="${3:-WinPS 5.1}"
  echo "==> [3/5] Running ./tasks.ps1 ${task} on the VM (${label})"
  ssh "$VM" "${host} -NoProfile -NonInteractive -Command \"Set-Location '${REMOTE_REPO}'; ./tasks.ps1 ${task}\"" \
    || { echo "ERROR: '${task}' failed on the VM under ${label}. Aborting deploy." >&2; exit 1; }
}
run_remote_task lint
run_remote_task build

# Tests run on all hosts before any fuzzing, so a plain failure surfaces early.
run_remote_task test
run_remote_task test pwsh 'pwsh 7'
run_remote_task test '%WINDIR%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe' 'WinPS 5.1 32-bit'

if [[ $RUN_FUZZ -eq 1 ]]; then
  run_remote_task fuzz
  run_remote_task fuzz pwsh 'pwsh 7'
else
  echo "==> [3/5] Skipping fuzz on both hosts (-NoFuzzing). Run without the switch before a release."
fi

# --- 4. install module + deploy integration sensors ---------------------------------------
echo "==> [4/5] Installing built module and deploying integration sensors"

read -r -d '' PS_INSTALL <<'PS' || true
$ErrorActionPreference = 'Stop'
# Silence the progress stream ('Preparing modules for first use'); over a non-interactive
# ssh pipe Windows PowerShell serializes it to stderr as CLIXML noise.
$ProgressPreference = 'SilentlyContinue'

# Locate the freshly built module and its version.
$manifest = Get-ChildItem -Path (Join-Path $repo 'Dist') -Recurse -Filter 'PrtgSensorKit.psd1' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $manifest) { throw 'Built module not found under Dist. Did the build step succeed?' }
$src = $manifest.Directory.FullName
$version = (Import-PowerShellDataFile $manifest.FullName).ModuleVersion
Write-Host "Built module version $version at $src"

# Install to the AllUsers module paths for both editions, removing prior versions.
$roots = @(
  'C:\Program Files\WindowsPowerShell\Modules',   # Windows PowerShell 5.1 (shared 32/64-bit)
  'C:\Program Files\PowerShell\Modules'           # PowerShell 7+ (pwsh)
)
$winTarget = $null
$pwshTarget = $null
foreach ($root in $roots) {
  $modDir = Join-Path $root 'PrtgSensorKit'
  if (Test-Path $modDir) { Remove-Item $modDir -Recurse -Force }
  $target = Join-Path $modDir $version
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  Copy-Item -Path (Join-Path $src '*') -Destination $target -Recurse -Force
  Write-Host "Installed PrtgSensorKit $version to $target"
  if ($root -eq $roots[0]) { $winTarget = $target } else { $pwshTarget = $target }
}

# Load by NAME like a real sensor does, then assert the resolved copy is the one just
# installed: a CurrentUser-scope copy would shadow it and pass a naive check.
Import-Module PrtgSensorKit -Force
$winLoaded = (Get-Module PrtgSensorKit).Path
if ($winLoaded -notlike (Join-Path $winTarget '*')) {
  throw "Windows PowerShell resolved a different PrtgSensorKit: $winLoaded (expected under $winTarget). Another copy is shadowing the AllUsers install."
}
$winOk = (Get-Command Invoke-PrtgSensor).Parameters.Keys -contains 'DryRun'
Write-Host "Windows PowerShell import OK from $winLoaded (DryRun present: $winOk)"

$pwsh = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pwsh) {
  # Same by-name + shadow assertion inside the pwsh host; child exits non-zero on any mismatch.
  $pwshCheck = @"
Import-Module PrtgSensorKit -Force
`$p = (Get-Module PrtgSensorKit).Path
if (`$p -notlike '$pwshTarget\*') { Write-Error "pwsh resolved a shadowing copy: `$p (expected under $pwshTarget)"; exit 3 }
if (-not ((Get-Command Invoke-PrtgSensor).Parameters.Keys -contains 'DryRun')) { Write-Error 'pwsh: DryRun parameter missing'; exit 4 }
Write-Host "pwsh import OK from `$p"
"@
  & $pwsh.Source -NoProfile -NonInteractive -Command $pwshCheck
  if ($LASTEXITCODE -ne 0) { throw "pwsh module verification failed (exit $LASTEXITCODE)." }
} else {
  Write-Warning 'pwsh not found on PATH; skipped the pwsh import check.'
}

# Flattened with a '<category>_' prefix: PRTG only lists scripts in the EXEXML root.
if (-not (Test-Path $exexml)) { throw "PRTG EXEXML directory not found: $exexml" }

# Clear existing scripts (and any nested Integration folder from an earlier deploy).
Get-ChildItem $exexml -File -Filter *.ps1 | Remove-Item -Force
$oldNested = Join-Path $exexml 'Integration'
if (Test-Path $oldNested) { Remove-Item $oldNested -Recurse -Force }

$integrationSrc = Join-Path $repo 'Tests\Integration'
$deployed = 0
foreach ($category in @('working', 'failing', 'malformed')) {
  $dir = Join-Path $integrationSrc $category
  if (-not (Test-Path $dir)) { continue }
  Get-ChildItem $dir -File -Filter *.ps1 | ForEach-Object {
    Copy-Item $_.FullName -Destination (Join-Path $exexml ("{0}_{1}" -f $category, $_.Name)) -Force
    $deployed++
  }
}

# The Doctor helper is not a sensor, but ships flat so it can run against the malformed_* files.
Copy-Item (Join-Path $integrationSrc 'Test-MalformedDoctor.ps1') -Destination (Join-Path $exexml 'Test-MalformedDoctor.ps1') -Force

Write-Host "Deployed $deployed integration sensor scripts (flattened, category-prefixed) to $exexml"
PS

TMP_PS="$(mktemp)"
{
  printf "\$repo = '%s'\n" "$REMOTE_REPO"
  printf "\$exexml = '%s'\n" "$REMOTE_EXEXML"
  printf '%s\n' "$PS_INSTALL"
} > "$TMP_PS"
scp -q "$TMP_PS" "${VM}:${REMOTE_REPO_SCP}/_deploy_install.ps1"
rm -f "$TMP_PS"
ssh "$VM" "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ${REMOTE_REPO}\\_deploy_install.ps1" \
  || { echo "ERROR: module install / integration deploy failed on the VM." >&2; exit 1; }
ssh "$VM" "powershell -NoProfile -NonInteractive -Command \"Remove-Item '${REMOTE_REPO}\\_deploy_install.ps1' -Force -ErrorAction SilentlyContinue\"" || true

# --- 5. validate Doctor predictions on the deployed malformed_* sensors --------------------
# -Path points at EXEXML so the DEPLOYED copies are validated, not the ones in the repo.
echo "==> [5/5] Validating malformed sensors against the Doctor on the VM"
ssh "$VM" "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ${REMOTE_REPO}\\Tests\\Integration\\Test-MalformedDoctor.ps1 -Path \"${REMOTE_EXEXML}\"" \
  || { echo "ERROR: Doctor validation of the malformed sensors failed on the VM." >&2; exit 1; }

echo ""
echo "==> Done. Doctor predictions on the malformed sensors validated. Integration sensors"
echo "    (working_*/failing_*/malformed_*) are in the PRTG EXEXML folder on ${VM}; validate"
echo "    each against Tests/Integration/README.md in the PRTG UI."
