# Developer tools

Everything here is meant to be run from the **repo root**. Most tools have a short name in
`tasks.ps1`, which is the intended entry point:

```powershell
./tasks.ps1 install_dev_requirements   # once per host, per PowerShell edition
./tasks.ps1 build                      # Source/ -> Dist/
./tasks.ps1 test
./tasks.ps1 lint
./tasks.ps1 coverage
./tasks.ps1 fuzz
./tasks.ps1 prepare_release 1.4.0
```

| Tool | Task | What it does |
|---|---|---|
| `install_dev_requirements.ps1` | `install_dev_requirements` | Installs ModuleBuilder, Configuration, Pester (pinned, see `Tools/pester_pin.ps1`), and PSScriptAnalyzer for the current user. |
| `build.ps1` | `build` | Clears `Dist/` and builds the module with ModuleBuilder. |
| `tests.ps1` | `test` | Runs the Pester suite against the built module. Throws on any failure. |
| `lint.ps1` | `lint` | PSScriptAnalyzer over `Source/`: style/correctness, then WinPS 5.1 + pwsh 7 compatibility. Any finding fails. |
| `coverage.ps1` | `coverage` | Test run with code coverage, listing every missed command. `-MinimumPercent` gates the run. |
| `fuzz.ps1` | `fuzz` | Mutation fuzzer over the six surfaces that must survive adversarial input. Prints a replayable seed. |
| `prepare_release.ps1` | `prepare_release <x.y.z>` | Runs the gates, promotes the changelog, stamps the version, rebuilds, and verifies the built manifest. |
| `get_changelog_section.ps1` | - | Extracts one section from `CHANGELOG.md`. Shared by `prepare_release` and the release workflow. |
| `deploy_to_testvm.sh` | - | Deploys the working tree to a Windows test VM, runs the suite on three hosts, installs the module, and deploys the integration sensors to PRTG. |

Everything except the deploy script imports the **built** module from `Dist/`, the same artifact
a user installs, so `build` has to run first.

## Notes

**Pester is pinned to 6.1.0.** The pin is owned by `Tools/pester_pin.ps1` and echoed here, so
changing it means editing both. Pester versions change how many commands a coverage run analyzes,
so numbers produced by two different versions cannot be compared. A host without the pinned
version fails the run with the command that installs it.

**Coverage is per host.** The relaunch cmdlets read as uncovered everywhere because they are
tested in a child process that the instrumentation cannot follow. Compare hosts before
concluding that a line is untested.

**`deploy_to_testvm.sh` needs your own VM.** It reads the host from a gitignored `.testvm` file
in the repo root:

```
IP=prtgsensorkit-testvm
```

It expects key-based ssh (it never prompts), the dev requirements installed on the VM for both
editions, and PRTG installed. Remote paths default to that layout and are overridable with the
`TESTVM_REPO` and `TESTVM_EXEXML` environment variables (`TESTVM_REPO` must not contain spaces,
since it is used as an scp destination). Use `-NoFuzzing` during a normal
edit/check loop; run a full pass before a release.

`fuzz-failures/` holds repro artifacts from the last fuzz run and is gitignored.
