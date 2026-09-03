# PrtgSensorKit - how we work here

PowerShell module for PRTG EXEXML sensors. The real runtime is **32-bit Windows
PowerShell 5.1 under a PRTG probe**, not the pwsh 7 you develop in. That gap sets the bar for
the whole repo: a claim is **unverified** until it has been executed where it actually runs.
A green pwsh 7 suite, a doc example you read but did not run, a `Dist/` you did not rebuild -
all unverified.

## Gotchas that have burned us

- **Behaviour tests run against `Source/`; only the artifact tests read `Dist/`.**
  `./tasks.ps1 test` builds first and then imports the source tree, so a failure names the
  source file and line; `-Target Dist` imports the build into those same tests instead.
  `Tests/Artifact/` always reads the build, whatever the target, and runs inside every test
  run. The remaining trap is a Pester session started by hand: it skips the runner's build,
  and the artifact stale check is what catches it.
- **Source must be pure ASCII** - non-ASCII breaks the built psm1 under WinPS 5.1.
  No em-dashes anywhere, including docs and CHANGELOG.
- A stale installed 1.0.0 module can shadow `Dist/` on by-name import; prepend `Dist/` to
  `PSModulePath` when running ad hoc.
- Exception-catch dispatch differs between WinPS 5.1 and pwsh 7 (see the comment in
  `Source/Private/Invoke-PrtgStateLock.ps1`). A macOS-only run leaves that class of bug
  unverified; the VM is the only place it resolves.

## The Windows test VM

Where claims stop being unverified. Available to any agent, any time, not just at release:
five minutes of ssh beats an afternoon of ACL/path/exception theory. Key-based ssh,
non-interactive:

```bash
source ./.testvm    # gitignored, per developer: IP=<host>
ssh "$IP" 'powershell -NoProfile -NonInteractive -Command "..."'   # WinPS 5.1 x64
ssh "$IP" 'pwsh -NoProfile -NonInteractive -Command "..."'         # pwsh 7
# 32-bit WinPS 5.1 (what PRTG actually starts): %WINDIR%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe
```

`TestUser` is a local admin and the default user set for ssh; `ssh "TestUser2@$IP"` is
the unprivileged account - permission questions are only answerable as testuser2.
PRTG is installed, so integration sensors can be validated on the real probe by the owner.
Clean up after yourself: scratch files, and any store folders
you created under `%ProgramData%\PrtgSensorKit\` - leftovers silently corrupt the next run.
The VM gets a copy of the tree; edit locally, deploy, verify - never edit on the VM.

## Backward compatibility

Public promise since 1.1.0: sensor scripts written for 1.0.0/1.1.0 run unchanged. Additive
changes only, except bug fixes that restore documented/spec behavior, which may ship in a
minor version even when they can turn green sensors red (1.3.0 EAP fix, 1.4.0 duplicate
channel names). Those need an explicit owner decision plus a bold CHANGELOG call-out with a
copy-paste migration. **Execute the migration snippet** - a broken one shipped once because
three review passes read it and left it unverified.

## Comment style

State the constraint the code cannot show. No development narrative

## Git boundaries (hard rules)

Commit only when the owner explicitly says so, `git push` only on the owner's clear command,
and the PR is **merged by the owner personally - never by the agent**, no matter how green
the checks are.

CI running twice on dev pushes (push + PR triggers) is intentional - do not "fix" it.

## Release checklist (in order)

1. Full `./Tools/deploy_to_testvm.sh` (`Tools/README.md` documents what it runs and its
   `-NoFuzzing` loop mode). Then validate on the real probe: every sensor in
   `Tests/Integration/README.md` accounted for against what that file says it must show,
   not spot-checked. Until that is done the release is unverified, however green the rest is.
2. `Tools/prepare_release.ps1 -Version X.Y.Z` stamps CHANGELOG (promotes `[Unreleased]`),
   README badge, and `build.psd1` - never stamp by hand, it is three places.
3. Group changes into one commit per logical item.
   Commit format: **one line, unscoped conventional type** (`fix: ...`, never
   `fix(scope): ...`), release stamp last as `release: vX.Y.Z`. Commits must be
   **GPG-signed** - beware: `git filter-branch` strips signatures.
4. Push dev, CI green, then PR dev -> master. Title `Release vX.Y.Z: <headline items>`;
   body is a condensed CHANGELOG: TL;DR + link, breaking-change call-out with migration
   snippet on top, then short Added/Changed/Fixed. Model: PR #5/#6.
5. Merge = **merge commit, never squash**. After merge: pull master, lightweight tag
   `vX.Y.Z`, push tag (triggers the release workflow), then ff-only merge master into dev
   and push.

## Agent skills

### Issue tracker

Local markdown: specs and tickets live under `.scratch/<feature-slug>/`.
See `Docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, unchanged, recorded as a `Status:` line in each issue
file. See `Docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `Docs/adr/` at the repo root.
See `Docs/agents/domain.md`.
