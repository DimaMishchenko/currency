#if DEBUG && targetEnvironment(simulator)
  import Conversion
  import CoordinatedFiles
  import CurrencyApplication
  import ExchangeRates
  import Foundation
  import Home
  import Onboarding
  import TipKit
  import WidgetKit

  @MainActor
  enum CurrencyE2EStartup {
    enum InitialState: String {
      case freshOnboarding = "fresh-onboarding"
      case readyConverter = "ready-converter"
      case readyMetals = "ready-metals"
      case readyMetalSource = "ready-metal-source"
      case readyCrypto = "ready-crypto"
      case readyHistorySync = "ready-history-sync"
    }

    enum StartupError: Error, Equatable {
      case invalidArguments
      case seedVerificationFailed
    }

    static func prepare(
      arguments: [String] = ProcessInfo.processInfo.arguments,
      directory: () -> URL = { AppGroup.directory }, defaults: UserDefaults = .standard,
      resetTips: () throws -> Void = { try Tips.resetDatastore() }, now: Date = .now
    ) throws -> RateService? {
      let configuration = try parse(arguments)
      guard configuration.enabled else { return nil }
      if let state = configuration.state {
        try resetTips()
        try seed(state, directory: directory(), defaults: defaults, now: now)
        WidgetCenter.shared.reloadAllTimelines()
      }
      return RateService(client: FixedRateClient())
    }

    private static func parse(
      _ arguments: [String]
    ) throws -> (
      enabled: Bool, state: InitialState?
    ) {
      var enabled = false
      var state: InitialState?
      var index = 0
      while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-CurrencyE2E":
          guard !enabled else { throw StartupError.invalidArguments }
          enabled = true
        case "-CurrencyE2EState":
          guard state == nil, index + 1 < arguments.count,
            let value = InitialState(rawValue: arguments[index + 1])
          else { throw StartupError.invalidArguments }
          state = value
          index += 1
        default:
          guard !argument.hasPrefix("-CurrencyE2E") else {
            throw StartupError.invalidArguments
          }
        }
        index += 1
      }
      guard state == nil || enabled else { throw StartupError.invalidArguments }
      return (enabled, state)
    }

    private static func seed(
      _ state: InitialState, directory: URL, defaults: UserDefaults, now: Date
    ) throws {
      let rates = RateStore(directory: directory)
      let daily = FixedRateClient.quotes(now: now)
      var effective = daily
      let bitcoinPrice: Decimal = state == .readyHistorySync ? 52_500 : 50_000
      effective["BTC"] = FixedRateClient.coinMetricsQuote(now: now, priceUSD: bitcoinPrice)
      effective["ETH"] = FixedRateClient.coinMetricsQuote(now: now, priceUSD: 100)
      try FileCoordination.write(at: directory.appendingPathComponent("rates.json")) {
        try RateCache(directory: directory)
          .save(
            RateSnapshot(
              quotes: effective, fetchedAt: now, dailyQuotes: daily, dailyFetchedAt: now,
              checkedAt: now, supplementalFetchedAt: now, supplementalQuotes: daily))
      }

      try seedHistory(
        base: "EUR", quote: "USD", values: [1.8, 2],
        directory: directory, now: now)
      try seedHistory(
        base: "EUR", quote: "XAU", values: [0.009, 0.01],
        directory: directory, now: now)
      let end = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 300) * 300)
      for reference in ["USD", "EUR", "CZK", "CHF", "VND"] {
        guard let referenceRate = daily[reference], let usd = daily["USD"] else {
          throw StartupError.seedVerificationFailed
        }
        let factor = NSDecimalNumber(decimal: referenceRate.value / usd.value).doubleValue
        try seedHistory(
          base: "BTC", quote: reference, values: [45_000 * factor, 50_000 * factor],
          directory: directory, now: now)
        let conversion: RateConversion? =
          reference == "USD"
          ? nil
          : .init(
            provider: .fawaz, published: FixedRateClient.day(now),
            value: referenceRate.value / usd.value, base: "USD", quote: reference)
        let intraday = HistorySeries(
          points: (0...288)
            .map { index in
              HistoryPoint(
                date: end.addingTimeInterval(Double(index - 288) * 300),
                value: (45_000 + Double(index) * 5_000 / 288) * factor)
            },
          source: .init(
            provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt,
            conversion: conversion), fetchedAt: end)
        try writeHistory(
          intraday, filename: "history-v3-BTC-\(reference)-1.json", directory: directory)
      }
      try seedHistory(
        base: "ETH", quote: "BTC", values: [0.0018, 0.002], directory: directory, now: now)
      let cryptoPair = HistorySeries(
        points: (0...288)
          .map { index in
            HistoryPoint(
              date: end.addingTimeInterval(Double(index - 288) * 300),
              value: 0.0018 + Double(index) * 0.0002 / 288)
          }, source: .init(provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt),
        fetchedAt: end)
      try writeHistory(cryptoPair, filename: "history-v3-ETH-BTC-1.json", directory: directory)
      if state == .readyHistorySync {
        let end = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 3600) * 3600)
        let day = HistorySeries(
          points: (0...288)
            .map { index in
              HistoryPoint(
                date: end.addingTimeInterval(Double(index - 288) * 300),
                value: 50_000 + Double(index) * 2_500 / 288)
            },
          source: .init(provider: .coinMetrics, observation: .minuteReference, timeZone: .gmt),
          fetchedAt: end)
        let week = HistorySeries(
          points: [
            HistoryPoint(date: end.addingTimeInterval(-6 * 86_400), value: 40_000),
            HistoryPoint(date: end.addingTimeInterval(-86_400), value: 48_000)
          ],
          source: .init(provider: .fawaz, observation: .dailyReference, timeZone: .gmt),
          fetchedAt: end)
        try writeHistory(day, filename: "history-v3-BTC-USD-1.json", directory: directory)
        try writeHistory(week, filename: "history-v3-BTC-USD-7.json", directory: directory)
      }
      let files = [
        "input.json", "onboarding.json", "widget-location-refresh.json",
        "widget-location.json", "widget-location-status.json"
      ]
      for filename in files {
        do {
          try FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
        }
      }
      for key in ["appearance.theme", "appearance.accent", "homeDiscoveryProgress"] {
        defaults.removeObject(forKey: key)
      }
      let conversion = ConversionStore(directory: directory)
      let progress = OnboardingProgressStore(directory: directory)
      switch state {
      case .readyConverter, .readyMetals, .readyMetalSource, .readyCrypto, .readyHistorySync:
        let input = try conversion.updateInput {
          $0 = ConverterState()
          $0.setDestinations(state == .readyMetals ? ["USD", "XAU"] : ["USD"])
          if state == .readyMetalSource { $0.changeSource("XAU") }
          if state == .readyCrypto {
            $0.changeSource("USD")
            $0.setDestinations(["BTC"])
          }
          if state == .readyHistorySync {
            $0.changeSource("BTC")
            $0.setDestinations(["USD"])
          }
        }
        try progress.save(OnboardingProgress(draft: input, step: .ready, completed: true))
        guard conversion.input() == input, progress.load()?.completed == true,
          progress.load()?.step == .ready
        else { throw StartupError.seedVerificationFailed }
      case .freshOnboarding:
        guard conversion.input() == ConverterState(), progress.load() == nil,
          !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("input.json").path),
          !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("onboarding.json").path)
        else { throw StartupError.seedVerificationFailed }
      }
      var discovery = HomeDiscoveryProgress()
      discovery.visitedDetails = true
      discovery.openedWidgets = true
      discovery.showedHistoryTip = true
      discovery.showedWidgetsTip = true
      let discoveryStore = HomeDiscoveryStore(defaults: defaults)
      discoveryStore.save(discovery)
      let seededRates = rates.loadRates()
      guard seededRates.quotes["EUR"]?.value == 1, seededRates.quotes["USD"]?.value == 2,
        seededRates.quotes["CHF"]?.value == 0.5, seededRates.quotes["CZK"]?.value == 25,
        seededRates.quotes["BTC"]?.value == 2 / bitcoinPrice,
        seededRates.quotes["BTC"]?.source.provider
          == .coinMetrics,
        discoveryStore.load() == discovery
      else { throw StartupError.seedVerificationFailed }
    }

    private static func seedHistory(
      base: String, quote: String, values: [Double],
      directory: URL, now: Date
    ) throws {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .gmt
      guard
        let yearStart = calendar.date(
          from: DateComponents(year: calendar.component(.year, from: now), month: 1, day: 1))
      else { throw StartupError.seedVerificationFailed }
      for range in HistoryRange.allCases where range != .day {
        let first =
          range == .yearToDate
          ? yearStart
          : now.addingTimeInterval(-Double(range == .all ? 60 : max(2, range.rawValue - 1)) * 86400)
        let series = HistorySeries(
          points: [
            HistoryPoint(date: first, value: values[0]),
            HistoryPoint(date: now.addingTimeInterval(-86400), value: values[1])
          ],
          source: .init(
            provider: .fawaz,
            observation: range == .all ? .monthlyReference : .dailyReference, timeZone: .gmt,
            contributingProviders: range == .all ? [.coinMetrics, .frankfurter] : nil),
          fetchedAt: now)
        let interval =
          range == .yearToDate
          ? "\(range.rawValue)-\(calendar.component(.year, from: now))" : "\(range.rawValue)"
        try writeHistory(
          series,
          filename: "history-v3-\(base)-\(quote)-\(interval).json",
          directory: directory)
      }
    }

    private static func writeHistory(
      _ history: HistorySeries, filename: String, directory: URL
    ) throws {
      let file = directory.appendingPathComponent(filename)
      try FileCoordination.write(at: file) {
        try JSONEncoder().encode(history).write(to: file, options: .atomic)
      }
      let saved = try JSONDecoder().decode(HistorySeries.self, from: Data(contentsOf: file))
      guard saved.points == history.points, saved.source == history.source,
        saved.fetchedAt == history.fetchedAt
      else { throw StartupError.seedVerificationFailed }
    }

  }

  private struct FixedRateClient: HTTPClient {
    func get(_ url: URL) async throws -> Data {
      try Task.checkCancellation()
      if url.host == "community-api.coinmetrics.io",
        url.path == "/v4/timeseries/asset-metrics"
      {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let assets = items.first { $0.name == "assets" }?.value?.split(separator: ",") ?? []
        let end = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970 / 60) * 60)
        let rows = assets.map { asset in
          [
            "asset": String(asset), "time": end.ISO8601Format(),
            "ReferenceRateUSD": asset == "eth" ? "100" : "50000"
          ]
        }
        return try JSONSerialization.data(withJSONObject: ["data": rows])
      }
      guard ["cdn.jsdelivr.net", "latest.currency-api.pages.dev"].contains(url.host ?? ""),
        url.path.hasSuffix("/currencies/eur.min.json")
      else { throw RateError.unavailable }
      struct Payload: Encodable { let date: String; let eur: [String: Decimal] }
      return try JSONEncoder()
        .encode(
          Payload(
            date: Self.day(.now),
            eur: Dictionary(
              uniqueKeysWithValues: Self.quotes(now: .now)
                .map {
                  ($0.key.lowercased(), $0.value.value)
                })))
    }

    static func day(_ now: Date) -> String { String(now.ISO8601Format().prefix(10)) }

    static func quotes(now: Date) -> [String: ExchangeRate] {
      let values: [String: Decimal] = [
        "EUR": 1, "USD": 2, "CHF": 0.5, "CZK": 25, "XAU": 0.01, "BTC": 0.00002,
        "ETH": 0.01, "VND": 50_000
      ]
      return values.mapValues {
        ExchangeRate(
          $0, published: day(now),
          source: .init(provider: .fawaz, observation: .dailyRate), cachedAt: now)
      }
    }

    static func coinMetricsQuote(now: Date, priceUSD: Decimal = 50_000) -> ExchangeRate {
      ExchangeRate(
        2 / priceUSD, published: day(now),
        source: .init(
          provider: .coinMetrics, observation: .minuteReference,
          conversion: RateConversion(
            provider: .fawaz, published: day(now), value: 2, base: "EUR", quote: "USD")),
        observedAt: now, retrievedAt: now)
    }
  }
#endif
