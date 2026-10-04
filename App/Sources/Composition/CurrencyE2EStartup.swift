#if DEBUG && targetEnvironment(simulator)
  import Conversion
  import CoordinatedFiles
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
      let provider = FixedRateProvider()
      return RateService(fiat: provider, daily: provider, crypto: nil)
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
      try FileCoordination.write(at: directory.appendingPathComponent("rates.json")) {
        try RateCache(directory: directory).save(
          RateSnapshot(quotes: FixedRateProvider.quotes(now: now), fetchedAt: now, checkedAt: now))
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
      case .readyConverter:
        let input = try conversion.updateInput {
          $0 = ConverterState()
          $0.setDestinations(["USD"])
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
        seededRates.checkedAt == now, discoveryStore.load() == discovery
      else { throw StartupError.seedVerificationFailed }
    }
  }

  private struct FixedRateProvider: RateProvider {
    func fetch() async throws -> [String: ExchangeRate] {
      try Task.checkCancellation()
      return Self.quotes(now: .now)
    }

    static func quotes(now: Date) -> [String: ExchangeRate] {
      let day = now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
      let values: [String: Decimal] = ["EUR": 1, "USD": 2, "CHF": 0.5, "CZK": 25]
      return
        values
        .mapValues { ExchangeRate($0, published: day, source: .init(provider: .ecb), cachedAt: now) }
    }
  }
#endif
