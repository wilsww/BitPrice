# Task plan: BitPrice UI rework

## Goal
Implement the app icon, textual menu-bar price, larger typography, compact selectable rows, and a bottom chart/detail area without changing non-UI behavior or concurrency contracts.

## Current phase
Complete

### Phase 13: Implement macOS font scaling and header icon alignment
- [x] Read the current UI6 sources and restore planning context
- [x] Replace ignored macOS dynamic type behavior with one central scaled-font helper
- [x] Switch header icons to visually matched circled symbols
- [x] Add Medium/base-size and multiplier regression coverage
- **Status:** complete

### Phase 14: Verify and record UI6
- [x] Run final strict build, tests, bundle checks, and audits after the last source edit
- [x] Record the macOS DynamicTypeSize platform finding and accepted tradeoff
- [x] Write `.codex-implement/_codex_impl_summary_ui6.md`
- **Status:** complete

## UI6 completion
- `PanelFont` is the sole fixed-size font construction point; the medium multiplier remains exactly 1.0 and all four steps are covered by tests.
- Final strict build and bundle checks passed. The full harness reports 31 passed, 0 failed, and 2 expected no-Aqua skips.
- No Aqua GUI session was available, so Medium visual parity, Extra Large usability, and circled-icon balance still need desktop confirmation.

### Phase 15: Implement add-coin layout, disclosure, and entity decoding
- [x] Read current add-coin, REST parsing, test, and planning context
- [x] Move Cancel to the leading edge and establish coin/market hierarchy
- [x] Disclose Binance live-source and Coinbase fallback roles and Add's enabling rule
- [x] Scale and space the Back/Add controls through the central font helper
- [x] Decode CoinGecko HTML entities at the search parsing boundary
- [x] Add focused entity-decoding and search-boundary coverage
- **Status:** complete

### Phase 16: Verify and record UI7
- [x] Run strict build, full tests, bundle checks, and source-policy audits
- [x] Record layout/data tradeoffs and no-Aqua limitations
- [x] Write `.codex-implement/_codex_impl_summary_ui7.md`
- **Status:** complete

## UI7 completion
- Add coin now uses a leading Cancel, centered title, explicit Coin/Markets hierarchy, role-labeled venue cards, visible Add eligibility rules, and scaled bordered Back/Add controls.
- CoinGecko search identity text is decoded at the REST parsing boundary for named and numeric entities; unknown and bare ampersands remain unchanged.
- Final build, test, bundle, and source-policy checks passed. No Aqua GUI session was available for visual confirmation.

### Phase 17: Implement Settings setting cards
- [x] Read current SettingsView and repository verification context
- [x] Group Price alerts and Text size into padded, subtly tinted cards
- [x] Add the Text size explanation while preserving existing bindings, header, footer, and empty region
- **Status:** complete

### Phase 18: Verify and record UI8
- [x] Run strict build, full tests, bundle checks, and source-policy audits
- [x] Record the card-spacing decision and no-Aqua limitation
- [x] Write `.codex-implement/_codex_impl_summary_ui8.md`
- **Status:** complete

## UI8 completion
- `SettingsView` now presents separate Price alerts and Text size cards with titled controls, compact internal spacing, and a visibly larger gap between cards.
- The existing header, bindings, read-only behavior, footer/error lines, shared frame, and empty region remain unchanged.
- Strict build, existing tests, bundle checks, and source-policy audits passed. No Aqua GUI session was available for visual confirmation.

### Phase 11: Implement Settings layout, text-size preference, and icon scaling
- [x] Read the current UI5 sources, planning records, tests, and build scripts
- [x] Add persisted stable text-size preference with default-medium fallback
- [x] Apply root dynamic type and preference-sized panel; revise Settings header and switch
- [x] Scale requested glyphs with Dynamic Type and add focused persistence tests
- **Status:** complete

### Phase 11 verification checkpoint
- `bash scripts/run-tests.sh`: 30 passed, 0 failed, 2 expected no-Aqua skips.
- `bash scripts/build-app.sh`: passed with strict Swift 6 warnings-as-errors and bundle verification.

### Phase 12: Verify and record UI5
- [x] Run strict app build, bundle checks, full tests, and forbidden-API audits
- [x] Review schema/network/concurrency scope and preserve NotificationService
- [x] Record tradeoffs and no-Aqua limitations in `.planning/ui/`
- [x] Write `.codex-implement/_codex_impl_summary_ui5.md`
- **Status:** complete

## UI5 completion
- The text-size preference is a stable string with canonical medium fallback; schema version remains 1.
- The requested four panel dimensions are used exactly, and the centered Settings title is isolated from unequal control widths with a full-width ZStack.
- No Aqua visual verification was possible.

## Current phase
Complete

## Phases

### Phase 1: Inspect requirements and implementation
- [x] Read all requested project files and relevant tests/scripts
- [x] Record current architecture and constraints in findings.md
- **Status:** complete

### Phase 2: Implement presentation changes
- [x] Add reproducible icon generation and bundle integration
- [x] Change MenuBarExtra to a text label sourced from `menuBarTitle`
- [x] Redesign rows, selection, and detail area with larger Dynamic Type styles
- [x] Add or update deliberate presentation tests
- **Status:** complete

### Phase 3: Verify and repair
- [x] Run strict app build and inspect bundle icon/plist/signing/linkage
- [x] Run all tests
- [x] Review diff for scope and hard-constraint compliance
- **Status:** complete

### Phase 4: Record and hand off
- [x] Complete planning records with tradeoffs and GUI limitation
- [x] Write `.codex-implement/_codex_impl_summary_ui1.md`
- **Status:** complete

### Phase 5: Implement quit and add-coin follow-up
- [x] Route quit confirmation through a dedicated inline `PanelRoute` case
- [x] Move the list quit affordance to the far-left header position
- [x] Align and resize search-result and venue-candidate rows
- [x] Compact the confirm-markets content and actions without changing the panel frame
- **Status:** complete

### Phase 6: Verify and record follow-up
- [x] Run strict app build and full tests
- [x] Verify plist, signing, linkage, icon, forbidden presentation APIs, and diff hygiene
- [x] Record layout tradeoffs and no-Aqua limitation
- [x] Write `.codex-implement/_codex_impl_summary_ui2.md`
- **Status:** complete

### Phase 7: Implement chart axes, larger type, and primary-coin guidance
- [x] Add pure axis helpers and cover normal, flat, and single-point ranges
- [x] Draw price/time axes from actual chart points while preserving gap breaks
- [x] Raise Dynamic Type styles and resize the panel/detail layout
- [x] Clarify the existing primary-coin star control and add an inline hint
- **Status:** complete

### Phase 8: Verify and record UI follow-up
- [x] Run strict build, bundle checks, and full tests
- [x] Audit added lines for forbidden presentation/shortcut APIs and scope
- [x] Record tradeoffs, no-Aqua limitations, and implementation summary
- **Status:** complete

### Phase 9: Implement settings, global alert gate, and precise chart ticks
- [x] Read the current UI4 sources, persistence model, alert engine, tests, and build scripts
- [x] Add inline Settings routing, immediate quit, and the persisted global alert switch
- [x] Round axis labels/gridlines while preserving real plotting bounds
- [x] Add focused alert, v1-default, and dual-scale axis tests
- **Status:** complete

### Phase 9 verification checkpoint
- `bash scripts/run-tests.sh`: 28 passed, 0 failed, 2 expected no-Aqua skips.
- `git diff --check`: passed.

### Phase 10: Verify and record UI4
- [x] Run strict app build, bundle checks, full tests, and forbidden-API audits
- [x] Review scope and preserve NotificationService/concurrency/network behavior
- [x] Record tradeoffs and the no-Aqua limitation in `.planning/ui/`
- [x] Write `.codex-implement/_codex_impl_summary_ui4.md`
- **Status:** complete

## UI4 completion
- Strict app build and bundle checks passed; no Aqua GUI launch was attempted.
- The precision tradeoff is a span-derived fixed decimal count with uniqueness protection; labels use that count while plotting keeps true min/max bounds.
- The global switch intentionally suspends evaluation and does not re-arm or add a grace period.

## Current phase
Complete

## Key questions
1. How are watched assets identified and deleted, so selection can fall back safely?
2. How are chart venue/quote disclosure and stale/failure states currently derived?
3. What icon-generation mechanism is available without third-party assets or a GUI?

## Decisions
| Decision | Rationale |
|---|---|
| Keep UI selection local to the panel view | Selection is presentation state and must remain distinct from persisted primary selection. |
| Preserve inline `PanelRoute` editors | Separate presentations close a `.window` MenuBarExtra panel. |
| Use single-selection `List(selection:)` tagged by item UUID | Makes the row selectable without nesting the star and Alert buttons inside another button. |
| Put reorder and direct delete controls in the selected detail area | Removes row clutter while keeping structural controls explicit and inline. |
| Draw PNGs headlessly with Core Graphics, then package them with `iconutil` | Produces an original, reproducible icon without downloads, GUI tools, or third-party assets. |

## Errors
| Error | Attempts | Resolution |
|---|---:|---|
| `rg` is unavailable on this host | 1 | Use `find`, `grep`, and `sed` as the documented fallback. |
| Icon-generator `swiftc` tried to write its default module cache under `~/.cache` | 1 | Give the generator a private module cache inside its temporary work directory. |
| macOS 15.6 `iconutil -c icns` rejects complete valid-size iconsets, including one it extracted from Apple's Dock icon | 2 | Keep the required pack attempt, then fall back to a deterministic ICNS container; validate by decoding it with `iconutil -c iconset`. |
| A diagnostic command containing `rm -rf build/IconDebug.iconset` was rejected by the execution safety layer | 1 | Used a uniquely named `mktemp` debug directory instead; no project data was removed. |
| A combined patch expected a duplicated chart-call line that was only an output-display artifact | 1 | Re-read the exact source range and applied the source/test edits against the actual text. |
