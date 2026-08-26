# State timestamps compare in UTC, and ties go to the entry appended last

Every comparison of State entry timestamps normalizes with `ToUniversalTime()`
before comparing, and any ordering of a history breaks ties in favour of the
entry that was appended last. Both halves are needed, because
`Get-PrtgSensorState` was able to contradict itself on each of them.

## Why UTC normalization

The module only ever writes `[DateTime]::UtcNow`, and clixml preserves
`DateTimeKind` across a round trip (verified `Utc` on both pwsh 7 and Windows
PowerShell 5.1). So a file the module wrote holds only `Utc` timestamps, and
normalizing is the identity transform on it. A hand-written or foreign clixml can
hold `Local` or `Unspecified` kinds, and there the two paths diverged:
`-MaxAge` filtering and `Get-PrtgNewestEntry` normalized, while the default
return path sorted on the raw value. With one `Utc` and one `Local` entry under a
negative UTC offset, the default path and `-Latest` named different entries as
newest, from the same file, in the same call.

## Why append order breaks ties

`[DateTime]::UtcNow` has roughly 15 ms resolution on .NET Framework, so two quick
saves genuinely produce identical timestamps. `Get-PrtgNewestEntry` compares with
`-ge` so that on a tie the later-appended entry wins, since file order is append
order. `Sort-Object` is not stable, so the default path returned tied entries in
arbitrary order. Unlike the kind problem, this needs no foreign file: two saves
within 15 ms on an ordinary probe are enough.

## Consequences

Any code that answers "which entry is newest" must use both rules, not one. This
includes anything that later consolidates the four state cmdlets, where reducing
the several orderings to a single one is a stated goal: the single ordering is
this one.
