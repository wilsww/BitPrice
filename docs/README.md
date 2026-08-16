# BitPrice documentation

## Current

- [SPEC.md](SPEC.md) — the behavioural contract. Kept in step with the implementation, and the document to read before changing code.

User-facing instructions live in the [top-level README](../README.md).

## History

[history/](history/) holds superseded design documents. They are kept because they record how decisions were reached — including several rounds of adversarial review whose outcomes are still live in the code — but every one of them describes an architecture the implementation has since replaced.

| Document | What it was | Why it is superseded |
|---|---|---|
| `IMPLEMENTATION.md` | The v4 implementation specification | Describes dual-venue Binance/Coinbase mappings with fallback, per-row sparklines, and CoinGecko-only search. The app now uses one market per coin, adds OKX as a second push feed, and draws one chart for the selected row. |
| `IMPLEMENTATION_r32.md` | Revision 3.2, the predecessor to the above | Same divergence, one revision further back. Retained for its record of the four Codex review rounds that produced the alert-fire transaction ordering, the re-arm persistence fix, and the feed circuit breaker. |
| `findings.md` | Defect ledger from the implementation phase | Superseded by the per-phase ledgers under `.planning/`. |
| `progress.md` | Progress log from the implementation phase | Same. |
| `task_plan.md` | Task plan from the implementation phase | Same. |

Per-phase planning records — `impl`, `redesign`, and `ui` — are under [`.planning/`](../.planning/). The `ui` set is the most recent.

None of the documents in `history/` should be used as a build reference.
