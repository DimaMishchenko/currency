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
      return RateService(policy: CurrencyRateConfiguration.policy, client: FixedRateClient())
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
      let policy = CurrencyRateConfiguration.policy
      let rates = RateStore(directory: directory, policy: policy)
      let daily = FixedRateClient.quotes(now: now)
      var effective = daily
      effective["BTC"] = FixedRateClient.coinbaseQuote(now: now)
      try FileCoordination.write(at: directory.appendingPathComponent("rates.json")) {
        try RateCache(directory: directory)
          .save(
            RateSnapshot(
              quotes: effective, fetchedAt: now, dailyQuotes: daily, dailyFetchedAt: now,
              checkedAt: now, supplementalFetchedAt: now, supplementalQuotes: daily))
      }
      for mode in [RateProviderPolicy.daily, .coinbaseEnhanced] {
        try seedHistory(
          base: "EUR", quote: "USD", values: [1.8, 2], mode: mode,
          directory: directory, now: now)
        try seedHistory(
          base: "EUR", quote: "XAU", values: [0.009, 0.01], mode: mode,
          directory: directory, now: now)
        try seedHistory(
          base: "BTC", quote: "USD", values: [90_000, 100_000], mode: mode,
          directory: directory, now: now)
      }
      let hourly = HistorySeries(
        points: [
          HistoryPoint(date: now.addingTimeInterval(-2 * 3600), value: 45_000),
          HistoryPoint(date: now.addingTimeInterval(-3600), value: 50_000)
        ], source: .init(provider: .coinbase, observation: .hourlyClose, timeZone: .gmt),
        fetchedAt: now)
      try writeHistory(
        hourly, filename: "history-coinbaseEnhanced-coinbase-BTC-USD-1.json",
        directory: directory)
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
      case .readyConverter, .readyMetals, .readyMetalSource, .readyCrypto:
        let input = try conversion.updateInput {
          $0 = ConverterState()
          $0.setDestinations(state == .readyMetals ? ["USD", "XAU"] : ["USD"])
          if state == .readyMetalSource { $0.changeSource("XAU") }
          if state == .readyCrypto {
            $0.changeSource("USD")
            $0.setDestinations(["BTC"])
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
        seededRates.quotes["BTC"]?.value == (policy == .coinbaseEnhanced ? 0.00004 : 0.00002),
        seededRates.quotes["BTC"]?.source.provider
          == (policy == .coinbaseEnhanced ? .coinbase : .fawaz),
        discoveryStore.load() == discovery
      else { throw StartupError.seedVerificationFailed }
    }

    private static func seedHistory(
      base: String, quote: String, values: [Double], mode: RateProviderPolicy,
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
            observation: range == .all ? .monthlyReference : .dailyReference, timeZone: .gmt),
          fetchedAt: now)
        let interval =
          range == .yearToDate
          ? "\(range.rawValue)-\(calendar.component(.year, from: now))" : "\(range.rawValue)"
        try writeHistory(
          series,
          filename: "history-\(mode.rawValue)-fawaz-\(base)-\(quote)-\(interval).json",
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
      if url.host == "api.coinbase.com", url.path == "/v2/exchange-rates",
        CurrencyRateConfiguration.coinbaseEnabled
      {
        var values = Dictionary(
          uniqueKeysWithValues: CurrencyCatalog.crypto.map { ($0, "0.00004") })
        values["EUR"] = "1"
        return try JSONSerialization.data(withJSONObject: [
          "data": ["currency": "EUR", "rates": values]
        ])
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
        "EUR": 1, "USD": 2, "CHF": 0.5, "CZK": 25, "XAU": 0.01, "BTC": 0.00002
      ]
      return values.mapValues {
        ExchangeRate(
          $0, published: day(now),
          source: .init(provider: .fawaz, observation: .dailyRate), cachedAt: now)
      }
    }

    static func coinbaseQuote(now: Date) -> ExchangeRate {
      ExchangeRate(
        0.00004, published: day(now),
        source: .init(provider: .coinbase, observation: .exchangeRate), retrievedAt: now)
    }
  }
#endif
