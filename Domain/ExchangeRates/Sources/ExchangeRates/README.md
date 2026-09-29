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

Crypto history uses completed Coinbase candles. `HistoryService.supportsIntraday(base:quote:)` defines the hourly routes used by the widget and details chart. `.day` uses direct USD, EUR, or supported GBP markets; crypto/crypto pairs divide matching USD candles, using matching EUR candles when either USD market is absent. USDC has no direct USD hourly route. Longer crypto/fiat and crypto/metal ranges combine daily USD closes with same-date Frankfurter USD/quote references. Other pairs use Frankfurter history directly. `.all` samples the joined daily series by month. Missing dates are omitted, and failed requests retain saved history for the requested pair.

The EUR and GBP market policy follows the [Coinbase product catalog](https://api.exchange.coinbase.com/products), verified on September 30, 2026. GBP excludes AVAX, ICP, XLM, and XRP from the app's crypto catalog. [Coinbase candles](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-candles) provide completed hourly observations without applying a daily FX rate to intraday prices.

Run `ExchangeRatesPackageTests` in the `CurrencyTests` scheme. API reference is available through Xcode’s Build Documentation action and the included DocC catalog.
