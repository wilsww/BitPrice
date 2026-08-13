# BitPrice implementation plan

## Goal
Build and verify the complete macOS menu-bar application described by `SPEC.md`, with all 15 review defects resolved explicitly.

## Current phase
Complete

## Phases

### Phase 1: Contract extraction and plan
- [x] Read the planning skill and required design inputs
- [x] Extract all interfaces, acceptance cases, and defect closures
- [x] Record implementation decisions in `findings.md`
- **Status:** complete

### Phase 2: Domain and persistence foundation
- [x] Implement domain/runtime models and exact v0/v1 wire DTOs
- [x] Implement validation, migration, atomic persistence, and process lock
- [x] Add canonical v0/v1 fixtures
- [x] Strict-compile the layer
- **Status:** complete

### Phase 3: Network and alert services
- [x] Implement deadline-bound REST transports, paced venue schedulers, and typed clients
- [x] Implement single-session WebSocket controller and delegate UUID authorization
- [x] Implement targeted alert decisions and notification abstraction
- [x] Strict-compile the layer
- **Status:** complete

### Phase 4: Application model and UI
- [x] Implement startup, atomic edits, quote/chart authorization, loops, and sleep/wake
- [x] Implement menu-bar views, search, mapping confirmation, alerts, and chart disclosure
- [x] Strict-compile the app
- **Status:** complete

### Phase 5: Bundle and deterministic acceptance tests
- [x] Implement direct-swiftc bundle and test scripts
- [x] Implement the adjusted acceptance suite without SwiftPM
- [x] Run tests and bundle validation (`plutil`, `codesign`, `otool`)
- **Status:** complete

### Phase 6: Audit and handoff
- [x] Map every one of the 15 defects to code and tests
- [x] Record additional specification defects and host limitations
- [x] Write `.codex-implement/_codex_impl_summary_impl1.md`
- **Status:** complete

## Decisions
| Decision | Reason |
|---|---|
| Use one main-actor feed controller with one lifetime URLSession | Required defect closure; avoids stale callback identity collisions |
| Use explicit v0/v1 DTOs and pure migration | Wire compatibility must be deterministic and fixture-backed |
| Use actor-owned paced request gates per venue | Enforces aggregate REST limits across all request kinds |
| Treat all request completions as capabilities represented by tokens | Prevents stale fallback/chart/search results from publishing |
| Keep lock and data files separate | Atomic replacement of `watchlist.json` cannot disturb `instance.lock` |

## Errors
| Error | Attempt | Resolution |
|---|---:|---|
| Required-reading command output was truncated | 1 | Re-read the specification and reviews in smaller bounded chunks |
| `swiftc` could not write the default Clang module cache under `~/.cache` | 1 | Pass a repository-local `-module-cache-path` in all compile scripts and checks |
| Throwing factory used directly in `StateObject` autoclosure | 1 | Bind the production model in the surrounding `do` before property-wrapper initialization |
| Optimized compile found task-group closure isolation missed by typecheck | 1 | Explicit immutable captures and `@Sendable` child closures |
| Recursive cache cleanup rejected by execution policy | 1 | Use a recoverable move to a validated temporary path |
