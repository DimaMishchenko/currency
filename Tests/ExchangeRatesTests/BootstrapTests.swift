import Foundation
import Testing

@testable import ExchangeRates

private struct BootstrapProvider: RateProvider {
  var quotes: [String: ExchangeRate] = [:]
  var delay: Duration = .zero
  var error: URLError.Code?

  func fetch() async throws -> [String: ExchangeRate] {
    try await Task.sleep(for: delay)
    if let error { throw URLError(error) }
    return quotes
  }
}

private actor PendingBootstrapProvider: RateProvider {
  private let quotes: [String: ExchangeRate]?
  private var continuation: CheckedContinuation<Void, Never>?
  private var released = false

  init(quotes: [String: ExchangeRate]?) { self.quotes = quotes }

  func fetch() async throws -> [String: ExchangeRate] {
    if !released { await withCheckedContinuation { continuation = $0 } }
    guard let quotes else { throw URLError(.badServerResponse) }
    return quotes
  }

  func finish() {
    released = true
    continuation?.resume()
    continuation = nil
  }
}

private func bootstrapQuotes(_ usd: Decimal = 2) -> [String: ExchangeRate] {
  [
    "EUR": ExchangeRate(1, published: "2026-09-10", source: .init(provider: .ecb)),
    "USD": ExchangeRate(usd, published: "2026-09-10", source: .init(provider: .ecb))
  ]
}

@Suite struct BootstrapTests {
  @Test func fiatDeliveredWithoutWaitingForSlowCrypto() async {
    let service = RateService(
      fiat: BootstrapProvider(quotes: bootstrapQuotes()),
      daily: BootstrapProvider(delay: .seconds(30)),
      crypto: BootstrapProvider(delay: .seconds(30)))
    let began = ContinuousClock.now
    let stream = await service.bootstrap(previous: RateSnapshot())
    for await update in stream {
      #expect(began.duration(to: .now) < .seconds(2))
      #expect(update.snapshot.hasUsablePair(from: "EUR", to: "USD"))
      #expect(!update.isFinal)
      break
    }
  }

  @Test func completionOrderDoesNotChangePrimaryPrecedence() async {
    let service = RateService(
      fiat: BootstrapProvider(quotes: bootstrapQuotes(3)),
      daily: BootstrapProvider(quotes: bootstrapQuotes(2), delay: .milliseconds(20)), crypto: nil)
    var final: BootstrapUpdate?
    for await update in await service.bootstrap(previous: RateSnapshot()) { final = update }
    #expect(final?.isFinal == true)
    #expect(final?.snapshot.quotes["USD"]?.value == 3)
  }

  @Test func offlineRequiresActualConnectivityErrorsFromEveryProvider() async {
    let offline = BootstrapProvider(error: .notConnectedToInternet)
    var final: BootstrapUpdate?
    for await update in await RateService(fiat: offline, daily: offline, crypto: nil)
      .bootstrap(previous: RateSnapshot())
    { final = update }
    #expect(final?.failure == .offline)
    for await update in await RateService(
      fiat: offline, daily: BootstrapProvider(error: .badServerResponse), crypto: nil
    )
    .bootstrap(previous: RateSnapshot()) { final = update }
    #expect(final?.failure == .unavailable)
  }

  @Test func invalidRefreshCannotReplaceSavedDailyQuote() async {
    let saved = RateSnapshot(quotes: bootstrapQuotes(), fetchedAt: .now)
    var invalid = bootstrapQuotes(.nan)
    invalid["EUR"] = ExchangeRate(0, published: "2026-09-10", source: .init(provider: .ecb))
    var final: BootstrapUpdate?
    for await update in await RateService(
      fiat: BootstrapProvider(quotes: invalid), daily: BootstrapProvider(), crypto: nil
    )
    .bootstrap(previous: saved) { final = update }
    #expect(final?.snapshot.quotes["USD"]?.value == 2)
    #expect(final?.snapshot.fetchedAt == saved.fetchedAt)
  }

  @Test func pendingCryptoKeepsUsableCachedPairUntilSuccess() async {
    let cachedQuote = ExchangeRate(
      5, published: "2026-09-10", source: .init(provider: .coinbase), observedAt: .now)
    let freshQuote = ExchangeRate(
      6, published: "2026-09-10", source: .init(provider: .coinbase), observedAt: .now)
    var live = bootstrapQuotes()
    live["BTC"] = cachedQuote
    let saved = RateSnapshot(quotes: live, fetchedAt: .now, dailyQuotes: bootstrapQuotes())
    let crypto = PendingBootstrapProvider(quotes: ["BTC": freshQuote])
    let service = RateService(
      fiat: BootstrapProvider(quotes: bootstrapQuotes()), daily: BootstrapProvider(),
      crypto: crypto)
    var updates = await service.bootstrap(previous: saved).makeAsyncIterator()
    // Both daily providers finish while crypto remains explicitly suspended.
    for _ in 0..<2 {
      let update = await updates.next()
      #expect(update?.isFinal == false)
      #expect(update?.snapshot.quotes["BTC"] == cachedQuote)
      #expect(update?.snapshot.hasUsablePair(from: "BTC", to: "EUR") == true)
    }
    await crypto.finish()
    let final = await updates.next()
    #expect(final?.isFinal == true)
    #expect(final?.snapshot.quotes["BTC"] == freshQuote)
  }

  @Test(arguments: [false, true])
  func pendingCryptoFallsBackOnlyAfterFailure(hasDailyFallback: Bool) async {
    var live = bootstrapQuotes()
    live["BTC"] = ExchangeRate(
      5, published: "2026-09-10", source: .init(provider: .coinbase), observedAt: .now)
    var daily = bootstrapQuotes()
    if hasDailyFallback {
      daily["BTC"] = ExchangeRate(4, published: "2026-09-10", source: .init(provider: .fawaz))
    }
    let saved = RateSnapshot(quotes: live, fetchedAt: .now, dailyQuotes: daily)
    let crypto = PendingBootstrapProvider(quotes: nil)
    let service = RateService(
      fiat: BootstrapProvider(), daily: BootstrapProvider(), crypto: crypto)
    var updates = await service.bootstrap(previous: saved).makeAsyncIterator()
    for _ in 0..<2 {
      let update = await updates.next()
      #expect(update?.isFinal == false)
      #expect(update?.snapshot.quotes["BTC"] == live["BTC"])
      #expect(update?.snapshot.fetchedAt == saved.fetchedAt)
    }
    await crypto.finish()
    let final = await updates.next()
    #expect(final?.isFinal == true)
    #expect(final?.snapshot.quotes["BTC"] == daily["BTC"])
    #expect(final?.snapshot.quotes["BTC"]?.observedAt == nil)
  }

  @Test func readinessRejectsIdentityUnsupportedInvalidTimeAndOverflow() {
    let now = Date.now
    let pair = RateSnapshot(quotes: bootstrapQuotes(), fetchedAt: now)
    #expect(pair.hasUsablePair(from: "EUR", to: "USD"))
    #expect(!pair.hasUsablePair(from: "EUR", to: "EUR"))
    #expect(!pair.hasUsablePair(from: "EUR", to: "UNKNOWN"))
    #expect(!RateSnapshot(quotes: bootstrapQuotes()).hasUsablePair(from: "EUR", to: "USD"))
    #expect(
      !RateSnapshot(quotes: bootstrapQuotes(), fetchedAt: now.addingTimeInterval(3600))
        .hasUsablePair(from: "EUR", to: "USD", now: now))
    #expect(
      RateSnapshot(quotes: bootstrapQuotes(), fetchedAt: Date(timeIntervalSince1970: 10))
        .hasUsablePair(from: "EUR", to: "USD", now: now))
    var overflow = bootstrapQuotes()
    overflow["USD"] = ExchangeRate(
      Decimal.greatestFiniteMagnitude, published: "2026-09-10", source: .init(provider: .ecb))
    #expect(
      !RateSnapshot(quotes: overflow, fetchedAt: now)
        .hasUsablePair(from: "EUR", to: "USD"))
  }
}
