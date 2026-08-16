# Task plan: BitPrice UI rework

## Goal
Implement the app icon, textual menu-bar price, larger typography, compact selectable rows, and a bottom chart/detail area without changing non-UI behavior or concurrency contracts.

## Current phase
Complete

## Outstanding work

Carried forward across phases and not yet done. Recorded here so it survives
context loss between sessions.

### User documentation
No end-user documentation exists. The app ships with no explanation of how to
start it, add a coin, set the primary coin (the one whose price shows in the
menu bar), or configure an alert. Every one of those is discoverable only by
clicking around. This was listed as a Phase 6 delivery item and has never been
written.

### Untested paths
Recorded as untested rather than as defects — the code exists and reads
correctly, which is precisely the state that has already proven insufficient in
this project: seven review rounds and 68 tests passed before six defects
appeared within minutes of the first real desktop launch.

- **Deleting the primary coin, and its fallback.** Verified on the desktop
  2026-08-16, both halves. `AppModel.removeItem` reassigns `primaryItemID` to
  `draft.items.first?.id`, and deleting the primary promoted the next item in
  the list as intended. Deleting the last remaining item leaves `primaryItemID`
  nil, and `menuBarTitle` then falls back to its `"BitPrice"` guard: the empty
  panel showed the no-watched-coins and no-coin-details states with no stale
  price left in the menu bar. Tests `22e` and `22f` now hold both cases, and
  were checked by mutation — deleting the reassignment line fails both. Worth
  knowing what `22f` actually proves: with the reassignment gone, the failure
  comes from `validatePersistedState` rejecting a dangling primary rather than
  from the assertion, so the empty-watchlist path was never able to persist a
  bad state. What the test adds is that `removeItem` takes the correct branch
  instead of throwing, and that `menuBarTitle` prints `"BitPrice"` rather than
  the price of a coin that is no longer watched — the quote itself stays in
  `quotes` after the delete, so only the item lookup keeps it off the menu bar.
- **Corrupt-file recovery mode.** `PersistenceStore` has four paths into
  `recovery(...)`: unreadable file, unregistered schema version, a version newer
  than this app supports, and failed validation. `recoveryProtected` then blocks
  writes until an explicit reset.

  All four now have tests. The read-failure and newer-version branches were
  delegated to Codex on 2026-08-16 and landed as `20b` and `20c`, joining the
  migration and validation coverage that already existed. Each asserts the same
  four things, since preserving a damaged file rather than overwriting it is the
  entire point of the mode: `load()` returns `.recovery`, an ordinary `save`
  throws, the bytes on disk are unchanged, and only `allowRecoveryReset` gets
  out.

  Both were mutation-checked here rather than taken on the delegate's word —
  replacing each branch's `recovery(...)` with `.firstLaunch(...)` fails that
  branch's test and only that one.

  Two decisions in `20b` worth keeping. It triggers the read failure with a real
  file at mode `000` rather than a directory occupying the path, which keeps the
  byte-comparison assertion meaningful; permissions are restored in a `defer` so
  the temporary root can still be removed. The known cost is that the test
  depends on `000` being unreadable to the running process — under root it would
  silently assert nothing instead of failing, so a containerised CI run as root
  would quietly lose this coverage. Verified as UID 501 on this host.
  `20c` derives its version from `currentSchemaVersion + 1` rather than a
  literal, so bumping the schema cannot silently retire the test.

  Still unseen: the read-only UI on a desktop. What add, delete, and settings
  edits actually look like while `isReadOnly` is true has never been observed.

### The panel background lets whatever is behind it bleed through
Raised 2026-08-15. **Resolved in ui24.** The panel now applies `.regularMaterial`
after its fixed frame, so the surface is defined rather than inherited. Verified
on the desktop in both dark and light appearance: no colour cast, cards still
distinct. Light mode was the real risk, since the contrast between a translucent
card fill and a lighter backdrop is narrower there; it holds.

### Quit is too close to where the pointer already is
Raised 2026-08-15. **Resolved in ui24.** Quit moved to the footer row at the
bottom-right, sharing a line with the closing disclosure. No confirmation step
was added: the misclick was caused by proximity to the gear, and moving the
button removes that path rather than patching it. Quit kept its prominent red
style — see `findings.md` for why that does not contradict the move.

### Settings item order
Raised 2026-08-15. **Resolved in ui24.** Ordered Launch at login, Price alerts,
Alert defaults, Text size, by the rule **effect reach beyond the app, widest
first; within a group, a parent precedes what it governs**. Use that rule to
place the next setting added. Text size being last is an accepted cost, recorded
in `findings.md`.

### Redesign the app icon
Raised 2026-08-15. **Resolved in ui25.**

The placeholder bitcoin glyph on an orange square is replaced by a white chart
mark on an indigo-to-cyan gradient squircle. The mark is a price line whose two
troughs around a lower middle peak form a W, with a rising lead-in on the left
and a breakout on the right that carries above everything before it. The
extensions are what keep it reading as a series rather than a bare letter.

Decisions worth keeping:

- **Squircle, not the circle of the reference design.** A circle inscribed in
  the icon's square reads visibly smaller than its neighbours in the Dock.
- **Three gradient stops, not two.** A two-stop gradient's midpoint is forced to
  the average of its ends, flattening the middle of the tile — most of its
  visible area. The third stop lets the middle exceed that average.
- **The stroke thickens below 64 pixels** (0.075 to 0.095 of tile width, floored
  at 1.6). Six vertices is at the limit of what a 16-pixel tile holds.

The legacy small-representation path was the identified risk: `icon_16x16` and
`icon_32x32` are packed as compressed RGB plus an 8-bit alpha mask rather than
PNG chunks, and a gradient compresses far worse than the previous flat orange
fill under packbits RLE. Tested rather than assumed — both sizes were extracted
back out of the built `.icns` and inspected. The gradient survives and the mark
stays legible at 16 pixels. The container grew from roughly 200 KB to 1.2 MB,
which is the expected cost of a gradient in a run-length encoding and is not a
defect.

`scripts/preview-icon.swift` is kept alongside the generator. It renders
candidate artwork to a contact sheet without touching the shipped icon, which is
how this design was chosen; the next revision should use it rather than editing
`make-icon.swift` speculatively.

### Quote-asset support is limited to USDT and USD
Raised 2026-08-15. **Resolved across ui26–ui28.**

The hard filters (`quoteAsset == "USDT"`, `quoteCurrency == "USD"`) are gone, so
any legal pair including `ETH/BTC` can be watched. The compatibility constraint
this entry warned about never had to be built: it existed only to stop runtime
fallback substituting one venue's price for another's, and ui26 removed that
substitution entirely. An item has one market, so there is nothing to keep
compatible.

A coin may also be watched in several markets at once — the CoinGecko-ID
uniqueness rule was removed in ui28, leaving per-venue market uniqueness to
reject an exact duplicate.

### Show the source, not just the quote asset, when a row is on fallback
Raised 2026-08-15. **Obsolete — there is no fallback.** ui26 removed runtime
venue substitution, so a row's source never changes and the quote asset it
already prints is stable. Recorded rather than deleted so a later reader does not
re-derive the idea without knowing it was overtaken.

### Add-coin venue selection asks for two answers that have only one option each
Raised 2026-08-15, premise corrected the same day. **Resolved in ui26 and
ui28.** The two single-option radio groups became one combined market list.
The sequencing dependency recorded here held: widening quote assets first turned
that list into a real choice, so the ceremony resolved itself rather than needing
its own simplification.

### Market list layout
Raised and **resolved 2026-08-16**. Each candidate row read
`Binance · BTCUSDT (BTC/USDT)`, whose last two segments were one fact written
twice. The row now leads with `BTC/USDT` and trails the venue in secondary
colour; the product ID is gone, since it is the string sent to the venue's API
rather than something a user checks a choice against. Verified on the desktop.
Near-miss tickers are not made harder to spot — `BTC/USD1` separates itself from
`BTC/USD` more clearly than `BTCUSD1` did, because the slash marks where the
quote asset begins.

### A dropped feed has never been seen
Deferred 2026-08-16 as not worth chasing. The offline row treatment from ui26
and ui27 — the dimmed row, the change losing its up/down colour, the Alert
button saying alerts cannot fire, and a Coinbase-only row reaching live from
polled quotes — has never been observed, because the feed does not drop in
normal use. Recorded rather than deleted: this is the exact shape of untested
path that has already produced defects in this project, so it stays visible for
whoever next has a reason to force a disconnection.

### Look for other price sources
Raised 2026-08-16. Not yet evaluated.

Binance and Coinbase are the only venues. Worth surveying what else could serve
as a source — CoinMarketCap, OKX, AICoin, and whatever else the survey turns up.

**What a candidate has to provide**, given the shape the app settled into across
ui26–ui28. Any survey should answer these per venue rather than comparing on
name recognition:

- **A live push feed, or a poll that is fast enough.** Binance is a WebSocket
  and Coinbase is a 60-second poll, and that difference is already disclosed in
  the UI because a poll can miss a brief alert breach. A venue offering only a
  slow poll is a worse Coinbase, not a second Binance.
- **A product catalogue that can be filtered by base asset.** Adding a coin
  matches candidates by ticker string against a catalogue endpoint. A venue with
  no such listing cannot participate in the add flow as it stands.
- **Historical candles at the three chart granularities** — 15m, 6h, 1d — since
  `ChartRange` derives its request from them. Coinbase already constrains this:
  it accepts only 60/300/900/3600/21600/86400 seconds, which is why 30m was
  rejected for the 24h range. A venue with a coarser or differently-shaped set
  would constrain the range table further.
- **Terms that permit this use.** CoinMarketCap in particular is an API-key
  product with tiered limits, which is a different arrangement from the two
  keyless public APIs used today. That affects distribution, not just code.

**What the current design does not need**, and should not acquire by accident:
a venue does not have to be a fallback for another. Since ui26 an item has one
market and no venue substitutes for another at runtime — see the quote-asset
entry above for why that substitution was removed. Adding a third venue means
adding a third thing a user can choose, not a third link in a chain.

**Cost to weigh.** Each venue adds a candidate fetcher, a quote path, a candle
path, rate-limit pacing, and its own failure modes, and every one of those has
to be exercised on a desktop against the live API. Two venues is already the
larger part of `RESTClients`. A third should be justified by coins or markets
the current two genuinely cannot reach, which is the first thing the survey
should measure.

### Chart time range
The chart is fixed to 24 hours. Evaluated 2026-08-15; decisions below.
Implemented in ui22 and **verified on the desktop 2026-08-16** against the live
Binance API: 24h and 30d both fetch and draw, the range selector switches
between them, the X axis formats by range (clock times at 24h, `7/18`-style
dates at 30d), and the disclosure line reports the selected range. The 15m/6h/1d
granularities are therefore exercised in practice, not only in the pure
normalization tests.

The two ranges showing different price bands looked wrong at first and is not.
Checked 2026-08-16 by fetching both intervals directly from
`api.binance.com/api/v3/klines` with the exact parameters the app sends. The
live data reproduces the screenshots exactly: 24h spans 62,935.72–63,168.17 with
a first close of 63,154.00, and 30d spans 62,823.64–66,556.16 with a first close
of 64,834.22.

The apparent contradiction came from misreading the axis. A range's axis covers
that range's own minimum and maximum, so 30d covering 62,824–66,556 comfortably
contains the 24h band rather than sitting above it, and the dashed line on the
30d chart is the baseline — the close from thirty days ago — not the current
price. What must agree between the two is the **last** close, and it does:
63,121.92 in both.

Two facts worth keeping, since neither is obvious from the code:

- The 30d chart's final bucket is stamped 08:00 local while 24h's is 10:45.
  Binance daily candles open at UTC 00:00, so the final one is the day still in
  progress and its close is the current price. That is why the two ranges end on
  the same number.
- `ChartRange.candleCount` is 31 for 30d but Binance returns 30, because
  `startTime` lands mid-day thirty days back and the partial candle before it is
  not counted. `limit` is a ceiling rather than a quota, so this affects nothing.

#### Chart time range evaluation (2026-08-15)

The 24-hour window is hardcoded in three places that are not independent
parameters but three expressions of one decision:

- `AppModel.refreshChart` — `end.addingTimeInterval(-86_400)`
- `RESTClients.binanceCandles` — `interval=1h`, `limit=25` (25 is 24÷1 + 1)
- `RESTClients.coinbaseCandles` — `granularity=3600`

Adding ranges without unifying these would turn one guessed constant into
three, which is the defect shape already removed twice from this project
(`nonChartHeight`, `yAxisWidth`).

**Venue granularity limits.** Binance takes an interval enum
(`1m/3m/5m/15m/30m/1h/2h/4h/6h/8h/12h/1d/...`) with `limit` up to 1000.
Coinbase accepts only `60/300/900/3600/21600/86400` seconds and at most 300
candles per request. The chosen ranges must be expressible on both, since
`chartSelection` falls back between venues.

| Range | Granularity | Candles | Binance | Coinbase |
|---|---|---|---|---|
| 24h | 15m | 96 | `15m` | `900` |
| 7d | 6h | 29 | `6h` | `21600` |
| 30d | 1d | 31 | `1d` | `86400` |

All three are legal on both venues and well under the 300-candle cap, so no
per-venue table and no pagination is needed.

**Decisions.**

- **15m for 24h, not 30m.** 30m was requested, but Coinbase has no 1800-second
  granularity, so the two venues would draw different densities for the same
  range. 15m exists on both, is finer than the current 1h, and stays at 96
  candles.
- **The range is global, not per-coin.** Only one chart is on screen at a time.
- **The range persists.** A new `PersistedState` field with a default,
  `currentSchemaVersion` stays 1 — the same additive pattern used for
  `alertsEnabled`, `textSize`, and the alert defaults.
- **The baseline mismatch is accepted and left alone.** At 7d the chart baseline
  is the 7-day-old close, while the row's percentage comes from the WebSocket
  ticker and is always 24h. Two different bases sit side by side. The ui15
  tooltip already says "this chart series' opening close", which stays accurate.
  Not annotating it is a deliberate choice, recorded here so a later reader does
  not mistake it for an oversight.

**Required plumbing.** `ChartRequestToken` needs the range as a field: without
it, a stale 24h response arriving after a switch to 7d cannot be distinguished
from a current one, and would overwrite the newer series. This is correctness,
not a feature — `marketRevision` already exists for the same class of problem.
`ChartSeries` needs it too, so the X axis can format labels by range.

**Untested area this touches.** `normalizedCandles` de-duplicates by
`bucketStart` used as a dictionary key. Its behaviour at bucket boundaries has
only ever been exercised at 1h granularity.

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

## UI17 completion
- [x] Read the current Settings, persistence, domain, notification, test, and build context.
- [x] Add system-authoritative login-item and notification-permission status with inline guidance and no notification-service changes.
- [x] Add schema-1 default alert cooldown/hysteresis persistence, validation, migration, and new-alert seeding.
- [x] Add persistence acceptance tests and run the strict test/build/audit checks.
- [x] Record the ad-hoc-signing and no-Aqua limitations for desktop review.

## UI18 completion
- [x] Read the current Settings card, persistence defaults, validation, tests, and build context.
- [x] Replace Alert defaults text fields/Save action with immediate bounded Steppers while preserving untouched off-step values.
- [x] Change fresh, missing-key, and migrated defaults to 30 seconds / 10 percent without changing schema version or existing alerts.
- [x] Add pure step arithmetic tests, update persistence assertions, run strict tests/build/audits, and record desktop-only risks.

## UI19 completion
- [x] Read the Alert defaults card and relevant project/build context.
- [x] Replace the two rows with a three-column content-sized Grid and preserve action-based stepping/accessibility.
- [x] Run the unchanged test suite, strict build, bundle checks, forbidden-token audit, and record desktop-only layout checks.

## UI20 completion
- [x] Read the current Alert defaults picker/card, persistence, tests, and build context.
- [x] Replace the Grid/Steppers with explicit segmented cooldown/hysteresis pickers and exact custom off-list options.
- [x] Remove dead stepper helpers/tests, add pure picker-option tests, preserve immediate persistence/schema/defaults, and verify strict build/tests/audits.

## UI21 completion
- [x] Read the current Alert defaults picker helper, Settings appearance/persistence path, and test 22d.
- [x] Retain each appearance-derived custom option in `@State` for the Settings screen lifetime without writing on appearance or changing the persisted schema.
- [x] Update pure option tests for cross-selection retention, exact custom values, on-list absence, and one-custom-only behavior.
- [x] Run strict tests/build, bundle and forbidden-token audits, and record the no-Aqua desktop checks.

## UI22: selectable chart time range
- [x] Add the single-source `ChartRange` table and persist the global range with a 24h fallback while keeping schema version 1.
- [x] Thread range through chart requests/tokens/series and use it for both venue requests and stale-response checks.
- [x] Add the inline segmented chart selector, immediate persistence, and range-aware X-axis/disclosure labels.
- [x] Add pure range, persistence, normalization, and request-shape tests without live network calls.
- [x] Run strict tests/build/bundle audits and record the Coinbase constraint, accepted baseline mismatch, and no-Aqua/no-network limitations.
- **Status:** complete

## UI23: range-derived chart gaps and reclaimed height
- [x] Read the current gap-splitting and finite list/detail layout paths plus the existing range/tests/planning context.
- [x] Derive the segment gap threshold from each range's bucket duration and add pure normal/missing-bucket coverage for all ranges.
- [x] Give the list the reclaimed space through a defensible finite-height proportion without changing chart axes/data or row typography.
- [x] Run strict tests/build/audits and record the Extra Large/layout and no-Aqua limitations.
- **Status:** complete

## UI24: opaque panel and deliberate Settings layout
- [x] Apply regular material after the fixed panel frame, keeping the existing card fills unless desktop review shows a contrast defect.
- [x] Move Quit into the wrapped first-baseline footer row with a bordered destructive style and keep Back as the only header control.
- [x] Reorder the unchanged Settings cards by effect reach: Launch at login, Price alerts, Alert defaults, Text size.
- [x] Preserve bottom placement when content fits and add a bounded scroll fallback for dynamic Extra Large overflow.
- [x] Run strict tests/build checks and append the material, ordering, accepted cost, and no-Aqua notes.
- **Status:** complete

## UI26: one selected venue and visible dead feeds
- [x] Remove Coinbase runtime fallback state, polling, stats decoding, and acceptance guards while preserving market revisions and Binance feed lifecycle behavior.
- [x] Allow any legal quote asset, deterministically order venue candidates, and verify low-price formatting.
- [x] Replace the two venue-selection groups with one combined inline market list and create exactly one mapping for new items.
- [x] Keep legacy mappings lossless on disk while using Binance when an old item has both mappings; dim offline rows and disclose that alerts cannot fire.
- [x] Update focused tests, record the SPEC divergence and accepted coverage/feed tradeoffs, run strict build/tests/audits, and write the implementation summary.
- **Status:** complete

## UI27: Coinbase primary quote polling
- [x] Read the post-UI26 single-source runtime, REST, domain, view, feed, alert, persistence, test, and build context before editing.
- [x] Restore Coinbase stats and 60-second primary polling without restoring fallback eligibility, substitution, or fallback tokens; preserve revision/product guards and legacy dual-mapping compatibility.
- [x] Make row presentation source-aware and restore Coinbase-only polling disclosure in the add flow while keeping UI26's dead-feed visuals and selected-source copy.
- [x] Add unavailable-change, Coinbase-live, and stale-after-remap tests; run strict tests, build, bundle checks, and forbidden-token audits.
- [x] Record the UI26 broken combination, the 120-second freshness decision, the polling alert-breach tradeoff, and no-Aqua/no-network desktop limits.
- **Status:** complete

## UI28: multi-market watch identity and concise add flow
- [x] Read the current post-UI27 domain, model, views, tests, persistence, feed, alert, build, and planning context.
- [x] Replace CoinGecko-ID-only uniqueness with the existing per-venue market uniqueness behavior; preserve multi-market streams, exact feed matching, row quote display, menu-bar title, schema 1, and legacy dual mappings.
- [x] Surface ValidationFailure messages through `localizedDescription` without changing other error types, and add validation/error tests.
- [x] Keep only the candidate list scrollable, pin Back/Add/disclosures/warning, remove redundant copy and Coin heading, add the no-market outcome, and append the CoinGecko ID to the selectable chart disclosure.
- [x] Run strict tests/build/bundle audits and record desktop-only verification needs.
- **Status:** complete

## UI28 follow-up: larger segmented-control hit targets
- [x] Apply `.controlSize(.large)` to all five segmented pickers (alert cooldown, alert hysteresis, text size, chart range, alert direction).
- **Status:** complete
