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
    #expect(HistoryWidgetRange.allCases.map(\.range) == HistoryRange.allCases)
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
    settings.comparison = HistoryCurrency("EUR")
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
