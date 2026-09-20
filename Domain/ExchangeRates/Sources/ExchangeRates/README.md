# ExchangeRates

A standalone Swift package for Decimal currency conversion, current fiat/crypto quotes, offline snapshots, and historical series. Requires Swift 6.2+, iOS 16+ or macOS 14+. No third-party dependencies, app identifiers, UI frameworks, or credentials.

Add this repository as a Swift package dependency and link the `ExchangeRates` product. Other repositories can reference this repository URL directly.

```swift
import ExchangeRates

let cache = RateCache(directory: cacheDirectory)
let result = await RateService().refresh(previous: cache.load())
try cache.save(result.snapshot)
let dollars = result.snapshot.convert(100, from: "EUR", to: "USD")

let history = HistoryService(directory: cacheDirectory)
let month = await history.load(base: "EUR", quote: "USD", range: .month)
```

Quotes are currency units per EUR. Conversion returns an unrounded `Decimal?`; callers choose display precision. Missing/invalid rates return nil. Snapshots preserve publication dates and intraday timestamps. Refresh warnings, history issues, and provenance are typed so hosts can choose their own presentation. `RateSource` contains a `RateProviderID`, `RateObservation`, and optional time zone; switch on these values to select your own strings or localization. Custom providers use `.custom("Provider name")`. Older string-based cache provenance decodes automatically.

The default service combines Frankfurter with ECB fallback, Fawaz daily rates, and Coinbase crypto overlays. Supply `RateProvider` implementations to `RateService`, or an `HTTPClient` to individual providers and history, to customize data sources and test without network access. The package does not schedule background work.

Crypto history uses USD-denominated completed candles. Use `.week`, `.month`, `.quarter`, `.year`, or `.all`; all-history requests may take longer and support task cancellation. Failed requests retain saved history.

Run `swift test` from the repository root. Public API reference is available through Xcode’s Build Documentation action and the included DocC catalog.

The `ExchangeRatesDynamic` product exposes the same module with explicit dynamic linking for apps that share it between frameworks. Choose one product per executable; the default `ExchangeRates` product lets SwiftPM choose linkage.
