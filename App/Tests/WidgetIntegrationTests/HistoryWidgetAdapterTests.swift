import Conversion
import ExchangeRates
import Foundation
import LocalCurrency
import Synchronization
import Testing
import WidgetKit
import Widgets

@Suite struct HistoryWidgetAdapterTests {
  private let now = Date(timeIntervalSince1970: 1_790_035_200)

  @Test func nativeDefaultsFollowAppAndOverridesAreIndependent() {
    var input = ConverterState()
    input.setDestinations(["CZK", "USD"])
    let settings = HistorySettings()
    #expect(settings.range == .month)
    #expect(settings.pair(input: input).base == input.source)
    #expect(settings.pair(input: input).quote == "CZK")
    input.setDestinations(["USD", "CZK"])
    #expect(settings.pair(input: input).quote == "USD")
    settings.comparison = HistoryCurrency("JPY")
    input.changeSource("GBP")
    #expect(settings.pair(input: input).base == "GBP")
    #expect(settings.pair(input: input).quote == "JPY")
    settings.base = HistoryCurrency("CHF")
    #expect(settings.pair(input: input).base == "CHF")
  }

  @Test func concreteDefaultsAndLegacySelectionsResolveToCurrencies() async throws {
    var input = ConverterState()
    input.changeSource("USD")
    input.setDestinations(["EUR", "CZK"])
    let saved = input
    let baseQuery = HistoryCurrencyQuery(defaultID: HistoryCurrency.appBase, readInput: { saved })
    let query = HistoryCurrencyQuery(defaultID: HistoryCurrency.appFirst, readInput: { saved })
    #expect(await baseQuery.defaultResult()?.id == "USD")
    #expect(await query.defaultResult()?.id == "EUR")
    let choices = try await query.suggestedEntities().items
    #expect(choices.allSatisfy { CurrencyCatalog.codes.contains($0.id) || $0.id == "@local" })
    #expect(Set(choices.map(\.id)).count == choices.count)
    let restored = try await query.entities(for: [
      HistoryCurrency.appBase, HistoryCurrency.appFirst, "CZK", "invalid"
    ])
    #expect(restored.map(\.id) == ["USD", "EUR", "CZK"])
    #expect(try await query.entities(matching: "Czech").items.contains { $0.id == "CZK" })
    #expect(try await query.entities(matching: "First in app").items.isEmpty)
    let settings = HistorySettings()
    settings.base = await baseQuery.defaultResult()
    settings.comparison = await query.defaultResult()
    input.changeSource("GBP")
    input.setDestinations(["JPY"])
    #expect(settings.pair(input: input).base == "USD")
    #expect(settings.pair(input: input).quote == "EUR")
    #expect(
      HistoryWidgetRange.allCases.map(\.range) == [.day, .week, .month, .quarter, .year, .all])
  }

  @Test func searchablePickersUseTheSameFullCatalogAndPreserveSavedPairs() async throws {
    var input = ConverterState()
    input.changeSource("USD")
    input.setDestinations(["EUR", "CZK"])
    let saved = input
    for defaultID in [HistoryCurrency.appBase, HistoryCurrency.appFirst] {
      let query = HistoryCurrencyQuery(defaultID: defaultID, readInput: { saved })
      let choices = try await query.suggestedEntities().items.map(\.id)
      #expect(choices.contains("EUR"))
      #expect(choices.contains("@local"))
      #expect(choices.contains("USD"))
      #expect(Set(choices) == Set(CurrencyCatalog.codes + ["@local"]))
      #expect(try await query.entities(matching: "Euro").items.contains { $0.id == "EUR" })
      #expect(try await query.entities(matching: "Local").items.map(\.id) == ["@local"])
      let restored = try await query.entities(for: ["EUR", "EUR", "@local"])
      #expect(restored.map(\.id) == ["EUR", "EUR", "@local"])
    }
  }

  @Test func chosenDollarPairSurvivesDifferentAppDefaultsAndRangeChanges() async throws {
    var input = ConverterState()
    input.changeSource("EUR")
    input.setDestinations(["GBP", "CZK"])
    let settings = HistorySettings()
    settings.base = HistoryCurrency("BTC")
    settings.comparison = HistoryCurrency("USD")
    for range in [HistoryWidgetRange.day, .week, .month] {
      settings.range = range
      #expect(settings.pair(input: input).base == "BTC")
      #expect(settings.pair(input: input).quote == "USD")
      #expect(settings.effectiveRange(for: settings.pair(input: input)) == range.range)
      #expect(settings.availableRanges(input: input) == HistoryWidgetRange.allCases)
    }
    input.changeSource("CHF")
    input.setDestinations(["JPY"])
    let saved = input
    for defaultID in [HistoryCurrency.appBase, HistoryCurrency.appFirst] {
      let query = HistoryCurrencyQuery(defaultID: defaultID, readInput: { saved })
      #expect(try await query.entities(for: ["BTC", "USD"]).map(\.id) == ["BTC", "USD"])
      #expect(try await query.entities(matching: "USD").items.contains { $0.id == "USD" })
    }
    #expect(
      HistorySettings.resolvePair(
        input: saved, base: HistoryCurrency("BTC"), comparison: HistoryCurrency("USD"))
        == settings.pair(input: saved))
    #expect(settings.pair(input: saved).quote == "USD")
  }

  @Test func fullRepresentationsIncludeCurrencyAndLocalImagesWhenRequested() async throws {
    var input = ConverterState()
    input.changeSource("USD")
    input.setDestinations(["EUR", "CZK"])
    let saved = input
    let query = HistoryCurrencyQuery(defaultID: HistoryCurrency.appBase, readInput: { saved })
    for code in ["USD", "EUR", "BTC", "XAU", "@local"] {
      #expect(HistoryCurrency(code).displayRepresentation.image != nil)
    }
    if #available(iOS 27.0, *) {
      let representations = try await query.displayRepresentations(for: [
        "USD", "EUR", "BTC", "@local", HistoryCurrency.appBase, HistoryCurrency.appFirst, "invalid"
      ])
      #expect(representations.count == 6)
      #expect(representations.values.allSatisfy { $0.image != nil })
      #expect(
        representations[HistoryCurrency.appBase] == HistoryCurrency("USD").displayRepresentation)
      #expect(
        representations[HistoryCurrency.appFirst] == HistoryCurrency("EUR").displayRepresentation)
      #expect(representations["invalid"] == nil)
    }
  }

  @Test func rangeChoicesFollowSupportedCryptoPairsAndKeepFiatChoices() async throws {
    var input = ConverterState()
    input.changeSource("BTC")
    input.setDestinations(["USD"])
    let saved = input
    let settings = HistorySettings()
    let fiatRanges: [HistoryWidgetRange] = [.week, .month, .quarter, .year, .all]
    #expect(settings.availableRanges(input: saved) == HistoryWidgetRange.allCases)
    #expect(
      try await HistoryRangeOptionsProvider(readInput: { saved }).results()
        == HistoryWidgetRange.allCases)

    settings.base = HistoryCurrency("USD")
    settings.comparison = HistoryCurrency("BTC")
    #expect(settings.availableRanges(input: saved) == HistoryWidgetRange.allCases)
    settings.comparison = HistoryCurrency("EUR")
    #expect(settings.availableRanges(input: saved) == fiatRanges)
    settings.base = HistoryCurrency("BTC")
    #expect(settings.availableRanges(input: saved) == HistoryWidgetRange.allCases)
    settings.comparison = HistoryCurrency("USD")
    #expect(settings.availableRanges(input: saved) == HistoryWidgetRange.allCases)
    settings.comparison = HistoryCurrency("ETH")
    #expect(settings.availableRanges(input: saved) == HistoryWidgetRange.allCases)

    input.changeSource("EUR")
    input.setDestinations(["CZK"])
    #expect(settings.availableRanges(input: input) == HistoryWidgetRange.allCases)
    settings.base = nil
    settings.comparison = nil
    #expect(settings.availableRanges(input: input) == fiatRanges)
    let fiatInput = input
    #expect(try await HistoryRangeOptionsProvider(readInput: { fiatInput }).results() == fiatRanges)
    settings.base = HistoryCurrency("BTC")
    settings.comparison = HistoryCurrency("@local")
    #expect(
      settings.availableRanges(input: input, localCurrency: "USD")
        == HistoryWidgetRange.allCases)
    #expect(settings.availableRanges(input: input, localCurrency: "CZK") == fiatRanges)
    #expect(settings.availableRanges(input: input) == fiatRanges)
  }

  @Test func sharedPickerIncludesLocalAndResolvesItForHistory() async throws {
    let query = HistoryCurrencyQuery(
      defaultID: HistoryCurrency.appFirst, readInput: { ConverterState() })
    let choices = try await query.suggestedEntities().items.map(\.id)
    let shared = try await ComparisonCurrencyQuery(readInput: { ConverterState() })
      .suggestedEntities().items.map(\.id)
    #expect(choices == shared)
    #expect(try await query.entities(matching: "Local").items.contains { $0.id == "@local" })
    #expect(try await query.entities(for: ["@local"]).first?.id == "@local")
    let settings = HistorySettings()
    settings.comparison = HistoryCurrency("@local")
    #expect(settings.pair(input: ConverterState(), localCurrency: "CZK").quote == "CZK")
    #expect(!settings.pair(input: ConverterState()).isSupported)
    let baseQuery = HistoryCurrencyQuery(
      defaultID: HistoryCurrency.appBase, readInput: { ConverterState() })
    #expect(try await baseQuery.suggestedEntities().items.map(\.id) == shared)
    #expect(try await baseQuery.entities(matching: "Local").items.contains { $0.id == "@local" })
    #expect(try await baseQuery.entities(for: ["@local"]).first?.id == "@local")
    settings.base = HistoryCurrency("@local")
    settings.comparison = HistoryCurrency("EUR")
    #expect(settings.pair(input: ConverterState(), localCurrency: "CZK").base == "CZK")
    #expect(settings.pair(input: ConverterState(), localCurrency: "USD").base == "USD")
    #expect(!settings.pair(input: ConverterState()).isSupported)

  }

  @Test func localHistoryHonorsPermissionAndSupportedCache() async {
    let now = now
    for status: WidgetLocationStatus in [
      .available, .failed, .denied, .restricted, .removed, .notDetermined
    ] {
      for localCode: String? in [nil, "CZK", "BTC", "invalid"] {
        for localIsBase in [false, true] {
          let calls = Mutex<[[String]]>([])
          let provider = HistoryTimeline(
            dependencies: HistoryTimelineDependencies(
              input: { ConverterState() },
              load: { base, quote, _, _ in
                calls.withLock { $0.append([base, quote]) }
                return HistoryResult(series: nil, issue: .unavailable)
              }, now: { now },
              location: {
                localCode.map {
                  LocalCurrency.WidgetLocation(
                    country: "CZ", currency: $0, updatedAt: now.addingTimeInterval(-172800))
                }
              },
              locationStatus: { status }))
          let settings = HistorySettings()
          settings.base = HistoryCurrency(localIsBase ? "@local" : "EUR")
          settings.comparison = HistoryCurrency(localIsBase ? "EUR" : "@local")
          let entry = await provider.entry(settings)
          let eligible = status.allowsCache && localCode == "CZK"
          #expect(entry.snapshot.pair.needsLocalCurrency == !eligible)
          #expect(entry.locationStatus == status)
          #expect(
            calls.withLock { $0 }
              == (eligible ? [localIsBase ? ["CZK", "EUR"] : ["EUR", "CZK"]] : []))
        }
      }
    }
  }

  @Test func timelineLoadsConfiguredPairAndSchedulesDailyExpiry() async throws {
    let now = now
    let requested = Mutex<[String]>([])
    var input = ConverterState()
    input.setDestinations(["CZK", "USD"])
    let savedInput = input
    let provider = HistoryTimeline(
      dependencies: HistoryTimelineDependencies(
        input: { savedInput },
        load: { base, quote, range, date in
          requested.withLock { $0 = [base, quote] }
          #expect(range == .quarter)
          #expect(date == now)
          return HistoryResult(
            series: HistorySeries(
              points: [
                HistoryPoint(date: now.addingTimeInterval(-86_400), value: 24),
                HistoryPoint(date: now, value: 25)
              ], source: .init(provider: .frankfurter), fetchedAt: now.addingTimeInterval(-3600)),
            issue: nil)
        }, now: { now }))
    let settings = HistorySettings()
    settings.range = .quarter
    let timeline = await provider.loadTimeline(settings)
    #expect(requested.withLock { $0 } == ["EUR", "CZK"])
    #expect(timeline.entries.count == 1)
    #expect(timeline.entries.first?.snapshot.latest?.value == 25)
    #expect(timeline.policy == .after(now.addingTimeInterval(82_800)))
  }

  @Test func usdToBitcoinLoadsBitcoinDollarSeriesAndDisplaysReciprocal() async {
    let now = now
    let requested = Mutex<[String]>([])
    let provider = HistoryTimeline(
      dependencies: HistoryTimelineDependencies(
        input: { ConverterState() },
        load: { base, quote, _, _ in
          requested.withLock { $0 = [base, quote] }
          return HistoryResult(
            series: HistorySeries(
              points: [
                HistoryPoint(date: now.addingTimeInterval(-86_400), value: 50_000),
                HistoryPoint(date: now, value: 100_000)
              ], source: .init(provider: .coinbase), fetchedAt: now), issue: nil)
        }, now: { now }))
    let settings = HistorySettings()
    settings.base = HistoryCurrency("USD")
    settings.comparison = HistoryCurrency("BTC")
    settings.range = .day
    let entry = await provider.entry(settings)
    #expect(requested.withLock { $0 } == ["BTC", "USD"])
    #expect(entry.snapshot.range == .day)
    #expect(entry.snapshot.pair.base == "USD")
    #expect(entry.snapshot.pair.quote == "BTC")
    #expect(entry.snapshot.latest?.value == 0.00001)
    #expect(entry.snapshot.change == -0.5)
  }

  @Test(arguments: [HistoryWidgetRange.month, .day])
  func cryptoCrossPairLoadsSameHistoryInEitherWidgetDirection(range: HistoryWidgetRange) async {
    let now = now
    let requested = Mutex<[(String, String)]>([])
    let provider = HistoryTimeline(
      dependencies: HistoryTimelineDependencies(
        input: { ConverterState() },
        load: { base, quote, _, _ in
          requested.withLock { $0.append((base, quote)) }
          return HistoryResult(
            series: HistorySeries(
              points: [
                HistoryPoint(date: now.addingTimeInterval(-86_400), value: 100),
                HistoryPoint(date: now, value: 120)
              ], source: .init(provider: .custom("Coinbase + Frankfurter")), fetchedAt: now),
            issue: nil)
        }, now: { now }))
    let settings = HistorySettings()
    settings.range = range
    settings.base = HistoryCurrency("BTC")
    settings.comparison = HistoryCurrency("EUR")
    let direct = await provider.entry(settings)
    settings.base = HistoryCurrency("EUR")
    settings.comparison = HistoryCurrency("BTC")
    let inverse = await provider.entry(settings)
    #expect(requested.withLock { $0.map { [$0.0, $0.1] } } == [["BTC", "EUR"], ["BTC", "EUR"]])
    #expect(direct.snapshot.latest?.value == 120)
    #expect(abs((inverse.snapshot.latest?.value ?? 0) - 1.0 / 120) < 0.0000001)
    #expect(abs((inverse.snapshot.change ?? 0) + 1.0 / 6) < 0.0001)
  }

  @Test(arguments: [
    ("BTC", "USD"), ("USD", "BTC"), ("BTC", "EUR"), ("EUR", "BTC"), ("ETH", "GBP")
  ])
  func dayLoadsSupportedCryptoMarketsAndSchedulesHourlyWhileFiatRemainsDaily(
    base: String, comparison: String
  ) async {
    let now = now
    let requests = Mutex<[(String, String, HistoryRange)]>([])
    let provider = HistoryTimeline(
      dependencies: HistoryTimelineDependencies(
        input: { ConverterState() },
        load: { base, quote, range, _ in
          requests.withLock { $0.append((base, quote, range)) }
          return HistoryResult(series: nil, issue: .unavailable)
        }, now: { now }))
    let settings = HistorySettings()
    settings.base = HistoryCurrency(base)
    settings.comparison = HistoryCurrency(comparison)
    settings.range = .day
    let crypto = await provider.loadTimeline(settings)
    #expect(requests.withLock { $0 }.map(\.2) == [.day])
    #expect(crypto.entries.first?.snapshot.range == .day)
    #expect(crypto.policy == .after(now.addingTimeInterval(3600)))

    settings.base = HistoryCurrency("EUR")
    settings.comparison = HistoryCurrency("CZK")
    let fiat = await provider.loadTimeline(settings)
    #expect(requests.withLock { $0 }.map(\.2) == [.day, .month])
    #expect(fiat.entries.first?.snapshot.range == .month)
    #expect(fiat.policy == .after(now.addingTimeInterval(86_400)))

    settings.range = .week
    _ = await provider.entry(settings)
    #expect(requests.withLock { $0 }.map(\.2) == [.day, .month, .week])
  }

  @Test func unsupportedPairSkipsNetworkAndFailedLoadHasNoSampleData() async throws {
    let now = now
    let calls = Mutex(0)
    let provider = HistoryTimeline(
      dependencies: HistoryTimelineDependencies(
        input: { ConverterState() },
        load: { _, _, _, _ in
          calls.withLock { $0 += 1 }
          return HistoryResult(series: nil, issue: .unavailable)
        }, now: { now }))
    let settings = HistorySettings()
    settings.base = HistoryCurrency("BTC")
    settings.comparison = HistoryCurrency("BTC")
    var timeline = await provider.loadTimeline(settings)
    #expect(calls.withLock { $0 } == 0)
    #expect(timeline.entries.first?.snapshot.issue == .unsupportedPair)
    settings.base = HistoryCurrency("USD")
    timeline = await provider.loadTimeline(settings)
    #expect(calls.withLock { $0 } == 1)
    #expect(timeline.entries.first?.snapshot.series == nil)
    #expect(timeline.entries.first?.snapshot.latest == nil)
    #expect(timeline.policy == .after(now.addingTimeInterval(86_400)))
  }
}
