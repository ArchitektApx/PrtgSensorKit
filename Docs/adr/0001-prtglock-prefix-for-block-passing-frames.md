# Parameters and locals of a block-passing frame carry a name prefix

`Invoke-PrtgStateLock` runs a caller-supplied script block via `& $PrtgLockBlock`,
and PowerShell resolves unqualified names in that block up the dynamic scope
chain, hitting the lock function's own frame first. Every parameter and local
there is therefore prefixed `PrtgLock`, so that a block written inside the module
reaches its own cmdlet's variables rather than the lock's. The prefix is ugly and
deliberate: without it the shadowing is silent, and the block gets a wrong value
rather than an error.

## What the prefix does and does not protect

Measured on macOS pwsh 7, Windows PowerShell 5.1 x64, and 32-bit Windows
PowerShell 5.1, all three agreeing:

- A block defined **inside the module** and passed through an unprefixed frame is
  shadowed. A test block reading `$File` and `$Depth` received the intervening
  frame's values, not its own cmdlet's. Through a prefixed frame it received its
  own cmdlet's values, correctly.
- A block supplied by the **sensor author** is not affected either way. It carries
  its own SessionState across the module boundary, so it resolves names against
  the caller's scope regardless of what the module's frames are called. Passing a
  block to `Use-PrtgCachedResult` whose names collide with every local in the
  cache's own block returned the caller's values for all of them.

So the prefix exists for the module's own four state-store block bodies in
`Save-`, `Get-`, `Clear-PrtgSensorState` and `Use-PrtgCachedResult`, which reach
`$Value`, `$Depth`, `$MaxEntries`, `$Key`, `$MaxAge`, `$SkipNullCache`,
`$ScriptBlock` and `$pruneMode` by dynamic lookup. The resolved store paths are
not among them: they arrive as the explicit `$PrtgOpState` argument, which is
rule 2 below applied. The prefix never had anything to do with protecting the
sensor author's block.

## Consequences

Any future module function that accepts a script block and invokes it is a new
frame in the same chain and needs the same treatment. Two rules follow:

1. Prefix every parameter and local of such a function with a name unique to it.
   A new parameter added later without the prefix reopens the hole silently.
2. Prefer passing what the block needs as an explicit argument
   (`& $block $path`, with `param($Path)` inside the block) over letting the
   block resolve it up the chain. That removes the hazard instead of managing it,
   and is the approach chosen for the atomic-write hooks.

The cost of a second frame is therefore not just the prefix. A frame that owns
more of the operation has a larger name surface to keep clear, because the names
it naturally wants are the ones the existing blocks already use.
`Invoke-PrtgStateOperation`, the envelope that owns resolve-then-lock for all
four cmdlets, is that second frame and carries the prefix `PrtgOp`.

## A closure is not the third option

The obvious way to avoid both the prefix and the explicit argument is to make the
block a closure, so it resolves names against its defining scope instead of the
dynamic chain. It is a dead end, recorded here so it is not rediscovered.

Measured on 32-bit Windows PowerShell 5.1, Windows PowerShell 5.1 x64, and
pwsh 7, all three agreeing:

- A closure does defeat the shadowing. A block reading `$File` through a frame
  declaring an unprefixed `$File` parameter received the frame's value; the same
  block after `.GetNewClosure()` received its own scope's value.
- A closure also severs the block from the module's private functions. Calling
  `Test-PrtgWindows` from a plain block inside the module succeeded; from the
  closure it failed with `CommandNotFoundException` on all three hosts.

All four `-PrtgOpBlock` bodies call at least one private function, so the second
result is fatal rather than a trade-off. The prefix plus the explicit argument
stays the answer.

## Notes on a review that proposed consolidating these frames

An architecture review of 23 August 2026 proposed a single
`Invoke-PrtgStateOperation` owning resolve, lock, load, freshness and write-back.
Three of its supporting claims do not survive a read of the code, and are
recorded here so they are not relied on again:

- It states all four cmdlets perform the same five-step sequence. `Save-` has no
  freshness step at all, and `Get-` applies `-MaxAge` **outside** the lock, while
  `Clear-` and `Use-PrtgCachedResult` apply it inside.
- It calls the cache's 30 second lock timeout a silent divergence from the other
  cmdlets' 10. It is documented and deliberate, because waiting sensors hold out
  for the duration of a sibling's fetch. Per-cmdlet defaults must be preserved.
- It counts three contradictory orderings of "newest". `Select-Object -Last` in
  `Save-PrtgSensorState` is append order and is consistent. The real
  contradiction is recorded in ADR 0002.
