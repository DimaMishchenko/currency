# ``ExchangeRates``

Convert currencies, refresh fiat and crypto quotes, and load historical series with offline fallbacks.

## Overview

Rates are normalized as currency units per euro. ``RateSnapshot/convert(_:from:to:)`` uses Decimal arithmetic and leaves rounding to the host. Configure ``RateService`` with custom providers or use the supplied feeds. A ``RateCache`` persists snapshots; ``HistoryService`` manages its own series cache in a caller-provided directory.

The package does not know about UI, App Groups, widgets, or polling schedules. Hosts choose when to refresh and how to present ``RefreshWarning`` and ``HistoryIssue`` values.

## Topics

### Conversion and caching

- ``ExchangeRate``
- ``RateSnapshot``
- ``CurrencyCatalog``
- ``CurrencyCode``
- ``RateCache``

### Refreshing quotes

- ``RateService``
- ``RefreshResult``
- ``RefreshWarning``
- ``RateProvider``

### Provider context

- ``RateSource``
- ``RateProviderID``
- ``RateObservation``

### Configuring providers

- ``HTTPClient``
- ``NetworkClient``
- ``RateError``
- ``FrankfurterProvider``
- ``ECBProvider``
- ``FawazProvider``
- ``CoinbaseProvider``
- ``FallbackRateProvider``

### Historical series

- ``HistoryService``
- ``HistoryRange``
- ``HistoryPoint``
- ``HistorySeries``
- ``HistoryResult``
- ``HistoryIssue``
