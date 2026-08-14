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

### Phase 19: Remove duplicated Settings card labels
- [x] Read current SettingsView and repository verification context
- [x] Make card headings primary and hide duplicate control labels
- [x] Preserve accessibility names, control structure, bindings, and all UI8 spacing/content
- **Status:** complete

### Phase 20: Verify and record UI9
- [x] Run strict build, full tests, bundle checks, and source-policy audits
- [x] Inspect each card for a single visible setting name
- [x] Record the accessibility and no-Aqua limitations
- [x] Write `.codex-implement/_codex_impl_summary_ui9.md`
- **Status:** complete

## UI9 completion
- The two Settings cards now show one visible setting name each through bold primary headings; Toggle and Picker labels are hidden visually but retain explicit accessibility names.
- UI8 card structure, spacing, explanations, header, footer/error lines, bindings, read-only behavior, and shared frame remain unchanged.
- Strict build, existing tests, bundle checks, and source-policy audits passed. No Aqua GUI session was available for visual confirmation.

### Phase 21: Implement detail supporting-text trim
- [x] Read current SelectedCoinDetail and repository verification context
- [x] Remove the redundant starred-coin hint while preserving row help text
- [x] Condense mapping IDs into one selectable, truncated line with prefixes, absence markers, and full-text help
- **Status:** complete

### Phase 22: Verify and record UI10
- [x] Run strict build, full tests, bundle checks, and source-policy audits
- [x] Inspect preservation of chart/stale disclosures and reorder/delete controls
- [x] Record the mapping-summary and no-Aqua limitations
- [x] Write `.codex-implement/_codex_impl_summary_ui10.md`
- **Status:** complete

## UI10 completion
- Selected detail now has no repeated starred-coin hint, while row star help text remains intact.
- Mapping IDs are one selectable, tail-truncated, venue-prefixed line with explicit absent-mapping markers and full-text help.
- Strict build, existing tests, bundle checks, and source-policy audits passed. No Aqua GUI session was available for visual confirmation.

### Phase 23: Implement flexible chart detail and directional fill
- [x] Read current ContentView/SelectedCoinDetail/Sparkline and repository verification context
- [x] Replace fixed list/detail heights with a bounded shared layout and finite chart height
- [x] Preserve reachability at Extra Large and keep empty-detail sizing consistent
- [x] Add change-direction chart stroke/fill with gap-safe gradient segments
- [x] Inspect tall-chart axis/layout behavior and document the baseline decision
- **Status:** complete

### Phase 24: Verify and record UI11
- [x] Run strict build, full tests, bundle checks, and source-policy audits
- [x] Record the ScrollView unbounded-height finding and container strategy
- [x] Write `.codex-implement/_codex_impl_summary_ui11.md`
- **Status:** complete

## UI11 completion
- List/detail now share a bounded layout-derived region; the chart receives finite remaining height and grows with the text-size panel frame while retaining a sensible floor and overflow scrolling.
- Gradient fill follows the row quote direction and breaks across the existing 90-minute gaps; no fabricated baseline was added.
- Strict build, existing tests, bundle checks, and source-policy audits passed. No Aqua GUI session was available for visual confirmation.

### Phase 25: Replace estimated detail sizing with measured layout
- [x] Read the current detail container and chart implementation
- [x] Remove the detail ScrollView/minHeight pairing and multiplier-based height estimate
- [x] Let a finite detail VStack allocate remaining height to the chart while preserving the chart floor
- [x] Keep empty and populated detail branches aligned and preserve all chart drawing behavior
- **Status:** complete

### Phase 26: Verify and record UI12
- [x] Reason through Medium, Extra Large, and no-scroll-indicator cases
- [x] Run strict build, full tests, bundle checks, and source-policy audits
- [x] Record why estimate-and-subtract failed and the measured-container strategy
- [x] Write `.codex-implement/_codex_impl_summary_ui12.md`
- **Status:** complete

## UI12 completion
- The normal selected-detail path now uses `ViewThatFits` to choose a plain finite detail stack first; its chart greedily fills the measured remainder after naturally sized siblings.
- The 140-point chart floor is retained. Only the fallback path, selected when the measured stack plus floor cannot fit, uses a detail `ScrollView`; empty/no-selection branches retain the same detail-region height.
- The prior guessed reserve and `minHeight`/`ScrollView` pairing are gone. Strict build/tests and source-policy audits passed; no Aqua GUI session was available.

### Phase 27: Add chart-open baseline and trim detail heading
- [x] Read the current SelectedCoinDetail/Sparkline and axis tests
- [x] Remove the redundant `details` heading word
- [x] Add a first-candle-close helper with degenerate-case coverage
- [x] Draw a rounded-precision labelled dashed baseline behind the existing fill/stroke
- **Status:** complete

### Phase 28: Verify and record UI13
- [x] Run strict build, full tests, bundle checks, and source-policy audits
- [x] Confirm plot bounds, gap-safe fill, and measured layout remain unchanged
- [x] Record the baseline source/label and no-Aqua limitation
- [x] Write `.codex-implement/_codex_impl_summary_ui13.md`
- **Status:** complete

## UI13 completion
- Selected detail now shows the symbol and quote asset without the redundant `details` suffix.
- The chart baseline is the first candle close for series with at least two points, labelled with the existing axis precision and drawn behind the unchanged fill/stroke.
- Baseline helper tests cover normal, flat, single-point, and empty series. Strict build/tests and bundle/source audits passed; no Aqua GUI session was available.

### Phase 29: Redraw the programmatic app icon
- [x] Read the current icon generator and packaging/verification path
- [x] Replace the rounded rectangle with a documented sampled squircle approximation
- [x] Remove gradients, rim, shadow, and coin disc in favor of a flat orange tile and white glyph
- [x] Add proportional/small-size glyph treatment with no secondary motif
- **Status:** complete

### Phase 30: Verify and record icon redraw
- [x] Build/package the icon and confirm all ten renditions decode
- [x] Check 16×16 and 32×32 pixels are nonblank and not single-colour
- [x] Run strict app build, full tests, bundle checks, and source-scope audits
- [x] Record the approximation, small-size decision, and no-GUI limitation
- [x] Write `.codex-implement/_codex_impl_summary_icon1.md`
- **Status:** complete

## Icon1 completion
- The icon is now a flat Bitcoin-orange sampled n=5 superellipse tile with a white glyph, no coin disc, gradients, rim, or shadow, and no secondary price/trend motif.
- Small-size glyph rendering uses a proportional branch with a 1.6-pixel minimum stroke at 16×16. All ten ICNS renditions decoded, and 16×16/32×32 pixel checks passed.
- Strict app build/tests and source-scope audits passed. No GUI session was available to judge the final system-icon balance.

### Phase 31: Implement baseline axis tick and Settings app identity
- [x] Move the first-close baseline label from the plot into the Y-axis tick column
- [x] Suppress colliding ordinary ticks without nudging labels or changing true plot bounds
- [x] Add the runtime app icon and conditional bundle-derived identity block to Settings
- [x] Extend axis tests for far, colliding, minimum-bound, and flat baselines
- **Status:** complete

### Phase 32: Verify and record UI14
- [x] Run the strict test/build scripts and confirm bundle resources/checks
- [x] Audit forbidden APIs, fixed-font placement, baseline source, and icon source
- [x] Record collision behavior, flexible Settings decoration, and no-Aqua limitations
- [x] Write `.codex-implement/_codex_impl_summary_ui14.md`
- **Status:** complete

## UI14 completion
- The baseline is now a true, shared-precision Y-axis tick with bold/color/`24h open` cues; ordinary ticks near it are dropped, including coincident bound ticks.
- Settings shows the running bundle icon and only available bundle name/version fields in the existing dead space, with lower layout priority than real settings content.
- Tests/build and scope audits pass. Human desktop confirmation remains required because this host has no Aqua GUI session.



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

## UI16 completion
- The Y-axis left inset is now derived from the actual resolved label widths, with the selected ticks computed first from height and a width-derived 40% cap.
- Capped labels truncate using the same text/font resolver; no fallback inset constant, precision change, tick-rule change, or plot-bound change was introduced.
- Strict tests/build and source audits passed. No Aqua GUI session was available for visual confirmation.

## UI15 completion
- The baseline is marked by a compact filled diamond and shared-precision value; its tooltip preserves the lost explanatory words without widening the axis or adding an in-plot label.
- Settings identity now has intrinsic height and sits directly above the closing disclosure, with the existing flexible spacer above and negative layout priority preserved.
- Strict tests/build and source-scope audits passed. Desktop visual confirmation remains outstanding because the host has no Aqua GUI session.
