# BitPrice ground-up specification redesign

## Goal

Produce a standalone `SPEC.md` from which an implementer can build BitPrice, while preserving measured platform facts and solving every named lifecycle, durability, migration, clock, and round-7 defect with concrete interfaces and real platform APIs.

## Constraints

- Do not modify the prior `IMPLEMENTATION.md` or root planning files.
- Do not write Swift implementation code.
- Prefer a small architecture whose interfaces directly supply every mechanism input.
- Create only the requested redesign planning files, `SPEC.md`, and the implementation summary.

## Phases

1. **Source review — complete**
   - Read the previous specification, review history, and both current verdict lenses.
   - Extract measured facts, contradictions, confirmed defects, and accepted constraints.
2. **Architecture decisions — complete**
   - Select the minimal module and concurrency model.
   - Prove lifecycle, health detection, backoff, state observation, alert durability, migration, and clock contracts against their interfaces/APIs.
   - Resolve every round-7 open defect.
3. **Specification authoring — complete**
   - Write standalone architecture, data model, interfaces, functional behavior, packaging/build, and acceptance verification into `SPEC.md`.
4. **Consistency audit — complete**
   - Check every mechanism-input/API mapping, all timed quantities, schema paths, lifecycle transitions, and required facts.
   - Confirm prior files are untouched.
5. **Handoff — complete**
   - Complete redesign planning records and `.codex-implement/_codex_impl_summary_rd1.md`.

## Errors

| Error | Attempts | Resolution |
|---|---:|---|
| `rg` is not installed | 1 | Use `find`, `grep`, and `sed`; do not retry `rg`. |
| Multi-hunk patch used non-monotonic context order | 2 | Inspected exact contexts and reapplied hunks in file order; keep future multi-hunk patches ordered by line. |
| Literal measured-fact audit did not normalize Markdown markup | 2 | Normalize emphasis and inline-code backticks before fixed-string checks; both facts were present and correctly worded. |
| Placeholder audit produced self-referential false positives | 2 | Restrict placeholder scanning to deliverable `SPEC.md`; planning error records necessarily name the markers. |
| Contract audit used a synonym different from the specification | 1 | Check the exact normative wording (`most recent`) rather than an invented synonym (`latest`). |
