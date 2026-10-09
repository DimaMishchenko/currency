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

Quotes are currency units per EUR. Conversion returns an unrounded `Decimal?`; callers choose display precision. Missing/invalid rates return nil. Snapshots preserve publication dates and intraday timestamps. Refresh warnings, history issues, and provenance are typed so hosts can choose their own presentation. `RateSource` contains a `RateProviderID`, `RateObservation`, optional time zone, and optional `latestObservation` for a mixed historical endpoint; switch on these values to select your own strings or localization. Custom providers use `.custom("Provider name")`. Older string-based cache provenance decodes automatically.

`RateService` and `HistoryService` default to `RateProviderPolicy.daily`: Fawaz supplies current daily rates and daily history for every supported asset. Hosts can explicitly select `.coinbaseEnhanced` to add current Coinbase crypto overlays and supported 24-hour charts. Pass the same policy to `RateService`, `RateStore`, and `HistoryService`. `RateStore` with an explicit policy filters all persisted rate dictionaries before reads and merges so disabled providers cannot return through old snapshots. Its default nil policy preserves arbitrary injected providers for reusable consumers. Its refresh cadence is six hours with `.daily`, and thirty minutes with `.coinbaseEnhanced` or no policy. Missing live crypto rates revert to preserved Fawaz quotes with their original provenance. Explicitly injected `RateProvider` implementations remain available for tests and custom consumers. The package does not schedule background work.

History ranges longer than one day use dated Fawaz EUR snapshots and divide the quote rate by the base rate. The dated archive begins March 2, 2024; `.all` samples each month end and the current partial month. These are daily or monthly reference observations, not market closing prices. Missing assets and dates absent from both CDN endpoints are omitted. Other request failures return only a compatible complete saved chart. Immutable dated payloads are shared across pairs; chart caches are separated by policy and provider and reject incompatible provenance.

With Coinbase enabled, `history.supportsIntraday(base:quote:)` exposes the configured hourly capability. `.day` uses completed hourly candles from direct USD, EUR, or supported GBP markets; crypto/crypto pairs divide matching USD candles, using EUR when either USD market is absent. USDC has no direct USD hourly route. Hourly caches expire at UTC hour boundaries. Longer ranges remain Fawaz daily history even when Coinbase is enabled.

The [Fawaz endpoint documentation](https://github.com/fawazahmed0/exchange-api#readme) defines dated CDN URLs and the Cloudflare fallback. Daily archive requests run with at most three concurrent transfers.

The EUR and GBP market policy follows the [Coinbase product catalog](https://api.exchange.coinbase.com/products), verified on September 30, 2026. GBP excludes AVAX, ICP, XLM, and XRP from the app's crypto catalog. [Coinbase candles](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-candles) provide completed hourly observations without applying a daily FX rate to intraday prices.

Run `ExchangeRatesPackageTests` in the `CurrencyTests` scheme. API reference is available through Xcode’s Build Documentation action and the included DocC catalog.
