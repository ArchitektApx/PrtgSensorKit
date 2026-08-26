# PrtgSensorKit

A PowerShell module for writing PRTG EXEXML sensors. It gives sensor authors the
things a sensor script needs but should not have to build: channel output, state
that survives between runs, secrets, logging, and a doctor that checks a script
before PRTG does.

## Language

### Sensor output

**Output document**:
The single in-memory object a sensor run builds, carrying the result and text
shape the monitoring product expects: the channels measured this run and the
message shown beside them. The output cmdlet serializes it at the end of the
run, and that serialized form is the whole of what PRTG sees.
_Avoid_: response document, output object, sensor state

**Channel**:
One measured value in a sensor run, with the unit and display settings the
monitoring product needs to chart it. A channel is built on its own and then
added to the output document; building one and adding it are separate steps, so
a channel can exist without ever reaching the output.

### On-disk stores

**Store**:
A folder the module owns on the sensor host, holding one kind of data. There are
exactly three: the State store, the Secrets store, and the Log store.

**State store**:
The store holding sensor state and shared cache data. Not secret: values are
written unencrypted and the files carry no ACL hardening.
_Avoid_: cache store, state cache

**Secrets store**:
The store holding DPAPI-protected secrets, each file locked to the account that
saved it. Windows only.

**Log store**:
The store holding sensor log files.

### State

**State entry**:
One `{Value, Timestamp}` pair in a key's history. Timestamps are UTC.

**History**:
The ordered list of State entries for one key. Newest is decided by timestamp,
with ties going to the entry appended last.

**Shared cache**:
A State entry read under a freshness policy, so that several sensors on one
device share a single expensive fetch. It is a way of *reading* the State store,
not a fourth store: same folder, same file format, same key namespace, and the
state cmdlets manage it.
_Avoid_: cache store, cache file (as a distinct kind of file)

**Lock sidecar**:
The `.lock` file next to a state file, whose open handle serializes access across
overlapping sensor runs. A leftover zero-byte sidecar is normal and harmless.

### Corruption reporting

**Malformed entry**:
An entry in an otherwise readable state file that is not a well-formed
`{Value, Timestamp}` pair. Malformed entries are dropped, and the rest of the
file is still used.

**Unreadable file**:
A state file that cannot be deserialized at all, so none of its entries survive.
Distinct from a malformed entry, which is a problem with one entry rather than
the file.

**Consequence clause**:
The part of an unreadable-file warning that tells the operator what the calling
cmdlet is about to do to that file: replace it, treat it as empty, delete it, or
refetch. It differs per caller and is the operator's only signal about what
happens to their data next.

### Doctor

**Check**:
One rule the doctor applies to a sensor script, identified by a stable code the
operator sees and reports. A check decides its own verdict and owns the wording
of every message it can emit, including the wording it uses when the script
passes.

**Finding**:
What a check returns: its code, a severity, and the message the operator reads.
A check returns one finding, or one per offending site where the rule can be
broken in more than one place.

**Parse context**:
The whole-script analysis a run performs once and every check reads from, so
that adding a check costs no extra pass over the script.

**Effective target host**:
The host a sensor script ends up running in after any restart helper it uses,
decided as pwsh over 64-bit over 32-bit. Distinct from the host PRTG starts,
which is always the 32-bit host no matter what the script restarts into.
