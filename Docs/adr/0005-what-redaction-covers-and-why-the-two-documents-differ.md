# Redaction covers message text, and the two response documents stay apart

Three verdicts about the module's output path. They are one record because they
are one review surface: a reader working down `Write-PrtgOutput`,
`Write-PrtgError`, `Format-PrtgMessage` and `PrtgRedaction.ps1` meets all three
in the same sitting, and each has now been re-proposed by someone who could not
have known it was already decided. Splitting them would leave the third
homeless, and the third is the one a reader reaches precisely by accepting the
first two.

## Redaction covers message text and log lines, and nothing else

`Protect-PrtgSecretText` runs at exactly two sites: `Format-PrtgMessage`, the
chokepoint every sensor message and every error text passes through, and
`Write-PrtgLog`, where the same values would otherwise land on disk. Channel
names and channel values are not masked, and the manual
`Set-PrtgOutput` / `Write-PrtgOutput` path is not masked.

This is deliberate. The masking exists because the monitoring product resolves
credential placeholders before it displays a sensor's output, so a password
echoed back inside an exception message reaches the screen in the clear. That is
a leak of a value the module knows to be secret, arriving in text the sensor
author never inspected. It is defence in depth over an accident, not a
classification boundary.

Channel names and values are the sensor author's own data. The product stores a
channel under its name, graphs it under that name, and carries the name across
sensor edits. Masking one would rename a channel the product is already tracking
and break its history, to protect a string the author chose and typed. If an
author puts a credential in a channel name, the fix is the sensor script.

The consequence is stated where it can be acted on: `Format-PrtgMessage`'s help
says outright that it is not a chokepoint for everything PRTG receives, and
names the two paths that bypass it.

## The output document and the error document are different responses

`New-PrtgOutputDocument` produces `prtg.result` plus `prtg.text`.
`Write-PrtgError` produces `prtg.error` plus `prtg.text`. They are not two cases
of one type and do not get a shared shape.

They answer different questions. One says what the sensor measured, and its
channels are the answer. The other says the sensor could not measure, and its
message is the answer; the product treats it as a distinct kind of response and
shows no channels for it. Their shapes are fixed by the monitoring product, not
by this module, so a unified type would have to carry every field of both and
suppress the wrong half per call - which is the emitted-shape problem 0003
already rules out for the output document.

The lifetimes differ too. The output document is module-scope state, built once
at import and mutated by `Add-PrtgChannel` and `Set-PrtgMessage` across a whole
run. The error document is a local built in one statement and serialized in the
next; there is nothing to hold.

Reference: <https://www.paessler.com/manuals/prtg/custom_sensors>

## The shared response tail is not extracted

`Write-PrtgOutput` and `Write-PrtgError` end in the same two lines: a call to
`Set-PrtgConsoleEncoding`, then `Write-Output` of the document piped through
`ConvertTo-Json -Depth 10`. They stay inline in both.

This one is named explicitly because a reader who has just accepted that the two
documents are unrelated will look down, see two identical tails, and propose
hoisting them anyway.

They are identical by coincidence of the two shapes, not by a shared contract.
Nothing keeps them identical: the encoding call is there because each cmdlet is
a possible last statement of a sensor process, and the depth argument is a
property of the document each one happens to serialize. A tail function would
assert that the two responses are emitted the same way by rule, which is exactly
the claim the section above denies, and it would put a hop between a two-line
cmdlet and what it emits.

## Consequence

Each of the three is answered by this file alone. A proposal to mask channel
names, to unify the two documents, or to extract the tail reopens one of them
only with evidence that its reason no longer holds: a product that stops
resolving placeholders into displayed output, a product that merges the two
response shapes, or a third caller that genuinely has to emit by the same rule.
