# Progress log

## Session: 2026-08-13

### Phase 1: Inspect requirements and implementation
- **Status:** complete
- Actions:
  - Read the requested planning skill and its templates.
  - Checked repository status and existing planning directories.
  - Confirmed `rg` is unavailable and selected standard fallback tools.
  - Read `SPEC.md` §2.1, all of `Views.swift`, the app entry point, relevant `AppModel` APIs, current build/test scripts, plist, tests, and implementation findings.
  - Chose stable UUID-backed local chart selection with primary/first-item fallback.
- Files created:
  - `.planning/ui/task_plan.md`
  - `.planning/ui/findings.md`
  - `.planning/ui/progress.md`

### Phase 2: Implement presentation changes
- **Status:** complete
- Implemented the text-only `MenuBarExtra` label, local selected-row state, compact rows, bottom detail chart/mappings/reorder/delete controls, and larger Dynamic Type styles.
- Added original Core Graphics icon generation, `iconutil` packaging, plist metadata, build integration, and menu-title/icon metadata tests.

### Phase 3: Verify and repair
- **Status:** complete
- `bash scripts/build-app.sh` completed successfully under Swift 6 warnings-as-errors and performed plist lint, ad-hoc signing verification, and `otool -L` inspection.
- `bash scripts/run-tests.sh` reported 25 passed, 0 failed, and the two expected no-Aqua skips.
- Explicitly decoded the built `AppIcon.icns` back to all ten standard PNG representations and inspected the 1024×1024 artwork.
- Rebuilt the fallback with correct legacy small-icon representations; enlarged decoded 16×16 and 32×32 checks are clean and recognizable.
- Made the fixed bottom detail region internally scrollable so larger Dynamic Type settings do not make mappings or controls unreachable.
- Final scope audit found no `.sheet`, `.popover`, `.alert`, `.confirmationDialog`, menu picker, `.keyboardShortcut`, `.caption2`, `@preconcurrency`, broad unchecked sendability, `Task.detached`, or `swift build` additions.
- Final `git diff --check`, source/bundle plist lint, bundle icon type check, and signing verification passed.

### Phase 4: Record and hand off
- **Status:** complete
- Completed `.planning/ui/` records, including the 540×700/scrollable-detail tradeoff and no-Aqua limitation.
- Wrote `.codex-implement/_codex_impl_summary_ui1.md`.

## Test results
| Test | Expected | Actual | Status |
|---|---|---|---|
| Strict app build | Exit 0 with zero warnings | Exit 0; plist/signing/linkage checks passed | pass |
| Full test harness | All tests pass | 25 passed, 0 failed, 2 expected no-Aqua skips | pass |
| Bundle icon metadata | ICNS exists and plist references it | 1,312,899-byte `AppIcon.icns`; `CFBundleIconFile=AppIcon.icns` | pass |
| ICNS representations | All ten standard PNGs decode | `iconutil -c iconset` produced all ten | pass |

## Error log
| Date | Error | Attempts | Resolution |
|---|---|---:|---|
| 2026-08-13 | `rg` not found | 1 | Use `find`, `grep`, and `sed`. |
| 2026-08-13 | Icon generator compiler could not write `~/.cache/clang/ModuleCache` | 1 | Added a temporary writable `-module-cache-path` in `make-icon.sh`. |
| 2026-08-13 | `iconutil -c icns` reports `Invalid Iconset` for all ten correctly named/dimensioned PNGs | 2 | Reproduced with an iconset extracted from Apple's Dock icon; added deterministic ICNS fallback plus `iconutil` decode verification. |
| 2026-08-13 | Safety layer rejected a diagnostic `rm -rf` command | 1 | Switched to a unique `mktemp` directory without deleting anything. |
| 2026-08-13 | Planning update patch expected a heading that did not exist | 1 | Read the planning-file tail and inserted the visual-verification section at the correct location. |
| 2026-08-13 | Manual fallback ICNS decoded corrupt base 16×16 and 32×32 images | 1 | Replaced unsupported small PNG chunk types with legacy compressed RGB plus 8-bit alpha-mask representations; retained PNG chunks for Retina and larger sizes. |

## Restart check
| Question | Answer |
|---|---|
| Where am I? | Complete. |
| Where am I going? | Hand off for desktop visual/interaction confirmation. |
| What is the goal? | Complete the requested presentation-only BitPrice UI rework. |
| What have I learned? | See `findings.md`. |
| What have I done? | Implemented, built, tested, audited, and documented the UI rework. |

## Follow-up session: 2026-08-13

### Phase 5: Implement quit and add-coin follow-up
- **Status:** complete
- Read the full planning skill instructions and restored the existing `.planning/ui/` context.
- Confirmed the worktree contains the prior UI pass and will preserve those unrelated in-progress changes.
- Inspected `Views.swift`: quit confirmation is header-local state, search results have variable symbol widths, and confirm-market actions are pushed down by a flexible spacer.
- Added `.confirmQuit` routing, moved the power control before the title, removed `confirmingQuit`, and created a dedicated inline destructive/neutral confirmation view.
- Added a 112-point truncating symbol column, first-baseline text alignment, Dynamic Type styles, vertical padding, and visible separators to search results.
- Enlarged and aligned candidate radio rows, promoted the ticker-match warning, and grouped confirm-market content and actions in an inline scroll view without changing the shared frame.

### Phase 6: Verify and record follow-up
- **Status:** complete
- `git diff --check` passed.
- Initial source-diff audit found no added forbidden presentation or shortcut API.
- `bash scripts/build-app.sh` exited 0 under the direct Swift 6 warnings-as-errors build; bundle plist lint, signing verification, and linkage inspection passed.
- `bash scripts/run-tests.sh` reported 25 passed, 0 failed, and 2 expected no-Aqua skips. No assertions were changed.
- Final artifact audit confirmed `Contents/Resources/AppIcon.icns` exists and is recognized as a macOS icon.
- Final added-line audit found none of `sheet(`, `popover(`, `alert(`, `confirmationDialog(`, `NSAlert`, or `keyboardShortcut`; `NotificationService.swift` is unchanged.
- No GUI launch or visual verification was attempted because the host has no Aqua session.
- Wrote `.codex-implement/_codex_impl_summary_ui2.md`.

## UI follow-up session: 2026-08-13

### Phase 7: Implement chart axes, larger type, and primary-coin guidance
- **Status:** complete
- Read the requested planning skill and restored all existing `.planning/ui/` records.
- Read `Views.swift`, chart model references, current workspace status, and the prior-pass diff.
- Confirmed the current sparkline uses requested rather than actual time bounds and has no axis labels.
- Confirmed the primary star behavior is already isolated in `setPrimary`; this pass will be presentation-only.
- Added `ChartAxisCalculator` in `Views.swift` for truthful price ticks, actual-timestamp time ticks, and zero-range-safe coordinate fractions.
- Rebuilt the chart Canvas with a labelled Y grid, locale-short X labels, actual point bounds, a larger plot, and the existing 90-minute gap break.
- Enlarged the panel to 660×780 and raised Dynamic Type styles across rows, details, add/search/confirmation, quit, and alert-editor content.
- Clarified the unchanged primary action with active yellow/dim inactive star rendering, explicit help text, and a detail-area hint.
- Added normal, flat, single-point, and empty axis assertions; included `Views.swift` in the direct test compilation so the tested helper is the production implementation.

### Phase 8: Verify and record UI follow-up
- **Status:** complete
- `bash scripts/run-tests.sh` reported 26 passed, 0 failed, and the 2 expected no-Aqua skips.
- `bash scripts/build-app.sh` exited 0 under direct Swift 6 warnings-as-errors compilation; plist lint, signing verification, and linkage inspection passed.
- Repeated artifact checks confirmed a valid signed bundle and `Contents/Resources/AppIcon.icns` recognized as a macOS icon.
- `git diff --check` passed. Added-line grep found none of the prohibited presentation or shortcut APIs; concurrency/build prohibitions were absent and `NotificationService.swift` remained unchanged.
- No existing test assertion was weakened or changed; one deliberate acceptance test was added for the production axis helper.
- No GUI launch or visual verification was attempted because this host has no Aqua session.
- One combined patch failed because copied diagnostic output appeared to duplicate a chart-call line; re-reading the exact range showed the source was correct, and the patch was reapplied to the actual text.
- Wrote `.codex-implement/_codex_impl_summary_ui3.md`.

## UI4 session: 2026-08-14

### Phase 9: Inspect requirements and current implementation
- **Status:** in_progress
- Read the planning skill and restored the existing `.planning/ui/` records.
- Confirmed the worktree is clean and the requested implementation is concentrated in the existing inline panel, `AppModel`, v1 persistence DTO/domain conversions, and direct test harness.
- Confirmed the current quit confirmation route, alert call site, axis bounds coupling, and existing test/build architecture from the requested source files.

### Phase 9: Implement settings, global alert gate, and precise chart ticks
- **Status:** complete
- Added an inline `.settings` route with a gear header control, Done return, global alert toggle, immediate destructive Quit BitPrice action, and the existing closed-app explanation.
- Persisted root-level `alertsEnabled` through `PersistedState`, v1 DTO decode/encode, migrations, and store/domain conversion without changing schema version; missing v1 keys default to `true`.
- Gated `AppModel.evaluateAlert` before `AlertEngine.evaluate`, marked globally-off row/editor states, and added next-tick re-enable behavior coverage.
- Added span-derived, uniqueness-preserving tick precision and separated rounded gridline values from real chart bounds used by `priceFraction`.
- Added tests for absent-v1 defaulting/encoding, suspended alert evaluation, ONDO-scale ticks/bounds, and 63,824-scale precision/formatting.
- `bash scripts/run-tests.sh` passed: 28 passed, 0 failed, 2 expected no-Aqua skips. `git diff --check` passed.

### Phase 10: Verify and record UI4
- **Status:** complete
- `bash scripts/build-app.sh` exited 0 with strict Swift 6 warnings-as-errors; bundle plist lint, ad-hoc signing verification, and `otool -L` passed.
- `Contents/Resources/AppIcon.icns` remains present and recognized as a macOS icon.
- The added-line audit found none of `sheet(`, `popover(`, `alert(`, `confirmationDialog(`, `NSAlert`, `Settings {`, or `keyboardShortcut`; no forbidden concurrency/build additions were found.
- `NotificationService.swift` is unchanged. No networking, lifecycle, threshold, hysteresis, cooldown, or concurrency contract was intentionally changed.
- Final `bash scripts/run-tests.sh`: 28 passed, 0 failed, 2 expected no-Aqua skips.
- No app launch or visual verification was attempted because the host has no Aqua GUI session.
- Wrote `.codex-implement/_codex_impl_summary_ui4.md`.

## UI5 session: 2026-08-14

### Phase 11: Inspect requirements and current implementation
- **Status:** in_progress
- Restored the existing `.planning/ui/` records and ran the planning session catch-up script.
- Confirmed UI4 is present: inline Settings, root `alertsEnabled`, v1 manual DTO decode/encode, fixed 660×780 panel, and existing Dynamic Type styles.
- Confirmed the new preference can use `AppModel.commitEdit` from `Views.swift`, keeping the requested source scope and avoiding networking/concurrency changes.

### Phase 11: Implement Settings layout, text-size preference, and icon scaling
- **Status:** complete
- Added `TextSizePreference` to the v1 persisted domain and manually decoded/encoded/canonicalized it in `V1StateDTO`; v0 migration remains default medium.
- Added the root dynamic type modifier and preference-specific 560×700, 660×780, 760×880, and 860×980 panel frames.
- Reworked Settings to a centered full-width header with Back on the left and immediate destructive Quit on the right; changed alerts to a switch and added an inline segmented text-size control.
- Enlarged the header plus/gear, row star, and detail reorder/delete glyphs with Dynamic Type fonts and `.imageScale(.large)`.
- Added persistence tests for absent text-size defaulting, unrecognized-value fallback, and extra-large round trip.

### Phase 12: Verify and record UI5
- **Status:** complete
- `bash scripts/build-app.sh` exited 0 under strict Swift 6 warnings-as-errors; plist lint, ad-hoc signing verification, and `otool -L` passed.
- `Contents/Resources/AppIcon.icns` remains present. `NotificationService.swift` and `AppModel.swift` are unchanged.
- Final `bash scripts/run-tests.sh`: 30 passed, 0 failed, 2 expected no-Aqua skips.
- Added-line grep found none of `sheet(`, `popover(`, `alert(`, `confirmationDialog(`, `NSAlert`, `Settings {`, `keyboardShortcut`, or `.system(size:`; no forbidden concurrency/build additions were found.
- No app launch or visual verification was attempted because the host has no Aqua GUI session.
- Wrote `.codex-implement/_codex_impl_summary_ui5.md`.

## UI6 session: 2026-08-14

### Phase 13: Implement macOS font scaling and header icon alignment
- **Status:** complete
- Reread the requested sources and restored the existing `.planning/ui/` records.
- Replaced UI5's ineffective macOS `.dynamicTypeSize` text assumption with `PanelFont.scaledFont`, using AppKit semantic base sizes and multipliers 0.85, 1.0, 1.2, and 1.45; all panel font call sites route through the central helper.
- Replaced `.imageScale(.large)` glyph sizing with the same scaled font path and changed header symbols to `plus.circle` and `gearshape.circle`.
- Added the multiplier ordering, exact Medium factor, and Medium/base-size regression test.
- Intermediate test run passed: 31 passed, 0 failed, 2 expected no-Aqua skips. Intermediate strict build passed before the final one-line helper formatting change.

### Phase 14: Verify and record UI6
- **Status:** complete
- Final `bash scripts/build-app.sh` exited 0 under strict Swift 6 warnings-as-errors; plist lint, codesign verification, `otool -L`, and the bundled `AppIcon.icns` check passed.
- Final `bash scripts/run-tests.sh` reported 31 passed, 0 failed, and 2 expected no-Aqua skips.
- Final audits passed: `git diff --check`; forbidden presentation/shortcut additions absent; only the central `PanelFont` helper contains `.system(size:)`; `dynamicTypeSize` and `.imageScale` are absent from the panel; `NotificationService.swift` is unchanged.
- Recorded the macOS DynamicTypeSize limitation and the accepted fixed-size multiplier tradeoff in `findings.md`.
- Wrote `.codex-implement/_codex_impl_summary_ui6.md`.
- No app launch or visual verification was attempted because this host has no Aqua GUI session. A desktop check remains necessary for Medium parity, Extra Large usability, and circled-icon balance.

## UI7 session: 2026-08-14

### Phase 15: Inspect add-coin flow and data boundary
- **Status:** in_progress
- Read the planning skill, existing `.planning/ui/` records, and all requested source/test/build files.
- Confirmed `AddCoinView` currently uses a trailing Cancel, a generic ticker warning, ungrouped venue rows, silent Add eligibility, and unscaled default Back/Add controls.
- Confirmed CoinGecko search results are mapped directly into `SearchResult` in `RESTClients.searchCoinGecko`; this is the correct parsing boundary for explicit HTML-entity decoding.
- The first combined planning patch did not match the existing progress-file wording; no repository content was changed by that failed patch, and the plan update was then applied in two targeted patches.
- The first test compile rejected `.accent` as a SwiftUI `ShapeStyle`; changed the new Coin card background to `Color.accentColor`.

### Phase 15: Implement add-coin layout, disclosure, and entity decoding
- **Status:** complete
- Moved Add coin's Cancel control to the leading edge inside a centered-title header while preserving the word “Cancel”.
- Rewrote the orange warning to explain unverified ticker-string identity and plausible-looking wrong prices.
- Grouped the selected Coin identity and Markets into consistent cards, and added explicit Binance live-source and Coinbase fallback descriptions.
- Kept both inline venue radio controls and the existing 60-second Coinbase missed-breach caveat; disclosed the exact Add enabling rule without changing selection semantics.
- Routed Back/Add through `panelFont`, added bordered large controls, and laid them out as a leading action group with spacing.
- Added explicit case-insensitive named and decimal/hex numeric HTML-entity decoding at the CoinGecko search mapping boundary; unknown/unterminated entities remain unchanged.
- Added a REST search fixture covering named entities, `&#39;`, `&apos;`, `&#38;`, `&#x26;`, uppercase `&AMP;`, a bare ampersand, and unchanged plain text.

### Phase 16: Verify and record UI7
- **Status:** complete
- Final `bash scripts/run-tests.sh`: 32 passed, 0 failed, 2 expected no-Aqua skips.
- Final `bash scripts/build-app.sh`: passed under strict Swift 6 warnings-as-errors; plist lint, codesign verification, `otool -L`, and `Contents/Resources/AppIcon.icns` checks passed.
- Final `git diff --check` and added-line audits found no forbidden presentations, menu shortcuts, `NSAttributedString`, or fixed-size fonts outside `PanelFont`; `NotificationService.swift` is unchanged.
- No app launch or visual verification was attempted because this host has no Aqua GUI session. Human desktop confirmation remains necessary for warning wrapping, card density, and Back/Add fit at all text-size steps.
- Wrote `.codex-implement/_codex_impl_summary_ui7.md`.

## UI8 session: 2026-08-14

### Phase 17: Inspect Settings grouping
- **Status:** in_progress
- Read the planning skill, current `.planning/ui/` records, and requested repository context.
- Confirmed `SettingsView` currently places the switch, alert explanation, and segmented text-size picker directly in one flat `VStack`; the header, footer explanation, error line, and shared panel frame are already correct and must remain unchanged.
- The focused layout will use two explicit rounded cards with smaller internal spacing/padding and a larger inter-card gap, while retaining the existing `Spacer(minLength: 14)` below the cards.

### Phase 17: Implement Settings setting cards
- **Status:** complete
- Wrapped Price alerts and Text size in separate neutral rounded-rectangle cards, each with a title, control, explanation, 12-point internal padding, and 6-point internal spacing.
- Used an 18-point gap between the cards so explanations visually belong to their controls.
- Added the factual one-line Text size explanation: it scales text throughout the panel and the panel grows with it.
- Preserved the existing centered header, alert read-only disabling, segmented picker, footer/error lines, shared frame, and `Spacer(minLength: 14)` empty region.
- No test was added because this is a pure layout change; the existing suite still covers the compiled production view.

### Phase 18: Verify and record UI8
- **Status:** complete
- Final `bash scripts/run-tests.sh`: 32 passed, 0 failed, 2 expected no-Aqua skips.
- Final `bash scripts/build-app.sh`: passed under strict Swift 6 warnings-as-errors; plist lint, codesign verification, `otool -L`, and `Contents/Resources/AppIcon.icns` checks passed.
- Final added-line audit found none of `sheet(`, `popover(`, `confirmationDialog(`, `NSAlert`, `Settings {`, `keyboardShortcut`, `Form {`, or `.system(size:`; the only fixed-size font remains inside `PanelFont`. `NotificationService.swift` is unchanged.
- No app launch or visual verification was attempted because this host has no Aqua GUI session. A desktop check remains necessary to confirm the two cards read as separate settings and the text-size explanation stays comfortable at all steps.
- Wrote `.codex-implement/_codex_impl_summary_ui8.md`.

## UI9 session: 2026-08-14

### Phase 19: Inspect duplicated Settings labels
- **Status:** in_progress
- Read the planning skill, current `.planning/ui/` records, requested source context, and the existing `SettingsView`.
- Confirmed each UI8 card currently repeats its setting name: the Price alerts heading plus the Toggle label, and the Text size heading plus the Picker label.
- The correction will keep the cards structurally identical, make both headings primary, hide only the duplicate visible control labels, and add explicit accessibility labels so VoiceOver still names both controls.

### Phase 19: Remove duplicated Settings card labels
- **Status:** complete
- Made both card headings bold primary headlines.
- Changed the visible Toggle and Picker labels to empty labels with `.labelsHidden()` and explicit `.accessibilityLabel(...)` values, preserving VoiceOver names without repeating the card titles.
- Kept both cards structurally identical and preserved UI8 backgrounds, 6/18 spacing, explanations, header, footer/error lines, bindings, read-only disabling, and shared frame.
- No test was added because this is a pure layout/accessibility-label change; the existing suite was run unchanged.

### Phase 20: Verify and record UI9
- **Status:** complete
- Final `bash scripts/run-tests.sh`: 32 passed, 0 failed, 2 expected no-Aqua skips.
- Final `bash scripts/build-app.sh`: passed under strict Swift 6 warnings-as-errors; plist lint, codesign verification, `otool -L`, and `Contents/Resources/AppIcon.icns` checks passed.
- Final inspection confirmed one visible setting name per card; explicit accessibility names remain on both hidden-label controls.
- Final added-line audit found none of `sheet(`, `popover(`, `confirmationDialog(`, `NSAlert`, `Settings {`, `keyboardShortcut`, `Form {`, or `.system(size:`; `NotificationService.swift` is unchanged.
- No app launch or visual verification was attempted because this host has no Aqua GUI session. A desktop check remains necessary to confirm visual hierarchy and VoiceOver presentation in the real panel.
- Wrote `.codex-implement/_codex_impl_summary_ui9.md`.

## UI10 session: 2026-08-14

### Phase 21: Inspect detail supporting text
- **Status:** in_progress
- Read the planning skill, current `.planning/ui/` records, requested source context, and `SelectedCoinDetail`.
- Confirmed the starred-coin hint is redundant and the row star already retains state-specific `.help(...)` text.
- Confirmed mapping IDs are currently three stacked conditional lines. The replacement will be a view-local computed summary, not a standalone pure function, so no new mapping unit test is needed.
- The first summary-file patch used an update operation before the required file existed; no repository content was changed by that failed patch, and the summary was then added explicitly.

### Phase 21: Implement detail supporting-text trim
- **Status:** complete
- Removed only the selected-detail starred-coin hint; preserved the row star's state-specific `.help(...)` text.
- Replaced stacked conditional mapping rows with a single `Text` line containing all three short venue prefixes and `none` markers for absent Binance/Coinbase mappings.
- Kept the summary selectable, tail-truncated it to one line, and attached the complete untruncated string to `.help(...)`.
- Left chart source/quote disclosure, stale-refresh messaging, and reorder/delete controls unchanged.
- No standalone pure formatter or new mapping test was added; formatting remains a view-local computed property.

### Phase 22: Verify and record UI10
- **Status:** complete
- Final `bash scripts/run-tests.sh`: 32 passed, 0 failed, 2 expected no-Aqua skips.
- Final `bash scripts/build-app.sh`: passed under strict Swift 6 warnings-as-errors; plist lint, codesign verification, `otool -L`, and `Contents/Resources/AppIcon.icns` checks passed.
- Final inspection confirmed preserved row-star help, chart/stale disclosures, reorder/delete controls, text selection, mapping prefixes, absence markers, and full-text help.
- Final added-line audit found none of `sheet(`, `popover(`, `confirmationDialog(`, `NSAlert`, `Settings {`, `keyboardShortcut`, `Form {`, or `.system(size:`; `NotificationService.swift` is unchanged.
- No app launch or visual verification was attempted because this host has no Aqua GUI session. A desktop check remains necessary for long-ID truncation and tooltip/readability behavior.
- Wrote `.codex-implement/_codex_impl_summary_ui10.md`.

## UI11 session: 2026-08-14

### Phase 23: Inspect chart/detail layout and fill requirements
- **Status:** complete
- Read the planning skill, current `.planning/ui/` records, requested source context, and the existing `ContentView`, `SelectedCoinDetail`, and `Sparkline` implementation.
- Confirmed the selected-detail ScrollView previously received unbounded height and contained a fixed 350-point region around a fixed 200-point chart; the no-items branch also used the old fixed detail height.
- Chose a bounded `GeometryReader` strategy: the list/detail body gets the available height, the detail region receives a half-height share subject to a list floor, and the chart receives a finite remaining height with a 140-point minimum. The detail ScrollView remains only as an overflow mechanism.
- Confirmed `ChartSeries` has no opening-close field, so no truthful baseline can be sourced without fabricating data.
- The first summary-file patch was malformed because it omitted the `Begin Patch` marker; no repository content was changed by that failed patch, and the summary was then added correctly.

### Phase 23: Implement flexible chart detail and directional fill
- **Status:** complete
- Replaced the fixed 350-point populated and empty detail branches with bounded GeometryReader regions that split available body height between list and detail, keeping empty/no-selection/selected states aligned.
- Passed a finite text-size-aware chart height into `SelectedCoinDetail`; the chart uses the remaining region with a 140-point floor, and the bounded ScrollView handles only genuine overflow.
- Added directional stroke/fill from `model.quotes[item.id]?.change`: green for positive, red for negative, secondary for zero, and accent for unavailable/missing change.
- Filled each contiguous series segment with a vertical color-to-transparent gradient before stroking it, preserving the existing >5,400-second gap breaks. No baseline was added because no opening-close data exists.
- Reasoned that the four Y ticks, actual-bound fractions, 108-point Y-label column, and 50-point X-label reserve remain independent of chart height and therefore scale sensibly above 300 points.

### Phase 24: Verify and record UI11
- **Status:** complete
- Final `bash scripts/run-tests.sh`: 32 passed, 0 failed, 2 expected no-Aqua skips.
- Final `bash scripts/build-app.sh`: passed under strict Swift 6 warnings-as-errors; plist lint, codesign verification, `otool -L`, and `Contents/Resources/AppIcon.icns` checks passed.
- Final inspection confirmed no fixed 200/350 chart/detail frame remains, the detail ScrollView has finite content sizing, directional fallback does not inspect chart endpoints, and gap-safe fill segments are used.
- Final added-line audit found none of `sheet(`, `popover(`, `confirmationDialog(`, `NSAlert`, `Settings {`, `keyboardShortcut`, `Form {`, or `.system(size:`; `NotificationService.swift` is unchanged.
- No app launch or visual verification was attempted because this host has no Aqua GUI session. A desktop check remains necessary for tall-axis spacing, chart fill appearance, and Extra Large overflow behavior.
- Wrote `.codex-implement/_codex_impl_summary_ui11.md`.

## UI12 session: 2026-08-15

### Phase 25: Replace estimated detail sizing with measured layout
- **Status:** in_progress
- Read the planning skill, current planning records, and the requested source context before editing.
- Confirmed the defect remains in `ContentView.listContent`: the selected detail is still a fixed-height `ScrollView`, its child is pinned with `minHeight: detailHeight`, and `chartHeight(for:)` subtracts `125 * PanelFont.multiplier(...)` rather than measuring sibling views.
- The implementation will use a finite detail-region `VStack` directly for the normal case. The chart will receive `.frame(maxHeight: .infinity)` after the natural header/disclosure/mapping content, with a minimum chart floor; a scroll container will be reserved only for the genuinely-too-small overflow case.
- Planning append attempts initially used stale exact context and failed without changing repository content; I reread the tails and applied the phase records with smaller, targeted patches.

### Phase 25: Implement measured detail layout
- **Status:** complete
- Replaced the selected-detail `ScrollView`/`minHeight` pairing with `ViewThatFits(in: .vertical)`: the first candidate is a plain finite detail stack, and the second is an intrinsic-height detail inside `ScrollView` for genuine overflow only.
- Removed `chartHeight(for:)` and its `125 * PanelFont.multiplier(...)` estimate. `SelectedCoinDetail` now gives the chart a 140-point minimum and `.frame(maxHeight: .infinity)` only in the fitting branch, so the chart receives the actual leftover proposal after its siblings.
- Applied the same chart-floor behavior to the unavailable-chart placeholder; the empty and no-selection branches still use the same computed `detailHeight`.
- Preserved the existing chart color, per-segment gradient fill, true plot bounds, axes, disclosures, and controls.

### Phase 26: Verify and record UI12
- **Status:** complete
- `bash scripts/run-tests.sh`: 32 passed, 0 failed, 2 expected no-Aqua skips.
- `bash scripts/build-app.sh`: passed under strict Swift 6 warnings-as-errors; plist lint, codesign verification, `otool -L`, and `Contents/Resources/AppIcon.icns` checks passed.
- Added-line audits found no forbidden presentation APIs, shortcuts, `Form`, or fixed font sizes; no `chartHeight` or `125 * multiplier` estimate remains, and non-target behavior files are unchanged.
- Reasoning: at Medium, the finite first candidate lays out the header/disclosure/mapping rows naturally and the greedy chart consumes all remaining detail height, leaving no unallocated band. At Extra Large, if those measured rows plus the 140-point floor do not fit, `ViewThatFits` selects the intrinsic content fallback so text remains reachable by scrolling. When the content fits, the first candidate is selected and no scroll indicator exists.
- No layout test was added because this is a pure SwiftUI presentation restructure; the existing test suite and strict build provide compile/regression coverage.

## UI13 session: 2026-08-15

### Phase 27: Add chart-open baseline and trim detail heading
- **Status:** in_progress
- Read the planning skill, current planning records, and the requested source/test context.
- Confirmed `SelectedCoinDetail` still renders `"\\(item.symbol) details"`, while `Sparkline` already has true price bounds, shared axis precision, and the correct fill/stroke ordering needed for a baseline.
- Chose `ChartAxisCalculator.openingClose(for:)` as a pure helper: it returns the first candle close only when at least two points exist. The baseline label will include `24h chart open` and the existing rounded axis-formatted value, avoiding any claim about a different venue's row change basis.

### Phase 27: Implement chart-open baseline and trim detail heading
- **Status:** complete
- Changed the selected-detail heading from `"\(item.symbol) details"` to the symbol alone, retaining the quote asset and all controls unchanged.
- Added `ChartAxisCalculator.openingClose(for:)`, returning the first candle close only for series with at least two points. Added normal, flat, single-point, and empty assertions to the existing axis test.
- Added a dashed muted baseline using true plot bounds, plus a `24h chart open · <rounded value>` label. The line is painted before the existing fill/stroke; the label is painted afterward for readability at min/max edges.

### Phase 28: Verify and record UI13
- **Status:** complete
- Final `bash scripts/run-tests.sh`: 32 passed, 0 failed, 2 expected no-Aqua skips.
- Final `bash scripts/build-app.sh`: passed under strict Swift 6 warnings-as-errors; plist lint, codesign verification, `otool -L`, and `Contents/Resources/AppIcon.icns` checks passed.
- Final added-line audit found none of `sheet(`, `popover(`, `confirmationDialog(`, `NSAlert`, `Settings {`, `keyboardShortcut`, `Form {`, or `.system(size:`). Non-target behavior files remain unchanged.
- Plot bounds, gap-safe segment fill, measured `ViewThatFits` sizing, and panel sizing were not changed. No baseline is drawn for single-point or empty series.
- No Aqua GUI session is available; a human desktop check remains necessary for label placement/readability at plot edges and the visual balance of the baseline against the colored chart.

## Icon1 session: 2026-08-15

### Phase 29: Redraw the programmatic app icon
- **Status:** in_progress
- Read the planning skill, current planning records, the icon generator, icon packaging script, build/test scripts, and the requested source context.
- Confirmed the existing generator uses a rounded rectangle, dark navy gradient, gold coin gradient, rim, shadow, and a glyph stroke of about 1.06 pixels at 16×16.
- Chose a sampled superellipse with exponent 5 as an explicit approximation of the system squircle, a flat Bitcoin-orange tile, and a white glyph with a minimum 1.6-pixel stroke at 16×16. No secondary price/trend motif will be included because it would reduce small-size legibility without adding necessary identity.

### Phase 29: Implement the programmatic icon redraw
- **Status:** complete
- Added `approximateSquirclePath(in:)`, a 128-sample n=5 superellipse approximation documented as not Apple's official curve.
- Replaced the navy gradient, coin gradient/rim/shadow, and old glyph construction with a flat `#F7931A`-family tile and a flat white Bitcoin glyph. The small-size branch uses a 1.6-pixel minimum stroke and a slightly wider glyph; no secondary motif was included.

### Phase 30: Verify and record icon redraw
- **Status:** complete
- `scripts/make-icon.sh` generated an ICNS that decoded to all 10 standard PNG renditions. Programmatic RGBA inspection found 42 unique colors at 16×16 and 61 at 32×32, with nonzero samples and white glyph-center samples.
- `bash scripts/run-tests.sh`: 32 passed, 0 failed, 2 expected no-Aqua skips; test count unchanged.
- `bash scripts/build-app.sh`: passed with strict Swift 6 warnings-as-errors; plist lint, codesign verification, linkage, and `Contents/Resources/AppIcon.icns` checks passed.
- An initial verification command was rejected because its cleanup trap contained `rm -rf`; it did not change repository content. The same verification was rerun without cleanup and passed, leaving only a temporary directory under `/tmp`.
- `Sources/` and `scripts/make-icon.sh` are unchanged. No GUI was available to judge whether the squircle, orange hue, and glyph balance match current macOS icon aesthetics.
