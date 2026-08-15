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

## UI7: add-coin hierarchy, venue roles, and CoinGecko entity boundary
- `AddCoinView` currently shares one leading-aligned `HStack` for its title and trailing Cancel. The confirmation route can use the Settings-style full-width `ZStack`: centered title, leading Cancel, and an intentionally empty trailing slot.
- The confirmation warning is the right place to state that ticker matching is a string guess rather than verified identity, and that an incorrect confirmation can still produce a plausible-looking wrong price. It remains an orange prominent block.
- The selected CoinGecko project should be a distinct identity card/section above a `Markets` section. Binance and Coinbase can each use the same card treatment while retaining inline radio rows; this preserves the `.window` panel lifecycle constraint.
- Binance is the live WebSocket source. Coinbase is the fallback polled every 60 seconds when Binance is unavailable or has no market; both roles need explicit one-line descriptions, while the existing missed-breach caveat remains.
- Add's existing predicate is correct: both venue answers must be non-nil and they must not both be `__none__`. A visible rule line can disclose that predicate without changing selection or auto-selecting either venue.
- CoinGecko search JSON is decoded into a private envelope and mapped to `SearchResult` in `RESTClients.searchCoinGecko`; HTML entity decoding belongs in this map before uppercasing/storing the symbol and before the result reaches SwiftUI or `WatchItem` creation.
- The explicit decoder will recognize case-insensitive `amp`, `lt`, `gt`, `quot`, `apos`, numeric decimal entities, and numeric hexadecimal entities. Unknown or unterminated `&...` sequences remain byte-for-byte unchanged, so the decoder cannot fabricate text.

### UI7 implementation tradeoffs and verification
- The Coin identity and both venue blocks use the same neutral rounded-card treatment; section labels (“Coin” and “Markets”) establish subject-versus-market hierarchy without introducing a separate presentation surface.
- Binance and Coinbase remain independently answered inline. The Add rule is disclosed in text and implemented through the existing predicate: both answers are required and at least one must be a real market.
- The warning is intentionally concise but still names both failure properties: ticker matching is an unverified string guess, and a wrong confirmation can look plausible while showing the wrong price.
- Entity decoding is deliberately explicit and conservative: recognized entities become their scalar characters, while unknown, malformed, or bare-ampersand text is preserved rather than guessed.
- Verification passed: 32 tests with 0 failures and 2 expected skips; strict app build; plist/signing/linkage/icon checks; `git diff --check`; and forbidden presentation, shortcut, HTML-importer, and fixed-font audits.
- No Aqua GUI session exists. A human desktop check is still needed for the warning staying within two lines, card density and scrolling, role-description readability, and Back/Add hit-area/fit at Small and Extra Large.

## UI8: Settings card grouping
- `SettingsView` is the only required source change. Its existing centered Back/Settings/Quit header, read-only alert binding, segmented text-size picker, footer explanation, error line, and shared preference-sized frame are all retained.
- Each setting card will have a title, its control, and its explanation. Internal spacing is intentionally compact; the cards are separated by a visibly larger gap so the alert explanation cannot be read as belonging to Text size.
- The Text size explanation will state only the observable scope: it changes text throughout the panel, and the panel grows with the selected size. No persistence or model behavior changes are needed.

### UI8 implementation tradeoffs and verification
- The cards use the existing panel font system and a low-opacity secondary tint with rounded corners; no fixed point sizes or `Form` metrics were introduced.
- Internal card spacing is 6 points with 12 points of padding, while the card-to-card gap is 18 points. The larger external gap is intentional and is the key readability tradeoff.
- The existing 14-point minimum spacer and shared preference-sized frame remain in place, so Settings does not resize the panel differently from other routes.
- Verification passed: 32 tests with 0 failures and 2 expected skips; strict app build; plist/signing/linkage/icon checks; `git diff --check`; and forbidden API/font audits.
- No Aqua GUI session exists. A human desktop check must confirm the cards read as separate settings, the explanatory lines remain attached to the correct controls, and the layout remains comfortable at Small and Extra Large.

## UI9: duplicated Settings labels and accessibility
- UI8's card titles are the intended visible setting names. The control labels must therefore be visually hidden rather than removed semantically.
- Both cards remain a `VStack` with the same title/control/explanation structure. `.labelsHidden()` removes the duplicate visible label, while an explicit `.accessibilityLabel` preserves a meaningful VoiceOver name for the empty-label Toggle and Picker.
- Card heading styling changes from dim secondary text to the central helper's bold headline; card backgrounds, 6-point internal spacing, 18-point inter-card spacing, explanations, header, footer, and shared frame remain unchanged.

### UI9 implementation tradeoffs and verification
- The visible labels are empty and hidden, but accessibility labels deliberately retain the control-specific names. This avoids duplicate visual copy without making VoiceOver controls nameless.
- Both cards remain the same title/control/explanation `VStack`; no title-trailing switch exception was introduced.
- Verification passed: 32 tests with 0 failures and 2 expected skips; strict app build; plist/signing/linkage/icon checks; `git diff --check`; forbidden API/font audits; and direct inspection of the two card blocks.
- No Aqua GUI session exists. A human desktop check must confirm the cards read cleanly with one visible name each and that the hidden labels are presented appropriately by VoiceOver.

## UI10: detail supporting-text trim
- The selected-detail star hint is redundant because the row star retains its state-specific `.help(...)` descriptions. Removing only the detail `Label` avoids repeating a general rule inside every selected coin block.
- Mapping summaries retain `CG:`, `BN:`, and `CB:` prefixes and render missing venue mappings as `BN: none` or `CB: none`, so a shortened line cannot imply that one venue's ID belongs to another.
- The summary is a view-local computed property rather than an extracted pure function. The rendered `Text` is single-line, tail-truncated, selectable, and carries the complete summary in `.help(...)` for long CoinGecko IDs.
- Chart source/quote disclosure, stale-chart messaging, and reorder/delete controls are unchanged.

### UI10 implementation tradeoffs and verification
- `BN: none` and `CB: none` are explicit absence markers, not fabricated market IDs. The `CG:`, `BN:`, and `CB:` prefixes remain inline so every present ID is recoverable by venue.
- The line truncates as a whole to protect the fixed panel width; `.help(mappingSummary)` retains the complete string for long identifiers.
- Verification passed: 32 tests with 0 failures and 2 expected skips; strict app build; plist/signing/linkage/icon checks; `git diff --check`; forbidden API/font audits; and direct preservation checks for row help, chart disclosures, stale messaging, and detail controls.
- No Aqua GUI session exists. A human desktop check must confirm the one-line mapping summary and long-ID tooltip are comfortable in the actual panel.

## UI11: flexible detail chart and directional fill
- UI13 adds the chart's opening-close reference from the first `ChartSeries` point only when at least two points exist; sparse series therefore do not receive a fabricated baseline.
- The baseline uses the existing true-bound `priceFraction`, the shared `pricePrecision`, and `formattedPrice`. Its inline label says `24h chart open`, so it describes this chart series rather than asserting the row quote's change venue.
- Draw order remains axes/grid, muted dashed baseline and label, then the existing per-segment fill and full-strength stroke. Layout sizing and gap handling are unchanged.
- UI12 correction: the prior `125 * multiplier` reserve was only an estimate of sibling-view height. It could exceed the real stack and leave dead space, or undershoot it and make the `minHeight` detail child inside a `ScrollView` advertise overflow and show a scrollbar.
- The normal selected-detail path must be a plain finite-height `VStack`; the header, disclosure, optional stale line, and mapping line size naturally, while a greedy chart fills the remaining proposal. The chart floor is a safety constraint, not a substitute for measurement.
- Scrolling must not surround content that fits. If the detail region cannot satisfy the natural text stack plus chart floor at Extra Large, only that true overflow path may scroll; the no-selection and no-items empty branches retain the same computed detail-region height.
- A ScrollView proposes unbounded height along its scroll axis. A greedy chart inside it cannot fill the visible detail region reliably, so the fix uses an outer bounded `GeometryReader` and passes an explicit finite chart height into `SelectedCoinDetail`.
- The list/detail body shares its available height: the detail receives half the body, with a 300-point target floor constrained by a 180-point minimum list region. This removes the fixed 350-point branch while keeping the empty-detail and selected/no-selection branches aligned.
- Chart height is the bounded detail height minus a text-size-scaled non-chart reserve, with a 140-point floor. At Extra Large the chart can shrink to that floor and the finite detail ScrollView can scroll if header/disclosure/mapping content genuinely exceeds the region; the outer panel frame still comes only from the text-size preference.
- Sparkline color comes from the selected item's current quote change, matching row convention: positive green, negative red, zero secondary, and unavailable/missing accent. No direction is inferred from chart endpoints.
- The area fill is drawn per contiguous <=90-minute segment before the full-strength stroke, so gradients do not span data gaps. Four existing axis ticks and the 50-point axis-label reserve remain valid at taller chart heights.
- No baseline was added: `ChartSeries` exposes no opening close, and a midpoint or first/last inference would fabricate a reference.

## Icon1: flat macOS-style app icon
- The current icon's rounded rectangle, navy gradient, coin gradient/rim, and shadow create the skeuomorphic appearance this pass removes. The existing glyph line width is `0.066 * size`, only about 1.06 pixels at 16×16.
- The replacement will sample `|x|^5 + |y|^5 = 1` around the tile to create a continuous-curvature squircle approximation. It must be documented as an approximation, not Apple's unpublished official curve.
- Small sizes will use the same simplified glyph geometry with a proportional stroke floor of 1.6 pixels at 16×16. No price or sparkline motif will be drawn at any size: the flat orange/white mark has stronger small-size contrast and fewer failure modes.

### Icon1 implementation and verification
- The final source uses 128 samples around an exponent-5 superellipse, fills the inset path with flat Bitcoin orange, and draws only the white glyph. The system squircle remains an approximation because Apple does not publish its curve.
- The optional secondary motif was deliberately omitted. At 16×16 and 32×32, the identity is already carried by the orange tile and white glyph; adding a trend mark would crowd the Finder-sized representations.
- The generated ICNS decoded to all ten standard renditions. Pixel inspection confirmed the 16×16 and 32×32 images are varied and nonblank. Human desktop review is still required for system-icon visual balance and color judgment.

## UI14: baseline tick and Settings app identity
- The chart baseline is the first candle's close only when the series has at least two points. It is represented as a real axis tick at its true plot fraction, with shared rounded precision, bold weight, a chart-related color, and a terse `24h open` marker. Positive/negative/unavailable cases share the chart's green/red/accent color; a neutral zero-change chart uses the accent for the baseline so it remains distinct from the secondary chart stroke.
- Ordinary ticks are suppressed only when their plotted distance from the baseline is less than the body-font point size used as an approximate one-line separation. The baseline wins even at the true minimum or maximum, so a coincident bound tick is replaced rather than nudged; the opposite bound follows the same rule when it collides.
- The dashed baseline is painted after ordinary gridlines but before the per-segment fill and stroke. No floating in-plot label remains, and true min/max bounds and gap-safe fill are unchanged.
- Settings reads `NSApplication.shared.applicationIconImage` and bundle metadata at runtime. The icon block is centered, scales its modest image dimension with the text preference, and has low layout priority so the cards and closing disclosure remain primary if vertical space is scarce.

## UI15: compact baseline marker and bottom-pinned Settings identity
- The baseline axis label now uses a filled diamond followed by the same rounded value as ordinary ticks. Bold weight and the distinct baseline color remain; the Y-axis reserve returns to the ordinary-label scale rather than being widened for explanatory words.
- The diamond alone tells an axis-only reader that this is a specially marked reference value, but not that it is the 24-hour opening close. A `.help(...)` on the chart supplies that meaning without affecting layout width, and no floating in-plot label was reintroduced.
- The Settings identity block now has intrinsic height and remains directly above the closing disclosure. The existing spacer owns the flexible space above it, while `.layoutPriority(-1)` remains so decoration yields to real content at Extra Large.

## UI16: measured Y-axis reserve
- Tick selection is performed from `plotHeight` before any width-dependent geometry. Each selected axis label is resolved with the exact panel-size font and measured unconstrained; the widest measured result plus the existing 9-point label gap determines the left inset.
- The measured inset is capped at 40% of the available Canvas width, leaving at least the remaining 60% (minus the existing right reserve) for the plot. If the cap binds at a narrow panel or pathological precision, the same measured label text is shortened with an ellipsis inside the capped label width; font size and shared numeric precision are not changed.
- The measurement cannot be isolated into a platform-independent pure test without replacing the authoritative `ResolvedText.measure(in:)` operation, so no hollow width test was added. Existing axis value tests remain unchanged.

## UI17: login item, alert defaults, and notification status
- Launch-at-login state is read from `SMAppService.mainApp.status` every time Settings appears and after every register/unregister attempt. `.requiresApproval` and unknown statuses stay visibly distinct from a registered item, with inline System Settings guidance rather than a retry or an alert. Unsigned or ad-hoc-signed development builds may report different login-item behavior than distributed builds; re-reading the system status keeps the control honest in either case.
- Global cooldown and hysteresis defaults are persisted as additive root-level v1 fields. Hysteresis remains a decimal string on the wire, both defaults are validated with the per-alert bounds, and changing them seeds only new alerts; existing alerts are not rewritten. Missing v1 keys and v0 migrations use zero defaults.
- Notification permission is read-only Settings presentation state. A nonisolated async helper creates and consumes the notification center/settings on the executor it is already using, then only a small sendable status enum crosses back to the main-actor view. No authorization request or notification submission was added, and `NotificationService.swift` remains untouched.

### UI17 implementation and verification
- Added the three Settings cards/lines through the existing inline panel route and central font helper. The login and notification values are not mirrored into persistence.
- Added persistence coverage for missing fields, v0 migration defaults, custom round trips, decimal-string encoding, and invalid bounds. The strict suite reports 33 passed, 0 failed, and 2 expected no-Aqua skips.
- The strict app build passed and linked ServiceManagement and UserNotifications automatically; plist, signing, linkage, and bundled-icon checks passed.
- No Aqua GUI session was available. A human desktop check remains necessary for actual login-item status changes, notification wording at each system permission state, and the added card density at Small and Extra Large sizes.

## UI18: bounded alert-default steppers
- The Alert defaults card now uses inline action-based `Stepper` controls. The handlers enforce cooldown `0...604_800` in 30-second increments and hysteresis `0...99` in one-percent increments, while keeping the stored file bounds as an independent validation guard.
- A stored off-step or fractional value is not normalized during Settings appearance. `AlertDefaultStepper.nextValue` rounds toward the next multiple only in the direction of an actual press: 12.5 becomes 13/12, and 45 seconds becomes 60/30. The card persists immediately through `model.commitEdit`; a failed write restores the displayed values from the model and surfaces `localError`.
- Shipped and missing-key defaults are now consistently 30 seconds and 10 percent across `PersistedState`, V1 decoding/memberwise defaults, fresh seed, and V0 migration. Existing per-alert values are untouched.

### UI18 implementation and verification
- Removed the free-text fields, Save defaults button, parsing, and UI-side manual range checks; the existing `validatePersistedState` bounds remain unchanged.
- Added pure arithmetic tests for fractional and exact hysteresis values plus an off-step cooldown.
- `bash scripts/run-tests.sh`: 34 passed, 0 failed, 2 expected no-Aqua skips. `bash scripts/build-app.sh`: passed with strict Swift 6 warnings-as-errors, plist lint, signing verification, linkage, and bundled icon checks.
- No Aqua GUI session was available. A human desktop check remains necessary for the visual affordance of the Stepper buttons and for confirming fractional/off-step values remain readable before interaction.

## UI19: aligned Alert defaults grid
- Replaced the two `LabeledContent` rows with a three-column `Grid`: leading labels, trailing bold monospaced-digit values, and arrow-only action Steppers. Grid column alignment and 8-point spacing provide content-derived layout without a guessed value width.
- The visible label/value texts are hidden from accessibility because each Stepper retains the complete existing label and current value. This prevents VoiceOver from announcing the number twice while keeping the controls named.
- The action callbacks, step sizes, bounds, persistence behavior, shipped defaults, and per-alert editor were not changed.

### UI19 implementation and verification
- Only `Sources/BitPrice/Views.swift` changed for the implementation. No test was added because this is a pure layout change; the existing 34-test suite, including all `AlertDefaultStepper` arithmetic tests, remains unchanged and passes.
- No Aqua GUI session was available. A human desktop check must confirm the stepper arrows hold position from cooldown `0` through `604800`, both rows align, and the card fits at Extra Large.

## UI20: fixed-option Alert defaults pickers
- The Grid/Stepper layout was replaced because content-sized columns still changed the card width as values changed, and reaching a one-hour cooldown through 30-second presses was impractical.
- Cooldown and hysteresis now use explicit segmented options. `AlertDefaultPickerOptions.options` returns the unchanged standard list for on-list values; for an off-list stored value it prepends exactly one selected custom option formatted with `decimalString`, preserving the exact Decimal. Selecting a standard tag changes the state and removes the custom option; appearance only computes options and never writes.
- Both new pickers explicitly use `.pickerStyle(.segmented)` and retain immediate commit/error-revert behavior. The old step direction/stepper helper and its arithmetic test were removed rather than retained as dead code.

### UI20 implementation and verification
- `Sources/BitPrice/Views.swift` and `Tests/TestMain.swift` are the only implementation/test files changed for this pass. The new pure tests cover on-list defaults, 45-second/2.5-percent custom labels and exact values, and standard-option counts.
- `bash scripts/run-tests.sh`: 34 passed, 0 failed, 2 expected no-Aqua skips. `bash scripts/build-app.sh`: passed with strict Swift 6 warnings-as-errors, plist lint, signing verification, linkage, and bundled icon checks.
- No Aqua GUI session was available. A human desktop check remains necessary for width stability, seven cooldown segments with a custom value at Extra Large, and custom-segment disappearance after standard selection.

## UI21: retained Alert defaults custom segments
- The custom picker option must be derived from the persisted value once when Settings appears, not from the live picker selection. `@State` retains that option while the screen is visible, so choosing a standard value does not destroy an off-list value that the user may want to restore.
- The retained option is presentation-only and is reseeded on the next Settings appearance from the then-current persisted value. Opening Settings does not write, and selecting the retained option passes its original `Decimal` through the existing binding and commit path without re-parsing or rounding.
- A nil retained option produces exactly the standard list, so shipped on-list defaults do not create custom segments. The pure option tests also assert that a retained list has only one non-standard option and that its value remains exact.

### UI21 implementation and verification
- `Sources/BitPrice/Views.swift` now holds one retained custom option per Alert defaults picker, seeds them in the existing appearance refresh, and renders options from retained state rather than live values.
- `Tests/TestMain.swift` updates test 22d for cross-selection retention, exact custom values, on-list appearance, and single-custom-list behavior.
- The strict test suite passed with 34 tests and 2 expected no-Aqua skips. The strict app build passed, including plist lint, code-sign verification, linkage, and the bundled icon check.
- No Aqua GUI session was available. Desktop review remains necessary to confirm the retained segment survives actual 45s → 1m → 45s interaction, disappears after leaving and returning with 60s stored, and remains usable at Extra Large.

## UI22: selectable chart time range
- `ChartRange` will be the sole source for lookback seconds, Binance interval, Coinbase granularity, and expected candle count. The 24h/7d/30d table is represented as 15m/6h/1d, 900/21600/86400, and 96/29/31 respectively.
- Coinbase's accepted granularity list is the binding constraint: a requested 30-minute 24h density was rejected because Coinbase has no 1800-second granularity. Using 15m for 24h keeps Binance and Coinbase at the same density and remains below both venues' limits.
- The global persisted range defaults to 24h and unknown stored strings fall back to 24h. Range is included in both `ChartRequestToken` and `ChartSeries`, so a response from an earlier selection cannot overwrite a current selection.
- The 7d X axis will use date-plus-time labels because a date alone loses the intra-day distinction while a time alone risks repeating across days; 24h keeps time-only labels and 30d uses dates.
- The accepted baseline mismatch remains deliberate: `points.first?.close` is the opening close of the selected chart series, while the row percentage remains the ticker's 24h value. No annotation or arithmetic change is added.

### UI22 implementation and verification
- `ChartRange` is persisted as the stable raw values `24h`, `7d`, and `30d`; missing and unknown strings normalize to `.hours24` without recovery, and the fresh seed/migration use the same default.
- Binance and Coinbase candle requests derive interval, limit, and granularity from the same range instance. `normalizedCandles` remains gap-preserving and now has direct pure coverage at all three range granularities for filtering and duplicate-bucket replacement.
- Range is included in request tokens and series. Changing the global selection clears and refreshes the displayed series; tokens also require the selected persisted range, preventing late responses from an earlier range from landing.
- The X-axis uses time-only labels at 24h, abbreviated date-plus-time at 7d, and abbreviated date-only at 30d. The chart disclosure and unavailable state use the selected series/global range instead of hardcoding 24h.
- `bash scripts/run-tests.sh`: 37 passed, 0 failed, 2 expected no-Aqua skips. `bash scripts/build-app.sh` passed strict compilation, plist lint, signing verification, linkage, and bundled-icon checks.
- No Aqua GUI session or live network access was available. Desktop review remains necessary for each range's actual fetch/drawing, rapid range switches, and 30d X-axis readability.

## UI23: range-derived chart gaps and reclaimed height
- The old `5_400`-second split threshold encoded 1.5 hours, which was valid only for the previous 1h series. At 7d and 30d it classified every normal 6h/1d interval as a gap, leaving every segment with one point and therefore drawing no line or fill.
- `ChartGapCalculator` now uses `1.5 * ChartRange.coinbaseGranularity`. A single normal bucket remains connected; a missing bucket represented by two bucket intervals breaks the line for all three ranges. The existing per-segment fill and stroke behavior is unchanged.
- The detail region now receives 40% of the finite `GeometryReader` height, leaving 60% for the list. This is a proportion of the actual available panel region rather than a guessed chart/content height. The normal `ViewThatFits` branch still lets the chart fill the remaining space after naturally sized controls; its existing scroll fallback and 140-point chart floor preserve reachability when Extra Large text cannot fit the full stack.

### UI23 implementation and verification
- `Sources/BitPrice/Views.swift` changed only the pure gap helper, segment split call, and list/detail height proportion.
- `Tests/TestMain.swift` adds normal-spacing and missing-bucket assertions for 24h, 7d, and 30d; all ui22 range tests remain unchanged and pass.
- `bash scripts/run-tests.sh`: 38 passed, 0 failed, 2 expected no-Aqua skips. `bash scripts/build-app.sh` passed strict compilation, plist lint, signing verification, linkage, and bundled-icon checks.
- No Aqua GUI session was available. Desktop review remains necessary for visible 7d/30d lines and fills, genuine 24h gap breaks, and the shorter detail/taller list balance at Extra Large.

## UI24 findings
- The panel had no surface after its fixed frame, so a strongly coloured window behind the menu-bar panel could tint the list. The regular material is applied after the fixed frame, covering the padding ring as well as the content. The cards retain their existing secondary translucent fills; their final contrast needs a desktop check on the material in light and dark appearances. Thick material is the next comparison option if regular material proves insufficient, but was not pre-selected.
- Quit now shares the bottom-right footer row with the existing closing disclosure. The row uses first-text-baseline alignment, and the disclosure text is vertically fixed-size so it wraps instead of truncating. The local error line is above this final row so the disclosure row remains last.
- Quit keeps its prominent red style (`.borderedProminent` with `.tint(.red)`), and its label was shortened to "Quit". The implementation brief had asked for a lowered `.bordered` weight on the reasoning that the screen's least frequent action should not carry its highest visual weight; on desktop review that reasoning was rejected. Moving the button out of the gear's corner had already removed the misclick path, and once the proximity hazard is gone, a destructive control benefits from being unmistakable rather than muted. Recorded because the two decisions look contradictory in isolation: the earlier one was about a control that sat where the pointer already was, this one about a control that no longer does.
- Settings is ordered by how far each setting's effect reaches beyond BitPrice, widest first; within a group, a parent precedes what it governs: Launch at login, Price alerts, Alert defaults, Text size. The accepted cost is that Text size is last even when the user came because text is hard to read.
- Extra Large can overflow because system login/notification status and local errors are dynamic text in addition to four cards and the identity block. A bounded GeometryReader gives the scroll content the actual viewport minimum height; the inline ScrollView therefore preserves bottom placement when content fits and makes all content, including Quit, reachable when it does not. No fixed-height estimate was introduced.

## UI25 findings
- The app icon was a placeholder-grade bitcoin glyph on a flat orange squircle. It is replaced by a white chart mark on an indigo/electric-blue/cyan gradient squircle. The mark's two troughs around a lower middle peak form a W; a rising lead-in and a higher breakout extend it on both sides so it reads as a price series rather than a letter.
- The circle used by the reference design was rejected: a circle inscribed in the icon square reads visibly smaller than neighbouring app icons in the Dock. The squircle already in `approximateSquirclePath` is reused unchanged, so only the fill and glyph differ from the previous icon.
- Two gradient stops were not enough. A two-stop gradient forces its midpoint to the average of its ends, which flattens the middle of the tile — the majority of its visible area. Three stops let the middle sit brighter than that average, which is what gives the gradient perceptible range.
- The stroke weight rises from 0.075 to 0.095 of tile width below 64 pixels, with a 1.6-pixel floor. Six vertices is at the limit of a 16-pixel tile, and the constant-ratio weight that suits 512 pixels disappears at 16.
- The legacy small-representation path was the identified risk and was tested rather than assumed. `icon_16x16` and `icon_32x32` are packed as compressed RGB plus an 8-bit alpha mask, not PNG chunks, and a gradient compresses far worse than a flat fill under packbits RLE. Both sizes were extracted back out of the built container with `iconutil -c iconset` and inspected: the gradient survives and the W stays readable at 16 pixels. The container grew from roughly 200 KB to 1.2 MB, which is the expected cost of run-length encoding a gradient rather than a defect.
- `scripts/preview-icon.swift` renders candidate artwork to a single contact sheet without touching the shipped icon or `make-icon.swift`. It is how this design was selected and is kept for the next revision.

## UI26 findings
- Runtime venue selection is now single-source. Existing items keep both optional mappings losslessly on disk, but Binance wins whenever both are present; the Coinbase mapping is ignored by quote/chart runtime in that case. New items set exactly one mapping from the user's combined candidate selection. `marketRevision` remains because remaps can still invalidate a chart response.
- Removed `fallbackTokens`, `fallbackTasks`, `fallbackLoop`, `coinbaseActivity`, `reconcileFallbacks`, `requestFallbackIfEligible`, `isCoinbaseEligible`, `invalidateFallback`, `FallbackRequestToken`, Coinbase stats decoding, and the Coinbase stats polling path. Coinbase remains a selectable mapping and chart venue, but without the deleted quote poll it cannot provide a live row quote; a Coinbase-only row is therefore visibly offline rather than silently substituted. This is the accepted coverage/feed tradeoff.
- Candidate ordering is deterministic and shared by REST results and the combined add flow: USD/USDT first, then USDC, then FDUSD, then all other quote assets; ties use case-insensitive quote, venue, and product ordering. This keeps likely stable-asset markets first without excluding ETH/BTC or any other legal quote.
- `AppModel.formatPrice` already renders a non-dollar-scale `0.024` correctly, so no formatter change was needed; the regression assertion now pins that behavior.
- SPEC divergence is deliberate and documented here rather than by editing SPEC.md: §6.2's Coinbase fallback/stats polling is removed; fallback references in §2.3 and §5's startup/periodic sequence are removed; §6.3 now uses the fixed mapping priority (Binance when present, otherwise Coinbase) instead of quote-source-driven selection; and §4's two independent venue answers/No market requirement is replaced by one combined, required market choice. §4.2's fallback-dependent runtime assumptions now describe a selected mapping only.
- Tests 15 and 16 were deleted because they asserted the removed Coinbase stats/late-response path. New coverage asserts candidate ordering, non-dollar formatting, and loading a v1 item with both mappings without recovery. The test count is 37 passed, 0 failed, with 2 expected no-Aqua skips.
- The accepted product cost is narrower coverage and no alert firing during a dead selected feed, including the loss of the former 60-second Coinbase fallback. Desktop review remains necessary for a many-market combined list at Extra Large, the offline row's dimming/status/Alert · Off disclosure, and sensible ETH/BTC price/chart presentation.

## UI27 findings
- UI26 shipped a broken combination: the add flow offered Coinbase as a selected market, but the same pass deleted Coinbase stats decoding and quote polling. Coinbase-only rows could therefore draw candles while remaining permanently unpriced and offline. UI27 closes that defect without restoring fallback.
- Coinbase is now a primary source only for an item whose selected mapping is Coinbase. It polls that product every 60 seconds; Binance remains the sole source for Binance-mapped items. Neither response can replace the other venue's quote, and legacy items with both mappings remain lossless on disk while Binance wins at runtime.
- The Coinbase response acceptance guard is intentionally one source-owned request identity plus the existing market revision, current Coinbase product ID, and current primary venue. No fallback eligibility rule or `FallbackRequestToken` was reintroduced.
- Coinbase rows use the existing 120-second freshness window. This gives a 60-second poll one full cycle plus request latency before becoming stale and keeps freshness semantics consistent with Binance; an old quote remains visible but is no longer live once it exceeds that window.
- Coinbase's change is unavailable when `last` is not positive or `open` is missing, non-finite, or non-positive. The add confirmation now restores the 60-second polling caveat only for Coinbase-selected markets, including the accepted risk that polling can miss a brief alert breach.
- UI26's any-quote-asset candidate behavior and stable-quote-first ordering remain unchanged. No persistence shape, schema, WebSocket controller, alert arithmetic, fallback compatibility check, or SPEC.md text was changed.

### UI27 verification and remaining risk
- Added direct Coinbase quote-change tests for zero/negative/missing/malformed opens, a Coinbase-primary live-row test, and a stale-response-after-remap test. The full strict suite reports 40 passed, 0 failed, and 2 expected no-Aqua skips. The strict app build passed, including plist lint, code-sign verification, linkage, and the bundled icon check.
- No Aqua session or live venue access was available. A desktop check remains necessary for a Coinbase-only row showing a price and reaching live, Binance rows staying unaffected, a disconnected Binance socket dimming only Binance rows, and the Coinbase-only add-flow caveat.

## UI28 findings
- The CoinGecko-ID-only uniqueness rule was obsolete once quote assets became user-selectable. It was removed. Exact-market uniqueness is already enforced by the existing per-venue product-ID sets: two Binance items with the same product ID or two Coinbase items with the same product ID are rejected, while the same coin on different markets is valid. No redundant CoinGecko/market key check was added.
- Confirmed the runtime seams before changing validation: `binanceProductIDs` remains a set containing each Binance mapping, so distinct markets subscribe to distinct streams; `feedDidAccept` matches the exact product ID, so distinct products do not collide; rows already show the quote asset; and `menuBarTitle` remains symbol plus price as deliberately designed.
- `ValidationFailure` now conforms to `LocalizedError` with its existing `description` as `errorDescription`. This fixes every existing `error.localizedDescription` surface for validation failures without changing the text behavior of other error types; the Add coin duplicate message and Alert editor validation messages therefore become user-readable without per-call-site branching.
- Add coin confirmation now keeps only the market list scrollable. The identity card remains above it, the selected-source disclosure and conditional Coinbase polling caveat remain fixed, Back/Add stay fixed, and the unchanged orange ticker warning is fixed immediately below Add. The no-candidate result has no picker, disclosure, or Add control and offers Back to search while retaining the identity card.
- The detail mapping summary was removed. The chart disclosure now appends the CoinGecko ID, keeps one-line truncation, full-text help, and text selection, and the unavailable-chart disclosure carries the ID as well so it is not lost before the first chart response.

### UI28 verification and remaining risk
- Added validation coverage for same-coin/different-market acceptance, same-coin/same-market rejection, and user-facing ValidationFailure text. The strict suite reports 42 passed, 0 failed, and 2 expected no-Aqua skips; the strict app build passed with plist, signing, linkage, and icon checks.
- No Aqua GUI session or live venue access was available. Desktop review remains necessary for a long market list at Extra Large with the Add/warning footer pinned, the no-market outcome, two ETH rows with different quote assets, and the extra list space after removing the detail mapping line.

## UI28 follow-up findings
- The segmented pickers were reported as hard to click. `.controlSize(.large)` raises their hit height by roughly a third while the system keeps the label proportions correct.
- A literal doubling was asked for and is not achievable. A `.segmented` picker on macOS takes its height from the `ControlSize` enum, so it ignores `.frame(height:)` entirely, and `.scaleEffect` would have doubled the width as well as the text and left the result soft-edged. `.controlSize(.large)` is the whole of what the platform offers here.
- The chart range picker shares its region with the chart, so making it taller leaves the plot slightly shorter. That is absorbed rather than clipped, because `detailHeight` is a proportion of available height rather than a constant.
