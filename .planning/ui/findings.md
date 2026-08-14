# Findings and decisions

## Requirements
- Presentation-only change: icon, menu-bar text, larger Dynamic Type styles, compact selectable rows, and a fixed bottom detail chart.
- Preserve inline routing, no keyboard shortcuts, no separate windows/popups, no networking/persistence/alert/concurrency changes.
- Stale and unavailable data must remain truthful; chart venue, quote asset, and mapping IDs must remain visible.
- Build remains direct Swift 6 `swiftc`, warnings-as-errors, arm64 macOS 14; no SwiftPM.

## Research findings
- `ContentView` owns the existing inline `PanelRoute` and currently uses a 380×520 fixed panel. Rows contain their own 42-point chart, mappings, and reorder controls.
- `AppModel` publishes `quotes` and `charts` dictionaries keyed by stable `WatchItem.ID`; `removeItem` repairs a deleted primary by choosing the first remaining item.
- `AppModel.menuBarTitle` already returns `SYMBOL formatted-price` only when the persisted primary and its quote are both present, otherwise `BitPrice`.
- `rowPresentation(for:)`, `quoteAsset(for:)`, `formatPrice`, and `formatChange` already preserve stale/offline state, source-specific quote assets, monospaced-friendly strings, and unavailable change as `—`.
- `ChartSeries` carries its own source, quote asset, and `latestRefreshFailed`, so the bottom detail can truthfully disclose a fallback chart independently of the current row quote.
- The build script already assembles/signs/verifies a direct-swiftc app bundle and creates `Contents/Resources`; it only needs icon generation/copy integration.
- The test harness has presentation-formatting and packaging tests but no `menuBarTitle` assertion.
- Apple documentation confirms the ten expected `.iconset` names and sizes. On this macOS 15.6.1 host, however, `iconutil -c icns` rejects both the generated complete set and a complete set extracted by `iconutil` from `/System/Library/CoreServices/Dock.app/.../Dock.icns`. The decoder direction works. The reproducible script therefore attempts the mandated pack command, falls back to writing standard PNG ICNS chunks, then uses `iconutil -c iconset` to validate all ten representations.

## Technical decisions
| Decision | Rationale |
|---|---|
| Store selected watched-item ID in `PanelView` state | Keeps chart selection separate from primary selection and avoids model/persistence changes. |
| Initialize/fallback selection to the current primary, then first item | Defines launch/empty/deletion behavior without persisting chart selection. |
| Increase the panel to 540×700 with a scrollable fixed-height 285-point detail region | Larger Dynamic Type styles and a taller chart need more room; detail scrolling prevents clipping at large accessibility sizes while retaining a usable watchlist. |
| Use `List(selection:)` rather than a whole-row `Button` | Nested star/Alert buttons remain independent and inline. |

## Issues
| Issue | Resolution |
|---|---|
| `rg` command is not installed | Use `find`/`grep`/`sed`. |
| `iconutil` packer reports `Invalid Iconset` for its own complete system-icon extraction | Use a deterministic standard ICNS-container fallback after the required attempt, and independently decode/verify it with `iconutil`. |
| Initial fallback used PNG `icp4`/`icp5` chunks that decoded corrupt at base 16×16 and 32×32 on this host | Encode those base sizes as legacy `is32`/`s8mk` and `il32`/`l8mk` chunks; keep modern PNG chunks for Retina/larger representations. |

## Specification divergence
- `SPEC.md` §2.1 describes an approximately 380-point panel and an always-visible sparkline in every row. The requested UI instead uses a 540-point panel and one selected-row chart in a fixed bottom detail area. `SPEC.md` is intentionally unchanged.

## Visual verification
- Inspected the generated 1024×1024 PNG extracted from the built ICNS: it has a dark navy rounded-square background, high-contrast orange coin, cream ring, and a bold double-stem Bitcoin-like mark. The large representation is crisp and distinctive.
- Enlarged diagnostics of the corrected decoded 16×16 and 32×32 representations show the orange coin and double-stem mark remain recognizable at those raster sizes.
- No app UI was launched or observed; there is no Aqua GUI session.
- Internet research was limited to the official Apple iconset naming/size reference and troubleshooting the host `iconutil` behavior. No external assets were downloaded or embedded.

## Verification limitations
- The host has no Aqua GUI session, so the final visual appearance and interaction must be confirmed by a human on a desktop.
- Specifically unverified: Finder/app-switcher icon display and caching, menu-bar title truncation in a real status bar, row selection/button interaction, panel fit, and large-Dynamic-Type scrolling.

## Follow-up: quit and add-coin layout
- The quit affordance still uses `confirmingQuit` to graft Quit/Cancel controls into the list header; the follow-up requires a dedicated inline `PanelRoute` destination instead.
- Search-result names currently begin immediately after variable-width symbols, producing a ragged text column; the row also lacks an explicit separator and uses smaller typography than the enlarged main panel.
- Confirm-markets currently uses a flexible `Spacer()` before its actions, leaving Back/Add visually stranded at the bottom of the fixed 540×700 panel.
- The existing fixed panel frame and inline editors remain the correct architecture and must not change for this follow-up.
- A 112-point symbol column fits the cited long tickers at the normal `.title3` size while deliberately truncating at larger Dynamic Type sizes or for longer symbols, protecting the aligned name/id column.
- Confirm-markets now uses one inline `ScrollView` with actions immediately after the polling note. This removes the large empty vertical gap while keeping every candidate and both actions reachable when result counts or Dynamic Type increase.
- The host cannot visually confirm the far-left header placement, prompt hierarchy and button appearance, search-row baseline alignment/separators, candidate density, truncation behavior, or scrolling at large Dynamic Type sizes. Those presentation details need a human check in an Aqua desktop session.

## Follow-up: chart axes, type, and primary control
- The current sparkline scales X against `requestedStart`/`requestedEnd`, even when returned points cover less time. Axis labels therefore must instead use the earliest and latest actual point timestamps, with the midpoint derived from those real bounds.
- The existing line already breaks when adjacent timestamps are more than 5,400 seconds apart; the axis implementation must preserve that path behavior and only draw neutral reference gridlines, not interpolate missing data.
- Axis calculations can stay presentation-only and independently testable by exposing an internal helper in `Views.swift`; no chart/network model changes are needed.
- Current 540×700 row columns total about 448 points before list insets, but another Dynamic Type step makes the six-character symbol/quote/status cluster and the cited price/change/Alert content tight. The panel needs both more width and more height, while the detail chart needs a larger reserved region for axes.
- The star already calls `setPrimary` and must retain that action; only its help text, active/inactive rendering, and nearby explanatory copy need to change.
- The axis uses four linearly derived price ticks including the exact actual minimum and maximum; flat and single-point series deliberately collapse to one centered price tick instead of creating a false range.
- Time ticks are the earliest point, the real point nearest the elapsed midpoint, and the latest point. This keeps every label attached to an observed timestamp and avoids assuming evenly spaced candles.
- A 108-point Y-label margin accommodates `AppModel.formatPrice` output such as `63,824.73` while leaving roughly 510 points of plot width in the 660-point panel. The detail reserve is 350 points with a 200-point plot and remains scrollable.
- The normal-size row budget is approximately 240 points for star/symbol/quote/status, 170 for a price such as `63,824.73`, 105 for `+12.34%` plus `Alert`, and 24 for inter-column spacing. That totals 539 points before list insets, leaving useful slack inside the 628-point padded content width.
- The larger 660×780 panel is a layout tradeoff: it keeps the normal-size six-character-symbol row and the 200-point axis plot readable, while the watch list and detail remain independently scrollable for more rows or larger system text.
- No Aqua session is available. Axis-label clipping/overlap in every locale, the perceived active/dim star contrast, longest-row fit, panel fit on smaller displays, and large-Dynamic-Type interaction still require human desktop confirmation.

## UI4: settings, global alerts, and tick precision
- `PanelRoute` currently has inline list/add/alert/confirm-quit routes; the existing quit confirmation must be removed and Settings must be another inline route so the `.window` panel never presents a separate surface.
- The persisted model is v1 and `PersistedState.bitcoinSeed()`, `V1StateDTO`, and the manual DTO conversion functions are the complete persistence path. `alertsEnabled` must be optional on decode with a `true` default and always encoded without changing `currentSchemaVersion`.
- Alert evaluation is called from both Binance and Coinbase quote paths through `evaluateAlert`; the global switch belongs at the first guard in that method, before `AlertEngine.evaluate`, and must not mutate alert latch state while disabled.
- The chart currently uses `priceTicks` both as labels and as the price bounds passed to `priceFraction`. UI4 must return/retain real min/max separately and use a span-derived rounded precision for labels/gridlines so the 0.33 and 63,824 scales remain readable without clipping points.
- Existing tests compile production `Views.swift` and exercise `ChartAxisCalculator`; the new pure helpers and model persistence/alert behavior can be tested without an Aqua session.

### UI4 implementation tradeoffs and verification
- Axis precision is derived from the linear tick interval, targeting readable significant digits and increasing precision until the rounded ticks remain distinct. A fixed formatter precision makes every label in the axis agree, including tight large-price ranges.
- `ChartPriceBounds` is deliberately separate from `priceTicks`: rounded values position reference gridlines, while real bounds are passed to both `priceFraction` calls for the series and the gridline fraction.
- The global toggle uses the existing synchronous full-state edit path, so it gets the same durable-write and read-only protection as other settings without changing any feed or task lifecycle code. Turning it on only changes the next quote evaluation; it does not re-arm or add a grace period.
- Verification passed: `bash scripts/build-app.sh`; `bash scripts/run-tests.sh` (28 passed, 0 failed, 2 expected skips); `plutil -lint`; `codesign --verify`; `otool -L`; icon resource presence; `git diff --check`; and added-line forbidden-API/concurrency/build audits.
- No Aqua GUI session exists on this host. A human desktop check is still needed for actual panel appearance, Settings/Done/Quit interaction, off-state contrast, row/editor text fit, axis label placement/localization, and menu-bar/panel behavior.

## UI5: Settings layout, text-size preference, and larger icons
- UI4 currently renders Settings inline through `PanelRoute.settings`; its header is a leading title plus trailing Done, the quit action is in the body, and the alert toggle has no explicit style. UI5 can preserve the route and immediately-applying binding while changing only presentation/layout.
- `ContentView` owns the fixed `.frame(width: 660, height: 780)`. The text-size preference must be applied to this root view and choose the frame dimensions from a stable enum/string preference without changing any model/network lifecycle code.
- `PersistedState` and `V1StateDTO` already carry the v1 root `alertsEnabled` flag. The new preference belongs alongside it, with manual DTO decode fallback for absent and unrecognized strings; `currentSchemaVersion` and `validatePersistedState` stay unchanged.
- `AppModel.commitEdit` is already public and synchronous on the main actor, so Settings can persist the text-size enum through an inline binding without modifying `AppModel.swift` or adding another runtime/concurrency surface.
- Requested glyphs are the row star, list header plus/gear, and detail up/down/trash images. Their current fonts are `.title3` or implicit, so `.imageScale(.large)` and Dynamic Type-relative font styles are appropriate; no fixed point size or `.system(size:)` is needed.

### UI5 implementation tradeoffs and verification
- `TextSizePreference` uses the stable raw strings `small`, `medium`, `large`, and `extraLarge`. The DTO canonicalizes both absent and unrecognized values to `medium`, and always writes the canonical root field without changing schema v1.
- The four requested panel sizes are used exactly: 560×700, 660×780, 760×880, and 860×980. The `dynamicTypeSize` mapping uses SwiftUI `.small`, `.medium`, `.large`, and `.xLarge`; the existing semantic font styles remain intact.
- The Settings header uses a full-width ZStack so the title is geometrically centered despite the Back and destructive Quit controls having different widths. The segmented text-size picker stays inline and does not risk dismissing the `.window` panel.
- The preference is persisted through the existing synchronous `commitEdit` path from `Views.swift`; no `AppModel.swift` change was needed, and no feed/network lifecycle behavior was added.
- Verification passed: strict app build; plist lint; codesign verification; `otool -L`; icon presence; 30 tests with 0 failures and 2 expected no-Aqua skips; `git diff --check`; and added-line audits for forbidden presentations, menu shortcuts, fixed system font sizes, concurrency workarounds, and SwiftPM.
- No Aqua GUI session exists on this host. A human desktop check is still needed for actual header centering, switch/segmented-control appearance, panel resizing at all four steps, longest-row fit, and larger glyph balance.

## UI6: macOS DynamicTypeSize finding and accepted font-scaling tradeoff
- Desktop testing confirmed that the UI5 `.dynamicTypeSize(...)` modifier changed the preference-sized frame but did not scale macOS semantic `.title*`, `.headline`, or `.body` fonts. This is a platform limitation: SwiftUI's DynamicTypeSize mechanism does not provide the requested macOS app-level semantic-font scaling.
- The accepted tradeoff is to make the in-app preference authoritative for panel text. `PanelFont.scaledFont` is the single fixed-size construction point; it derives the base point size from AppKit's `NSFont.preferredFont(forTextStyle:)`, applies the UI5 multiplier, and returns the resulting SwiftUI Font. Medium therefore retains the platform's current base size, while Small/Medium/Large/Extra Large use 0.85/1.0/1.2/1.45.
- Every panel font call site now uses the `panelFont` modifier backed by that helper; the two Canvas labels call the helper directly. No fixed-size system font occurs outside the central helper. The old ignored `.dynamicTypeSize(...)` modifier was removed.
- Header `plus` and `gearshape` changed to `plus.circle` and `gearshape.circle`; the row/detail glyphs now use the same scaled helper instead of `.imageScale(.large)`, keeping icon size proportional to the selected text step.
- Final verification passed after the helper edit: strict app build and bundle checks, 31 tests with 0 failures and 2 expected skips, `git diff --check`, and forbidden-API/font audits.
- No Aqua GUI session is available here. A human desktop check must confirm Medium is genuinely unchanged relative to UI5 and that Extra Large remains usable rather than absurd, plus the circled-icon visual balance.
