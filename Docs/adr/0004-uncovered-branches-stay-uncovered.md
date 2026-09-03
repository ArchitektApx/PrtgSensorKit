# Behaviour tests run against the source tree, and uncovered branches stay uncovered

The behaviour tests import the source tree, so coverage is measured over the source files
and reported per file. Only the tests under `Tests/Artifact/` read the built module, and
they are about the build itself rather than about what the module does; `./tasks.ps1 test`
and `./tasks.ps1 coverage` build first, so no run can measure a stale artifact.
`./tasks.ps1 coverage` forces the `Source` target, because a coverage number over the
source files only means something when those files are what executed.

Every command the suite misses on all four hosts it runs on (macOS pwsh 7, and Windows
PowerShell 5.1 x64, x86 and pwsh 7 on the Windows test VM) is left uncovered rather than
mocked, and the reason it is missed is recorded in this file rather than in a comment at
the site. Source comments state a constraint the code cannot show; a test-strategy note
is not one, and each attempt to phrase one as a permanence claim was later measured
false.

## Why not mock

A mock of a process that execs and exits exercises the mock, not the code, and turns a
visible gap into an invisible one: the coverage number then claims something was tested
when only its stand-in was. The relaunch path is verified by the integration sensors on a
real probe instead.

## Why not in the source

The first version of this record was a set of "PERMANENTLY UNCOVERED" comments. Measured,
the module has no branch that no host can execute: every one is uncovered for a reason
short of impossibility. A comment asserting impossibility is a claim about test
infrastructure, which changes, and it was wrong five times in one loop. The categories
below are stable; the count of sites in each is not, so the count is not recorded.

## The categories

**Expensive.** Reachable in process, but reaching the last line ends the test host.
`Invoke-PrtgRelaunch` and the relaunch arm of each `Restart-*` cmdlet: the call operator
starts the child, waits, returns, and `exit $LASTEXITCODE` then ends the host with the
child's code. An `-Executable` that does not resolve executes everything above the exit
and throws `CommandNotFoundException` back to the caller. Covering the exit means a
throwaway host per test.

**Coverable by choice.** `Set-PrtgConsoleEncoding`'s catch. `kernel32!FreeConsole`
detaches the console from the running process, the setter then throws, and
`AllocConsole` restores one, but a different one, so the suite would be mutating
process-global state its own reporting depends on. Not worth one arm.

**Untriggered.** `Set-PrtgModernTls`'s TLS 1.3 catch and the TLS 1.2-only assignment
after it. Which values the `SecurityProtocol` setter accepts diverges from the enum's
members by runtime: pwsh 7 refuses `Ssl3`, Windows PowerShell 5.1 accepts every member.
`Tls12 -bor Tls13` was accepted on all four hosts, so nothing reaches the catch; a
runtime that refuses it is not excluded, which is why the catch is defensive rather than
dead.

**Unavailable host.** `Get-PrtgDoctorHostPath`'s early return needs a 32-bit operating
system, where there is no WOW64 redirection to honor. `Is64BitOperatingSystem` reports
the real OS, so a 32-bit process on 64-bit Windows, which the VM does run the suite in,
cannot stand in for one. `Restart-As64BitPowershell`'s sysnative lookup is the neighbour:
it wants a 32-bit process plus `$env:WINDIR` redirected so the lookup fails, which a test
can arrange and none does.

**Untested.** Everything else in the intersection is an ordinary test gap: no fixture
produces the shape. `Get-PrtgLogCallerScriptPath` from a stack with no script path,
`New-PrtgLogFile`'s prune catch, three PSK0104 target-selection lines in
`Test-PrtgDoctorEnvironment`, and two arms in `Test-PrtgDoctorScript`. Writing those
tests is a scoping decision, not a platform question.

## How to measure it again

Intersect on the `<file>:<line>: <command>` rows the coverage run prints under
`--- Missed ---`, never on line numbers. The file is part of the key because coverage is
measured per source file, and two files hold a line 40. A line holding two commands, such
as `$who = if ($onWindows) { ... } else { $env:USER }`, is missed on every host while each
half is covered on the host it applies to. Intersecting on lines reports it as permanently
uncovered, and one round did. `comm` compares lexically, so sort
lexically; coverage collected over ssh carries CRLF, strip it first. A locked DPAPI store
on the VM stops the secret tests before they reach the code and inflates the
intersection; the VM account must have logged on at the console since the last reboot.

The sweep behind this record is under `.scratch/internal-seams/measurements/`, with the
per-host lists and the intersection as raw run output. Its line numbers and quoted
command text refer to the build they were taken from and are evidence for this decision,
not a live index.

## Consequences

`Tools/coverage.ps1` prints, beside the number on every run, that a covered line is not a
tested input, and a per-file table that says which area is thin. Nobody adds a permanence
comment at a site; a new uncovered site gets a row in one of the categories above, or a
test. A future test host that changes one of these facts changes this file, not the source.
