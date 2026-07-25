# Architecture decision records

Use an ADR for a durable decision that changes the architecture, operational
model, security boundary, or evaluation method. ADRs preserve *why* a choice was
made; `DESIGN.md` describes the current system.

Use ascending filenames such as `0001-single-node-k3s.md`. Once accepted, do not
rewrite an ADR to hide a superseded decision; create a new ADR that supersedes
it instead.

## Template

```md
# ADR-NNNN: Title

**Status:** proposed | accepted | superseded by ADR-NNNN
**Date:** YYYY-MM-DD

## Context

What constraint or problem requires a decision?

## Options considered

What viable choices were compared?

## Decision

What was selected, and why?

## Consequences

What benefits, limitations, risks, and follow-up work result?

## Validation

How will this decision be tested or measured in this repository?
```
