# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root: the glossary.
- **`Docs/adr/`**: read ADRs that touch the area you're about to work in.

This repo is single-context. The skill also supports a multi-context layout, keyed off a
`CONTEXT-MAP.md` at the root pointing at one `CONTEXT.md` per context, with context-scoped
ADRs beside each; none of that applies here and there is nothing to look for.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

```
/
|-- CONTEXT.md
|-- Docs/adr/
|   |-- 0001-prtglock-prefix-for-block-passing-frames.md
|   `-- 0002-state-timestamps-compare-in-utc.md
`-- Source/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0003 (no class-shaped problem in this module), but worth reopening because..._
