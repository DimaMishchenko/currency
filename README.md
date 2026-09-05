# Currency

A minimal one-to-many SwiftUI converter for iOS 26: one amount, a personal list of currencies, flag emoji, restrained Liquid Glass controls, Decimal arithmetic, and offline rates. See [the design brief](Documentation/Design.md).

## Run

Generate the workspace without opening Xcode:

```sh
tuist generate --no-open
```

Then open `Currency.xcworkspace`, select the Currency scheme and an iOS 26 simulator, and Run. For a physical device, select your signing team for both targets and register the `group.com.dimasike.currency` App Group. If changing identifiers, update `Project.swift` and `Modules/CurrencySupport/Sources/CurrencyStore.swift` together. Regenerate after changing a Tuist manifest or the dependency graph.

The standalone [`ExchangeRates`](Sources/ExchangeRates/README.md) package has no dependencies beyond Apple frameworks. Tuist consumes it from the repository root.

```sh
swift test
```

Run the `CurrencySupport` scheme’s tests in Xcode on an iOS 26 simulator for converter state and shared storage.

## Localization

English source catalogs use Xcode-generated typed accessors throughout the app and widgets. See [localization](Documentation/Localization.md) for adding languages and testing resource integration. The [independent review](Documentation/IndependentReview.md) records two remaining P2 storage recommendations.

## Provider decision (verified September 5, 2026)

The revised requirement permits reasonable throttling, with no subscription or authentication:

- **Frankfurter v2:** primary fiat source and fiat history. The [official FAQ](https://frankfurter.dev/) specifies no daily/monthly quotas, no API key, and anti-abuse throttling. The broader current-currency catalog is bundled for offline selection; unavailable currencies are labeled in the picker.
- **Coinbase:** one unauthenticated [EUR-based exchange-rates request](https://docs.cdp.coinbase.com/coinbase-app/track-apis/exchange-rates) supplies the entire crypto catalog per refresh. Missing or invalid individual rates use the daily fallback. The separate Exchange API supplies historical USD candles, with starts paced at 150ms and at most three pages in flight per chart. No authenticated endpoints are used.
- **ECB XML:** direct fiat fallback when Frankfurter fails. [ECB publication schedule](https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html): working days around 16:00 CET. ECB coverage is smaller; other currencies retain saved daily rates or Fawaz data.
- **Fawaz:** [project documentation](https://github.com/fawazahmed0/exchange-api) explicitly advertises free access without rate limits and daily updates. Used for crypto and fiat fallback. jsDelivr is attempted first, Cloudflare Pages second, including fallback after invalid payloads.

No provider included requires credentials or a subscription. Crypto is periodically checked, not streamed live. The batch endpoint provides no market timestamp: `retrievedAt` records receipt time, `observedAt` remains absent, and the details screen explicitly labels retrieval time. Upstream quote age cannot be verified; the previous ticker trade-age check does not apply.

## Architecture

The app composes two independent feature modules. All app-specific modules are Tuist targets; reusable rate logic lives in its own Swift package.

| Module | Responsibility | Entry point |
| --- | --- | --- |
| [ExchangeRates](Sources/ExchangeRates/README.md) | Conversion, providers, refresh, history, offline rates | `RateSnapshot`, `RateService`, `HistoryService`, `RateCache` |
| [CurrencySupport](Modules/CurrencySupport/README.md) | Shared converter state, formatting, App Group integration | `ConverterState`, `CurrencyStore`, `CurrencyDisplay` |
| [ConverterFeature](Modules/ConverterFeature/README.md) | Amount entry, currency list, refresh, widget guidance | `ConverterScreen` |
| [RateDetailsFeature](Modules/RateDetailsFeature/README.md) | Rate provenance and historical charts | `RateDetailsScreen` |
| [CurrencyWidgets](Widgets/README.md) | Home and Lock Screen widgets | Widget extension |
| [App](App/README.md) | Service composition and feature navigation | App executable |

Features depend on `CurrencySupport` and `ExchangeRates`, never on each other. The app supplies the converter’s details destination. Widget intents and feature implementation types remain internal. Public declarations have DocC comments; package decoder helpers remain internal and are tested with `@testable` imports. See [the architecture review](Documentation/Architecture.md) for decisions and verification commands.

Frankfurter (with sequential ECB fallback) and Fawaz fetch concurrently. The primary fiat chain wins daily publication-date ties; newer saved daily data is preserved. Daily quotes are cached separately from Coinbase overlays. If Coinbase fails or lacks a pair, that currency immediately reverts to its daily quote, including while offline. Every quote retains its source, publication date and optional trade or retrieval timestamp. Fiat/crypto conversions may combine daily fiat with intraday crypto; details disclose both sources.

The bundled picker includes 22 cryptocurrencies. In addition to BTC, ETH, SOL, DOGE, LTC, USDC, and USDT, it supports XRP, ADA, AVAX, LINK, DOT, BCH, XLM, ATOM, UNI, ETC, FIL, AAVE, ALGO, SHIB, and ICP. New entries have Fawaz daily quotes and Coinbase batch rates / USD history markets; provider availability can change. The catalog is curated in `CurrencyCode`, with searchable asset names in `CurrencyDisplay`.

Automatic checks run on activation and while the app is active with a persisted 30-minute attempt interval. Daily feeds are reused for six hours; manual refresh bypasses their freshness check. Widget timelines request 30 minutes, but iOS decides actual execution. Recent widget typing skips network refreshes; app typing only performs local conversion. Widget reload requests from app typing are debounced. There is no background polling daemon. Rates and input use separate atomic files in an App Group; widget keypad mutations use file coordination.

History uses Frankfurter time series for fiat and Coinbase completed daily USD candles for crypto, with 1W/1M/3M/1Y/Max ranges. One year uses a calendar-year interval. Max requests Frankfurter coverage from 1948 with monthly grouping, and scans Coinbase's available history from 2009 in paced, concurrent 299-day windows (including empty windows so gaps do not truncate history). Coinbase Max keeps the last available daily close per month; other crypto ranges retain daily closes. The actual returned date span is shown. Crypto history is explicitly USD-denominated, independent of the converter’s base. No current FX quote is applied to historical crypto prices. Each pair/range is cached atomically for six hours (24 hours for Max) and remains available offline. Failed pagination never saves a partial series as complete; existing cached charts remain available. Unsupported Coinbase pairs show an unavailable state; history failure does not affect conversion. Coinbase historical requests stay under the 300-candle maximum. Charts are loaded on demand only, and changing ranges cancels outstanding page requests.

The shared ephemeral HTTP session pools connections and coalesces identical in-flight GETs within each process. Each caller can cancel independently; the last cancellation stops the underlying transfer. Requests bypass URLCache because persisted snapshots and chart caches own freshness. Defaults are a 12-second inactivity timeout (30 seconds for history) and a 45-second total transfer limit; failures are not automatically retried. App and widget processes have separate sessions and can still overlap across processes. Crypto history windows align to UTC midnight, making completed-day requests reusable and giving each boundary candle one owner.

## Widgets and platform limits

- Small: source amount and first destination.
- Medium: source amount and first three destinations.
- Large: up to eight destinations in adaptive columns plus a numeric keypad with 0–9, decimal, double-zero, delete, clear, swap, and open-app control.
- Currency board: up to six in medium and twelve in large.
- Quick rate: inline and rectangular Lock Screen variations.

Add, remove, and reorder currencies in the app; widgets share that ordered list and amount. Tap a result in the app to make it the source, preserving the displayed converted amount (rounded to that currency’s displayed precision). Existing saved input migrates automatically. Widget buttons use App Intents and run without opening the app. [Apple’s interaction model](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) supports buttons and toggles, not a system keyboard/TextField. Each input requires system processing and a new widget timeline; fast calculator-style response cannot be guaranteed. iOS also controls scheduled refresh timing. The in-app keypad is immediate.

## Verification

Core tests cover Decimal cross-conversion, missing rates, XML/JSON parsing, malformed data, alternate CDN, provider failure, preservation of newer data, cache corruption/round-trip, and keypad bounds. No live network dependency in unit tests.

Before shipping, validate widget rapid taps on a physical device, Dynamic Type, VoiceOver, dark/tinted home screens, and App Group provisioning. App Store signing and distribution are not configured.

## Visual gallery

Open `Documentation/Gallery.html` for the three actual WidgetKit sizes and the keypad, currency picker, management, and rate-details screens. Widget screenshots were captured using simulator ad-hoc signing so App Group sharing works. For simulator integration builds, keep code signing enabled (use `CODE_SIGN_IDENTITY=-`); `CODE_SIGNING_ALLOWED=NO` is sufficient for compile checks but strips the entitlements needed for shared storage.

### Crypto icons

The 21 cryptocurrency badges other than DOGE use the colored background variant of [Web3 Icons](https://github.com/0xa3k5/web3icons), © 2024 0xa3k5, under the [MIT license](Modules/CurrencySupport/Resources/Web3Icons-LICENSE.txt). DOGE uses the simpler gold-circle symbol from [Cryptocurrency Icons](https://github.com/spothq/cryptocurrency-icons), under [CC0 1.0](Modules/CurrencySupport/Resources/CryptocurrencyIcons-LICENSE.txt). All 22 SVG assets are bundled locally for offline use in the app and widgets, alongside native fiat flag emoji. Attribution is also available in the info screen’s Sources section. See [asset provenance](Documentation/Web3Icons.md) for the pinned upstream revision.

Metal badges (Au, Ag, Pt, Pd) are original SwiftUI artwork with distinct muted colors, a static diagonal satin highlight, and a subtle rim. They replace medal and white-circle emoji throughout the app and widgets.
