# PrtgSensorKit - how we work here

PowerShell module for PRTG EXEXML sensors. The real runtime is **32-bit Windows
PowerShell 5.1 under a PRTG probe**.

## Local Environment

@AGENTS.local.md

## Comment style

State the constraint the code cannot show. No development narrative

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
