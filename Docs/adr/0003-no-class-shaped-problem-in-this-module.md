# There is no class-shaped problem in this module

The module keeps its two candidate types as plain custom objects carrying a typed
name: the output document, and the channel object `New-PrtgChannel` returns.
Neither becomes a PowerShell class. The proposal has been raised and withdrawn
more than once, and each time the same measurements are repeated, so the reasons
are recorded here rather than rediscovered.

## The output document

A class does not remove the thin wrappers. `Add-PrtgChannel`, `Set-PrtgMessage`,
`Get-PrtgMessage`, `Clear-PrtgOutput` and `Write-PrtgOutput` exist because the
module-scope document is not something a sensor author holds a reference to; they
would still exist as cmdlets around an instance, doing the same work.

The document will not grow behaviour to justify methods either. Its shape is
fixed by the monitoring product, not by this module: a `prtg` object holding
`result` and `text`. A different shape is not a method added to this type, it is
a different output standard adopted wholesale, at which point the type is
rewritten rather than extended.

## The channel object

Dynamic parameters are a function feature. `New-PrtgChannel` decides which
companion parameters exist from the bound `-Unit`, which a class constructor
cannot do, so a class would need a function wrapper anyway and that wrapper
carries the entire parameter surface regardless. The class buys nothing and adds
a second place the surface is written down.

The emitted shape settles it. A class instance serializes every property it
declares, while a channel must emit only what was set. The vendor manual is what
makes that a defect rather than a curiosity: it distinguishes an element that is
absent from one set to a default, so an unset field must be missing from the
JSON and not present as `null`. `New-PrtgChannel` achieves that by adding note
properties only for bound parameters, which a fixed set of class properties
cannot express.

Reference: <https://www.paessler.com/manuals/prtg/custom_sensors#advanced_elements>

## What is not a reason

Two arguments for the change were measured and came out neutral. They are
recorded so they are not re-run as though they were open questions.

- **Serialization.** `ConvertTo-Json` produces identical output for the document
  as a custom object and as a class instance. There is no serialization gain.
- **Stale types on reimport.** The hazard where an old class definition survives
  a module reimport and a new instance fails to match it did not reproduce on
  either host tested. It is not an argument against classes here.

## The constraint underneath both

A validation set cannot take a variable: `[ValidateSet()]` arguments must be
compile-time constants. The generator interface that would allow a computed set,
`IValidateSetValuesGenerator`, does not exist on the 32-bit Windows PowerShell
5.1 that the monitoring probe starts, confirmed on that host. Any future attempt
to data-drive a parameter surface, class-based or not, hits this first: the unit
list and the companion parameters have to be written out literally, and adding a
unit stays two edits.

## Consequence

The existing idiom is the right one: a plain custom object with a typed name
(`PSTypeName`), built by a function that decides which properties to attach. It
gives the type identity a format file or a parameter type constraint can bind
to, without committing the emitted shape to a fixed property set.
