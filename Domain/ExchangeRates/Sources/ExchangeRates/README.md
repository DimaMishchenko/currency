# ExchangeRates

Currency's rate core for Decimal currency conversion, current fiat/crypto quotes, offline snapshots, and historical series. No third-party dependencies, app identifiers, UI frameworks, or credentials.

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

Crypto history uses completed Coinbase USD candles. Crypto/crypto pairs divide candles on matching timestamps, including hourly observations for `.day`. Crypto/fiat and crypto/metal pairs combine daily closes with same-date Frankfurter USD/quote references; they have no hourly range. Other pairs use Frankfurter history directly. `.all` samples the joined daily series by month. Missing dates are omitted, and failed requests retain saved history for the requested pair.

Run `ExchangeRatesPackageTests` in the `CurrencyTests` scheme. API reference is available through Xcode’s Build Documentation action and the included DocC catalog.
