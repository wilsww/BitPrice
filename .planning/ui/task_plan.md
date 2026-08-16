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

  The read-only UI was walked through on a desktop 2026-08-16, by setting
  `schemaVersion` to 99 in the real state file with everything else untouched.
  That branch was chosen over malformed JSON because its message names the
  version, so the screen itself identifies which of the four branches ran.
  All four read-only behaviours are correct: add is disabled, delete and reorder
  are disabled, the Settings controls are disabled, and a reset button exists.
  An earlier reading of the source suggested there might be no way out of
  recovery mode at all; that was wrong — `resetRecovery()` is wired to a button
  in the banner area.

  The walkthrough produced three defects, all in what the mode *says* rather
  than what it does. They are recorded below under their own entry, since the
  branch coverage above is unaffected by them.

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

### The Settings screen scrolled when it had no need to
Raised and resolved 2026-08-16. Settings showed a scrollbar at Medium, where
everything already fits. Two attempts got it wrong before the third worked, and
the wrong turns are the useful part of this entry:

- **Unconditional `ScrollView`.** The content was pinned to `minHeight:
  geometry.size.height` so the trailing `Spacer` could hold Quit at the bottom,
  which left the scroll content exactly its own height — close enough, once the
  scrollbar gutter and rounding are counted, to register as overflow.
- **A `ViewThatFits` pair**, copied from the selected-detail region. It chose the
  scrolling branch at Medium while leaving Extra Large — the *taller* content —
  unscrolled. The plain branch is measured carrying the enclosing
  `maxHeight: .infinity` frame, so it reports that it never fits, and Extra Large
  escaping was luck rather than the mechanism working.

The fix is no scroll construct at all plus one changed constant: **Small's panel
is 750 rather than 700**. That is the real finding here. The panel heights grow
40% from Small to Extra Large while the type does not, so the smallest size is
the *tightest* fit rather than the roomiest. Removing the scroll view exposed
that immediately — Small clipped its own header and the Quit row — which is why
"the settings are a fixed set of cards and cannot overflow" was wrong as stated.
Verified on the desktop at Small and Extra Large: no scrollbar, nothing clipped,
Quit in place at both.

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

### Recovery mode says the wrong things
Raised 2026-08-16 by the desktop walkthrough recorded above. **Resolved and
verified on the desktop the same day**, including a second walkthrough that
confirmed the backup file now appears with all four coins intact — the same
operation that silently destroyed them the first time. Three defects, in
increasing order of how much they matter:

- **The banner runs two sentences together.** `AppModel` composes it as
  `"\(reason) Original file preserved at \(path)."`, which assumes each `reason`
  ends in punctuation. None of the four do, so it reads `...than this app
  supports Original file preserved at...`. The fix belongs in the composition,
  not in the reason strings — `20c` asserts on the exact reason text.
- **It explains the cause and not the consequence.** The banner states a
  technical fact and stops. It never says the watchlist did not load, so the
  single BTC row on screen looks like data rather than a stand-in. And
  `Schema version 99` means nothing to a user whose actual situation is that
  the file came from a newer BitPrice — most plausibly a downgrade.
- **Reset destroys the file the banner promised was preserved.** The button sits
  directly under a message saying the original is safe, and `resetRecovery()`
  saves a fresh seed straight over it. Confirmed by hand: a four-coin watchlist
  became a one-coin seed and the original bytes were gone. `Reset protected
  file` also reads like a repair rather than a discard.

The chosen fix copies the damaged file aside before overwriting, under a fixed
filename so each reset replaces the previous copy rather than accumulating —
the alternative of timestamped copies was rejected because deleting the user's
data is exactly the code worth not writing. A copy failure must abort the reset:
the read-failure branch means the file can genuinely be unreadable, and
discarding someone's only copy because the backup step failed is worse than
refusing to reset. No confirmation dialog: a `MenuBarExtra` panel dismisses when
a separate presentation takes key status, which is why every editor here is an
inline route.

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
Raised 2026-08-16. **Surveyed 2026-08-16; recommendation is to add nothing.**
The criteria below were written before the survey and are left as written; the
measurements that answer them follow at the end of the entry.

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

---

**Survey, 2026-08-16.** The cost paragraph above asked for the reachability
measurement first, so that is what was done first, and it turned out to settle
the question before the API comparison mattered.

*What the current two already reach.* Both catalogues were fetched live —
`api.binance.com/api/v3/exchangeInfo` filtered to `status == TRADING`, and
`api.exchange.coinbase.com/products` filtered to online and not
trading-disabled. Binance offers 1,371 pairs across 491 base assets, Coinbase
517 pairs across 402. They overlap on 219 assets, so the union the app can
reach today is **674 distinct base assets**. That number is the baseline every
candidate has to beat.

*What a third venue would add.* Five keyless spot catalogues were fetched the
same way and differenced against that union. The raw counts look tempting until
they are filtered for liquidity, which is the step that matters — an asset with
no volume is a row a user can add and then watch sit still.

| Venue | New base assets | Of those, >$1M 24h volume |
|---|---|---|
| Gate | 1,556 | 23 |
| KuCoin | 386 | 28 |
| Kraken | 261 | 4 |
| OKX | 124 | 9 |
| Bybit | 111 | 11 |

Volume was taken from each venue's own 24h ticker endpoint, counting only
USD/USDT/USDC quotes so the figures are comparable. Gate's 1,556 collapsing to
23 is the whole story of that column: the long tail is almost entirely dormant
listings.

*The ceiling, not just the best single choice.* Unioning the liquid-new sets
across all candidates gives **49 assets** — that is the most any third venue,
or any number of them, could add. Inspecting the list shrinks it further:
`ETH5L`, `SOL5L` and `WLD5S` are leveraged tokens rather than coins, `XBT` is
Kraken's own name for BTC and is already reachable, `GBP` is fiat, and one
entry is a Chinese-language name. What remains is roughly forty low-cap and
meme tickers, of which exactly one is a coin most people could name: **XMR**
(Monero, $38M/24h on KuCoin), delisted by both Binance and Coinbase, available
on KuCoin and Kraken.

*The API comparison, for the record.* It was run anyway, and would not have
changed the outcome. KuCoin, OKX and Bybit each clear all three technical
gates — public WebSocket ticker, base-asset-filterable catalogue, and 15m/6h/1d
candles, the last verified by live request rather than from docs. Kraken fails
the candle gate: `interval=360` returns `{"error":["EGeneral:Invalid
arguments"]}`, so it has 4h and 1d but no 6h, and would force the range table
to change. CoinGecko and CoinMarketCap both fail on candles at the free tier —
CoinGecko gives auto-granularity only (30m/4h/4d by span, explicit intervals
are paid) and CoinMarketCap serves no OHLCV at all on Basic. CryptoCompare now
needs a key and has moved streaming behind an enterprise contract since the
CoinDesk acquisition. Geography is worth noting for whoever revisits this:
Bybit and OKX's global endpoints both block US access, which Binance already
does too.

*What comparable apps use.* Ten open-source tickers were surveyed — macOS menu
bar, Linux panel extensions, and terminal apps — to see whether they converged
on something this survey had missed. They did not converge on a third exchange.
They split into two shapes. The larger group calls an **aggregator** rather than
any exchange: CoinGecko in `miguelmota/cointop`, `Gituser143/cryptgo` and the
GNOME `Crypto-Price-Tracker`, with CoinCap and CoinMarketCap appearing as
alternates. The smaller group calls **exchange APIs directly**, which is what
this app does — `AttackOnMorty/crypto-ticker` is Binance WebSocket only,
`mqulateen/crypto-ticker-macOS` is Coinbase only, and two of the older projects
(`alecananian/osx-coin-ticker`, `gnome-shell-bitcoin-markets`) instead let the
user pick from a long exchange list. Two stock-first apps use Yahoo Finance,
which is outside this app's scope, and one depends on an unofficial scraper
host. Nothing in the sample suggests a fourth technical requirement the criteria
above missed.

*OKX specifically, since being a large exchange is the obvious reason to ask.*
It was evaluated on its own after the table above, because name recognition is a
fair reason to revisit a number. Everything technical passes. Its public
WebSocket was connected to from this machine and pushed live ticker frames
carrying `last` and `open24h`, which is exactly the pair the row needs to show a
price and a change; `/api/v5/market/candles?bar=6H` was requested directly and
returned data, so it clears the granularity gate that Kraken fails; and its
`instruments` catalogue exposes `baseCcy`/`quoteCcy` for the add flow. No API
key, no payment.

What it does not clear is the coverage bar. OKX adds **9** liquid base assets
over the current pair — `DOS`, `OKB`, `AEON`, `USDG`, `BASED`, `PI`, `CORE`,
`SLX`, `CC` — and does **not** carry XMR, the one recognisable coin the whole
survey turned up. Its 247 overlapping assets mean it mostly offers a second
market for coins already reachable, not access to coins that are not.

That is a coverage finding, and it did not decide the matter: OKX is scheduled
as step two of the entry below. Recorded so the two arguments stay separable —
wanting a major venue in the picker is a product judgement, and this paragraph
is the measurement that judgement should be made against, not a veto over it.

*The aggregator question, which the repo survey raised and the API survey
answered.* Aggregators are popular in that sample because most of those apps
only need a number, not a chart. This app needs candles, and that is where
aggregators fail. CoinGecko's keyless endpoint does work without a key —
`/simple/price` and `/coins/{id}/ohlc` both answered on request — but the OHLC
candles came back spaced **1,800 seconds apart** on a `days=1` request, which is
the documented auto-granularity, not a choosable interval. 15m, 6h and 1d are
paid-plan only, so it cannot serve `ChartRange` as written. CoinCap, cited by
two repos in the sample, returned an empty body and appears to be gone. So the
aggregator route is not an unexplored alternative — it is a route this app's
chart requirement closes.

*Conclusion.* Adding a venue costs a candidate fetcher, a quote path, a candle
path, rate-limit pacing, and a desktop pass against the live API — the cost
paragraph above lists them. The best available return on that is KuCoin's 28
assets, of which one is recognisable. That does not clear the bar the same
paragraph set, and the comparable-app survey found no fourth requirement and no
better-shaped option. **Recommendation: stay at two venues.** The one specific
thing that would reopen this is a request for Monero, which no amount of work on
Binance or Coinbase can satisfy, since both have delisted it; KuCoin and Kraken
both carry it, and of those two only KuCoin passes the 6h candle gate.

### Make the price source a replaceable part
Raised 2026-08-16, out of the price-source survey above. **Three steps — one,
2a, 2b — and they must not be combined**; see "Why they must be separate" below.

**Step one is done and was verified on the desktop 2026-08-16**; see the closing
section of this entry. **Step two — adding OKX — is outstanding and is the
second half of an agreed plan, not an open question.** It was split from step
one on purpose so that a failing test could not be ambiguous between the two;
the split was a sequencing decision, not a decision to drop the second half.
Step two has since been split again into **2a (OKX polling, half a day) and 2b
(the push-feed seam, one to two days)**, on the same reasoning.

The survey earlier in this file argues OKX does not pay for itself on coverage,
and that argument stands as written. It is an input to the decision, not the
decision: the reason to add a large venue can be that users expect to see it in
the picker, which is a product judgement rather than a measurement. The
measurement is recorded above so that judgement can be made with it in view.

The survey concluded that no third venue earns its keep on coverage. A separate
question came out of estimating the work: adding *any* venue is more expensive
than it should be, and that is a property of this code rather than of the venues.
The estimate is 2–3 days for a venue that is otherwise a straight copy of the
Coinbase paths. That cost is worth removing on its own terms, independent of
whether a third venue is ever added.

**What is already right, and should not be rebuilt.** The measurement here was
better than expected, so the work is smaller than "introduce an abstraction"
suggests:

- The **common data structures already exist and are already venue-agnostic**.
  `VenueCandidate`, `CandlePoint`, `ChartSeries` and `Quote` each carry a
  `venue`/`source` field and none of them are shaped around a particular API.
  Normalising each venue's response into a shared type is done.
- The **lower abstractions are already protocols**: `HTTPTransport`,
  `RequestPacer`, `WebSocketSessionTransport`, `WebSocketTaskTransport`. They
  are substitutable and already carry test doubles.

**Where the hardcoding actually is.** Three places, and only three:

1. **Dispatch sites — five of them, all in `AppModel`.** Lines 327–328 fan out
   to `binanceCandidates` and `coinbaseCandidates` by name, 522 calls
   `coinbaseStats`, and 566/570 branch between `binanceCandles` and
   `coinbaseCandles`. This is what a parent service should absorb.
2. **Named mapping fields — the real debt.** `WatchItem` carries
   `binanceMapping` and `coinbaseMapping` as two named properties, and those
   names recur through both `PersistenceStore` DTO layers, through
   `validateState`, and in code that is only correct while there are exactly
   two venues: `primaryVenue(for:)` is an if-chain, and
   `chartTokenStillMatches` selects a mapping with a ternary on
   `token.venue == .binance`. This is the only part that requires a schema
   change.
3. **`Binance`-prefixed names for things that are not Binance-specific**:
   `BinanceFeedSink`, `BinanceTick`, `BinanceLifecycle`. Renames, not rework.

**The shape to aim for.**

```swift
protocol PriceSource: Sendable {
    var venue: Venue { get }
    var liveness: SourceLiveness { get }      // .push or .polled(seconds:)
    func candidates(symbol: String) async throws -> [VenueCandidate]
    func quote(productID: String) async throws -> SourceQuote
    func candles(productID:range:start:end:) async throws -> [CandlePoint]
    func supports(_ range: ChartRange) -> Bool
}
```

Two details in that signature carry existing behaviour that is currently
hardcoded in the UI. `liveness` replaces the literal "Coinbase polls every 60
seconds" text, which appears in three places in `Views.swift` and would be
silently wrong for any new venue; the disclosure should be derived from the
source rather than written per venue. `supports(_:)` turns "this venue lacks a
granularity" into data — the survey found Kraken has 4h and 1d but no 6h, and
today that could only be expressed as a special case.

**Step one — restructure, with the venue list unchanged.** Introduce
`PriceSource`, move the Binance and Coinbase implementations behind it, collapse
the five dispatch sites, collapse the two named mapping fields into one, and
carry the schema migration. Behaviour must not change: the same two venues, the
same UI, the same disclosures. The existing 50 tests are the regression net for
exactly this kind of pure structural change.

**Step two — add OKX. Outstanding, and it splits again.** Reading the code
after step one landed showed the work is not one piece. Three of the four parts
are additive and touch nothing that already works; the fourth rewrites the
connection layer. Splitting them costs nothing and buys the same thing the
step one/two split bought: a failing test that can only mean one thing.

Its technical feasibility is already established rather than assumed — the
WebSocket was connected to from a development machine and pushed live ticker
frames, and the 6H candles were fetched directly. See the OKX paragraph in the
survey above for both. What remains is the work, not the question of whether it
can be done.

#### Step 2a — OKX as a polling source. Landed 2026-08-16, awaiting desktop test.

Everything except the push feed. OKX has a full REST ticker, so it can ship as
a polled source — the way Coinbase runs today — and still be a usable venue:
visible in the picker, quoted, charted, alertable.

**Poll interval: 30 seconds, decided 2026-08-16.** Coinbase polls at 60. OKX's
public REST limit is 20 requests per 2 seconds per endpoint, which 30-second
polling does not come close to, and the shorter interval halves the window in
which an alert threshold can be crossed unseen. `liveness` already carries the
number, so the UI will say "polls every 30 seconds" without being told.

- **`OKXPriceSource`.** A new conformance next to `CoinbasePriceSource`, which
  is the working template. Three new methods on `RESTClients` (candidates,
  ticker, candles) with their `Decodable` types, then one line added to
  `configuredPriceSources`. No existing call site changes.
- **`Venue.okx`.** One case. The DTO shape does not change, so this is not a
  schema version bump — but it is still **one-way for user data**: a v2 file
  containing `"okx"` will fail to decode on a build that predates the case, and
  `Venue` is decoded as part of `MappingDTO`. The pre-2a `watchlist.json` should
  be backed up the same way the v1→v2 migration was, and for the same reason.
- **The UI needs nothing.** Step one made the polling disclosure derive from
  `liveness` and the no-market message derive from `configuredSourceNames`, so
  both pick up a third venue on their own. Test 22g pins that seam and should be
  extended rather than replaced.

**`VenueCandidateOrdering` stays alphabetical — decided 2026-08-16.** Its final
tie-break is `venue.rawValue`, so `binance` sorts before `coinbase` today and
`okx` will sort last. That is an accident of spelling rather than a ranking, and
adding a third venue makes the accident visible.

The alternative considered was ranking by traded volume, which raised the
question of whether the picker should then *show* the volume it sorts by. It
should — sorting by a number the user cannot see is worse than not sorting.
**But the catalogue responses do not carry volume**, and this was checked rather
than assumed: Binance `/api/v3/exchangeInfo` and Coinbase `/products` both
return instrument definitions only (symbol, status, base/quote, precision,
filters), as does OKX `/api/v5/public/instruments`. Volume lives on the ticker
endpoints, which are a different request per candidate — three extra calls for a
ticker listed on all three venues, all of them in front of a user waiting to add
a coin, all queued behind `RequestPacer`.

So volume ordering is a separate piece of work with its own cost, not part of
adding a venue. Recorded as its own entry below. 2a does not touch
`VenueCandidateOrdering`.

#### Step 2b — the feed seam. One to two days, and the real risk.

`BinanceFeedController` is the one thing step one deliberately did not
abstract, and it is not a thin wrapper. Its 290 lines carry the app's only real
concurrency-correctness machinery: three-way identity checking across
`configurationID`, `connectionID` and `taskIdentifier` (`callbackIsCurrent`),
lease timeouts, failure backoff, sleep/wake. `AppModel` holds it by concrete
type, not by protocol, and `feedDidAccept` filters on
`mapping?.exchange == .binance`, so an OKX tick reaching that method today would
be dropped.

The lifecycle machinery is genuinely venue-neutral and worth sharing. What is
not shareable is subscription and parsing: Binance names its streams in the URL,
which is why `maximumCombinedStreamURLBytes` exists at all, while OKX connects
first and then sends `{"op":"subscribe",…}`, returning `{"arg":…,"data":[…]}`.
`replaceProducts` therefore means "reconnect to a new URL" on one venue and
"send an unsubscribe and a subscribe" on the other. The same method name cannot
carry both implementations.

Doing this properly means extracting a `PriceFeed` protocol and a controller
that owns several feeds, leaving each venue's identity checking inside its own
implementation. That is a rewrite of the connection layer. The existing feed
tests all name `BinanceFeedController` concretely and will move with it.

If 2b is never done, OKX stays on a 30-second poll and says so in the UI. That
is a real product state, not a broken one.

---

**2a landed 2026-08-16** in "feat: add OKX as a third price source, polling every
30 seconds", delegated and then verified rather than taken on report. The test
count went from 51 to 55. `bash scripts/build-app.sh` is clean and the installed
app in `~/Applications` was synced to the new binary, hash-compared.

It was additive as predicted: `DomainModels.swift` gained one enum case and one
computed property, `RESTClients.swift` gained the OKX types, three fetchers, a
pacer and the `PriceSource` conformance, and no existing call site outside
`configuredPriceSources` was edited. `BinanceFeedController` was not touched.

*The endpoint shapes were fetched live before the task was written*, which is
what caught three differences that documentation alone would not have made
obvious and that a plausible implementation would get wrong:

- `history-candles` returns rows **newest-first**, opposite to both existing
  venues. Passing them through `normalizedCandles` sorts them; adding a reversal
  on top would have un-sorted them.
- Its timestamps are **milliseconds**, like Binance and unlike Coinbase's
  seconds. A mix-up puts every point in 1970 and draws an empty chart.
- OKX reports failure as a **non-zero `code` string inside an HTTP 200 body**, so
  `requireSuccess` alone would accept an error response as market data.

Each is now pinned by a test that also asserts the request path and query items,
so a wrong endpoint or bar string fails rather than silently returning nothing.

**One defect was found, and Codex reported it against its own work.** The task
said the UI needed no edits because step one made the disclosures derive from
`liveness`. That was true, but the venue *name* in those sentences came from
`venue.rawValue.capitalized`, which renders `okx` as **"Okx"** — in five places:
the market picker, the chart caption, both polling disclosures, and the
duplicate-market validation error. Codex left it alone as out of scope and said
so plainly instead of quietly fixing or quietly ignoring it. Fixed separately in
"fix: spell OKX the way OKX spells it" by giving `Venue` an explicit
`displayName`, so a fourth venue must state its own spelling rather than inherit
a rule that only happened to fit the first two. Test 22h pins it; both 22h and
22g fail if a name regresses, verified by mutation.

**Not yet verified on the desktop.** The live `watchlist.json` was backed up to
`watchlist.json.pre-okx` (sha256 `be82cd8f…`) with a hash-verified restore
script that was run once to prove it works, not merely written. This matters
because adding `Venue.okx` is one-way for user data even without a schema bump:
a file containing `"okx"` cannot be decoded by a build predating the case.

What the desktop test needs to show: an OKX market appears when adding a coin
and is spelled "OKX", selecting it produces a live price and a drawn chart at
all three ranges, the alert editor says OKX polls every 30 seconds, and the four
existing Binance items are untouched.

**Why they must be separate.** Each split isolates one class of failure.
Combined, step one and step two leave a failing test unable to distinguish a
restructuring mistake from a mis-wired new venue. Combined, 2a and 2b leave it
unable to distinguish a bad OKX mapping from a broken connection layer — and 2b
touches the only code in the app with real concurrency-correctness machinery, so
that is exactly the distinction worth keeping.

**The risk that needs stating.** Step one collapsed two mapping fields into one,
which is a schema change, and schema changes on this app land in the recovery
path hardened earlier in this session. A migration bug does not produce a crash;
it produces a user whose watchlist is in read-only recovery mode. That work is
done and verified against a real file, but the same exposure returns in a
smaller form in 2a: adding `Venue.okx` does not change the DTO shape, yet a file
containing it cannot be read by any build that predates the case. Both times,
user data is the thing at stake and deserves the most test attention.

---

**Step one landed 2026-08-16** in "refactor: put the two venues behind a
PriceSource protocol", delegated and then verified rather than taken on report.
The test count went from 50 to 51.

*The migration was verified against a real file, not only fixtures.* This is the
part that mattered, because a migration bug does not crash — it drops the user's
watchlist into read-only recovery. The live `watchlist.json` was a v1 file with
four Binance-mapped items (BTC, ETH, SOL, ONDO), which is exactly the case the
migration has to decide. It was backed up to `watchlist.json.pre-v2-migration`
with a hash-verified restore script, and the restore script was itself run once
before the test rather than merely written. After launching the new build: the
file is now `schemaVersion: 2`, all four items survive in their original order,
each `binanceMapping` collapsed to a single `mapping` carrying `binance` and its
original product ID with none mis-assigned to Coinbase, the primary coin is
still BTC, the row reads `live`, and no recovery warning appeared.

*One thing that looked like a loss and was not.* No alerts were present after
the migration. Comparing the pre-migration backup shows all four items had
`alert: null` before it as well, so nothing was dropped — the alerts had simply
never been saved. Worth recording because "the alerts are gone" is exactly what
a migration bug would look like.

*Two behaviours found during verification that the delegated summary did not
report.* Both were checked against the pre-change source before deciding.

- The alert editor printed "Coinbase polls every 60 seconds and can miss a brief
  breach" **unconditionally**, including for Binance markets, where it was
  simply false. It now derives from the selected source's `liveness` and appears
  only for polled venues. This is a deliberate behaviour change, kept because
  the instruction not to change behaviour exists to stop a restructuring from
  breaking correct behaviour, not to preserve a wrong sentence.
- Neither polling disclosure had any test coverage. Test 22g now pins
  `sourceLiveness(for:)`, the seam both views branch on.

*Mutation checks run on the highest-risk paths*, since a green suite only proves
the tests pass, not that they can fail: flipping the migration's Binance-first
rule to Coinbase-first fails exactly one test, and removing the v1 dispatch
branch fails four by dropping real v1 files into recovery. Changing Coinbase's
poll interval from 60 to 30 fails 22g. The source was restored exactly after
each.

*An alert surviving a quit-and-relaunch was then exercised too*, closing a gap
that predated this change. An alert was set on BTC (above 70,123, cooldown 60,
hysteresis 10), the app was quit and reopened, and the editor came back with
every field intact. The on-disk v2 record matches what the editor shows, which
also exercises something fixtures could not: writing an alert through the new
single-mapping DTO rather than only reading an old one. The same screen
confirmed the disclosure fix — a Binance market no longer shows the Coinbase
polling sentence.

Noted so it is not later mistaken for a defect: that alert was saved with
`isEnabled: false`, because the editor's Enabled toggle was off. The alert
persists and will not fire until the toggle is turned on, which is the intended
behaviour rather than a lost setting.

### Order the candidate markets by traded volume, and show it
Raised 2026-08-16 while scoping OKX; deliberately kept out of that work.

When a ticker is listed on more than one venue, the add-coin picker orders the
candidates by quote asset first (USD/USDT, then USDC, then FDUSD) and breaks
remaining ties on the venue's name, alphabetically. That tie-break is spelling,
not judgement. With two venues it happens to agree with liquidity; with three it
stops agreeing, and it will never be the reason a user should prefer one market.

Volume is the honest ordering, and if the list is sorted by volume it should
display volume — a list ordered by an invisible number is harder to trust than
an arbitrary one. Same-ticker comparison across venues is sound, since each
venue reports 24h volume in the base asset and the base asset is the same one
the user searched for. Cross-ticker comparison would need USD conversion; this
feature does not.

**The cost is request count, and it lands where it is most visible.** The
catalogue endpoints do not carry volume — checked, not assumed: Binance
`/api/v3/exchangeInfo`, Coinbase `/products` and OKX
`/api/v5/public/instruments` all return instrument definitions only. Volume
comes from the ticker endpoints, one request per candidate, so a ticker listed
on three venues costs three extra calls with the user waiting on the add-coin
screen and every call queued behind `RequestPacer`.

Two ways to avoid paying that per candidate, both worth weighing before
implementing: Binance's `/ticker/24hr` and OKX's `/market/tickers` each return
the *whole* venue in one response, so a single request per venue would serve
every candidate at once — but those are large payloads to fetch for one row.
Coinbase has no such bulk endpoint on the exchange API and would still be
per-product.

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
