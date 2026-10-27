# Progress — redesign

## 2026-08-13

- Started a new scoped planning record under `.planning/redesign/`; left the previous root planning files untouched.
- Read the complete `planning-with-files-zht` workflow and located all required source artifacts.
- Read the beginning/current history of the prior root plan and progress log to recover context.
- Recorded the unavailable `rg` command and switched repository inspection tools.
- Current phase: source review.
- Read both current rejection lenses in full. Captured all eleven true-hit findings and the convergent remedies: eliminate post-hoc stream barriers, keep health/reconnect with the socket owner, expose authoritative status, and match state granularity to the detected condition.
- Read `IMPLEMENTATION.md` §§1 through the beginning of §4 and indexed the three most relevant prior-review sections in `findings.md`.
- Finished `IMPLEMENTATION.md` and read the first half of the seven-round findings history. Captured stable functional/API contracts and discarded mechanisms that repeatedly expanded into unimplementable coordination protocols.
- Read the remainder of `findings.md`, including the complete round-7 and revision-4.3 histories.
- Checked official Apple and Coinbase documentation for the concrete WebSocket operations and timestamped public candle contract. Chose an unconditional connection lease instead of a forbidden ping loop, and venue candles instead of pretending timestamp-free CoinGecko points describe 24 hours.
- Checked official Binance Spot documentation for combined streams, control-frame limits, 24-hour socket lifetime, ticker update-speed wording, and timestamped klines. Source review is complete; architecture decision work is active.
- Re-read the scoped plan and findings before authoring. Reconciled two provisional notes with the final decisions. Architecture decisions are complete; `SPEC.md` authoring is active.
- Created `SPEC.md` (628 lines) with standalone product behavior, module/concurrency ownership, data/schema contracts, lifecycle and fallback algorithms, clock table, build/packaging rules, mechanism accountability ledger, focused acceptance tests, and explicit omissions.
- Initial audit confirmed the required old mechanisms appear only as explicit exclusions and that the repository’s pre-existing modifications to `IMPLEMENTATION.md` and root planning files remain present but were not edited by this redesign.
- Consistency audit found and fixed a retry-reset weakness: a first-tick reset could still churn when the peer sent one tick then closed. Reset now requires survival of the existing five-minute lease, or an explicit set/wake context change.
- Tightened three interface edges during audit: accepted Binance product IDs map only through current persisted mappings, first alert enable persists before requesting notification permission, and Coinbase `live` requires the latest completed eligible request to have succeeded.
- One multi-hunk patch failed because its contexts were ordered backwards; no file changed. Reapplied it in file order and recorded the tooling error.
- Replaced inferred socket-open state with the real `URLSessionWebSocketDelegate` open/close contract, specified an idempotent identity-bound failure transition, and made REST/WebSocket payload limits concrete (5 MiB / 1 MiB).
- Defined product replacement while suspended, exact sleep/wake identity invalidation, empty-set behavior during sleep, and added the 90-minute chart-gap quantity to the clock table.
- Made persistence date coding exact (`.iso8601`) and extended acceptance coverage for suspended replacement and concrete payload-size/HTTP boundaries.
- First measured-fact check falsely reported the CoinGecko uniqueness sentence missing because Markdown emphasis split the literal string. The content was present; recorded the checker error and changed the audit to normalize emphasis.
- Tightened retry reset again after observing that lease completion alone could include a hanging or last-second handshake. Reset now also requires 60 awake seconds since the matching platform `didOpen` callback.
- Made open-instant clearing explicit on set replacement, failure, sleep, wake preparation, and shutdown so stability evidence cannot leak between connections.
- Corrected startup ordering so the support directory exists before the atomic process lock, and specified read-only behavior when the first seed cannot be persisted. A second non-monotonic patch-context failure changed nothing before the ordered retry; the plan error count was updated.
- The first placeholder audit matched the accountability ledger’s intentional phrase “required input ... absent,” not a placeholder. Recorded the false positive and narrowed the check.
- The narrowed placeholder audit then matched the planning error record naming placeholder tokens. No deliverable defect existed; final scan is correctly scoped to `SPEC.md`.
- The next measured-fact scan found a second markup-only mismatch around inline code (`symbols=`/`-1102`). The sentence is verbatim; final audit normalizes both emphasis and backticks.
- Full human read found the original 5 MiB REST-body cap could reject Binance’s whole-market catalog. Raised the concrete common cap to 64 MiB while retaining a strict pre-decode bound.
- Made the three-state row mapping exhaustive for “connected but no first quote”: it is stale while acquisition is possible/in progress, and offline only when no source is connected, connecting, or requesting.
- One contract-check string used “latest” while the specification says “most recent”; no content was missing. Recorded and corrected the exact-string audit.
- Final audits passed: measured facts, mechanism/interface presence, required contract coverage, placeholder absence, balanced Markdown fences, and trailing whitespace.
- Completed all five phases. Created only the requested specification/planning artifacts and handoff summary; wrote no Swift implementation.
