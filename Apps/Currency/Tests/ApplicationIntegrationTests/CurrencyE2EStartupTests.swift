#if DEBUG && targetEnvironment(simulator)
  import AppearancePreferences
  import Conversion
  import ExchangeRates
  import Foundation
  import Home
  import Onboarding
  import Testing

  @MainActor
  struct CurrencyE2EStartupTests {
    @Test func resetSeedsRealStoresAndPreservesUnrelatedData() async throws {
      try await withFixture { directory, defaults in
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unrelated = directory.appendingPathComponent("unrelated.json")
        try Data("keep".utf8).write(to: unrelated)
        defaults.set("keep", forKey: "unrelated")
        defaults.set("dark", forKey: "appearance.theme")
        _ = try ConversionStore(directory: directory).updateInput { $0.setAmount("99") }
        var resets = 0
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let service = try #require(
          try CurrencyE2EStartup.prepare(
            arguments: ["-CurrencyE2E", "-CurrencyE2EState", "ready-converter"],
            directory: { directory }, defaults: defaults, resetTips: { resets += 1 }, now: now))
        let composition = AppComposition(
          directory: directory, appearance: AppearancePreferences(defaults: defaults),
          discoveryDefaults: defaults, service: service)
        #expect(resets == 1)
        #expect(composition.conversion.input().source == "EUR")
        #expect(composition.conversion.input().amount == "1")
        #expect(composition.conversion.input().destinations == ["USD"])
        #expect(composition.progress.load()?.completed == true)
        #expect(composition.rates.loadRates().checkedAt == now)
        #expect(composition.appearance.theme == .system)
        #expect(defaults.string(forKey: "unrelated") == "keep")
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
        #expect(composition.discovery.load().canOfferHistory(editing: true) == false)
        let refresh = try await composition.refresh(force: true)
        #expect(refresh.warning == nil)
        #expect(refresh.snapshot.convert(42, from: "EUR", to: "USD") == 84)
        #expect(refresh.snapshot.quotes["CHF"]?.value == 0.5)
        #expect(refresh.snapshot.quotes["CZK"]?.value == 25)
      }
    }

    @Test func resetReplacesRatesAndPreservesThemAgainstAnOlderRefresh() async throws {
      try await withFixture { directory, defaults in
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let earlier = now.addingTimeInterval(-60)
        let day = now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let previous = RateSnapshot(
          quotes: [
            "EUR": ExchangeRate(
              1, published: day, source: .init(provider: .ecb), cachedAt: earlier),
            "USD": ExchangeRate(
              1.13, published: day, source: .init(provider: .ecb), cachedAt: earlier)
          ], fetchedAt: earlier, checkedAt: earlier)
        try RateCache(directory: directory).save(previous)
        _ = try CurrencyE2EStartup.prepare(
          arguments: ["-CurrencyE2E", "-CurrencyE2EState", "ready-converter"],
          directory: { directory }, defaults: defaults, resetTips: {}, now: now)
        let rates = RateStore(directory: directory)
        #expect(rates.loadRates().quotes["USD"]?.value == 2)
        _ = try rates.saveBootstrapRates(previous, now: now)
        #expect(rates.loadRates().quotes["USD"]?.value == 2)
        #expect(rates.loadRates().quotes["USD"]?.cachedAt == now)
      }
    }

    @Test(arguments: ["ready-converter", "fresh-onboarding"])
    func resetReplacesHistoryWithFreshDeterministicSeries(state: String) async throws {
      try await withFixture { directory, defaults in
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history-EUR-USD-30.json")
        try Data("invalid previous history".utf8).write(to: file)
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        _ = try CurrencyE2EStartup.prepare(
          arguments: ["-CurrencyE2E", "-CurrencyE2EState", state],
          directory: { directory }, defaults: defaults, resetTips: {}, now: now)
        let series = try JSONDecoder().decode(HistorySeries.self, from: Data(contentsOf: file))
        #expect(
          series.points == [
            HistoryPoint(date: now.addingTimeInterval(-7 * 86400), value: 1.8),
            HistoryPoint(date: now.addingTimeInterval(-86400), value: 2)
          ])
        #expect(series.fetchedAt == now)
        #expect(series.source == RateSource(provider: .ecb, observation: .dailyReference))
        let result = await HistoryService(directory: directory, client: UnexpectedHistoryClient())
          .load(
            base: "EUR", quote: "USD", range: .month,
            now: now.addingTimeInterval(86399), cacheLifetime: 86400)
        #expect(result.issue == nil)
        #expect(result.series?.points == series.points)
      }
    }

    @Test func launchWithoutExplicitResetPreservesHistory() async throws {
      try await withFixture { directory, defaults in
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history-EUR-USD-30.json")
        let previous = Data("existing history".utf8)
        try previous.write(to: file)
        for arguments in [["-AppleLanguages", "(en)"], ["-CurrencyE2E"]] {
          var accessedState = false
          _ = try CurrencyE2EStartup.prepare(
            arguments: arguments,
            directory: {
              accessedState = true
              return directory
            }, defaults: defaults, resetTips: { accessedState = true })
          #expect(!accessedState)
          #expect(try Data(contentsOf: file) == previous)
        }
      }
    }

    @Test func steadyFixtureLaunchPreservesEditsAndOnboardingCompletion() async throws {
      try await withFixture { directory, defaults in
        _ = try ConversionStore(directory: directory).updateInput { $0.setAmount("99") }
        try OnboardingProgressStore(directory: directory)
          .save(
            OnboardingProgress(draft: ConverterState(), step: .ready, completed: true))
        _ = try CurrencyE2EStartup.prepare(
          arguments: ["-CurrencyE2E", "-CurrencyE2EState", "fresh-onboarding"],
          directory: { directory }, defaults: defaults, resetTips: {})
        let progress = OnboardingProgressStore(directory: directory)
        #expect(progress.load() == nil)
        #expect(
          !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("onboarding.json").path))
        #expect(
          !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("input.json").path))
        let conversion = ConversionStore(directory: directory)
        #expect(conversion.input() == ConverterState())
        let edited = try conversion.updateInput { $0.setAmount("42") }
        try progress.save(OnboardingProgress(draft: edited, step: .ready, completed: true))
        defaults.set("dark", forKey: "appearance.theme")
        var accessedState = false
        let service = try CurrencyE2EStartup.prepare(
          arguments: ["-CurrencyE2E"],
          directory: {
            accessedState = true
            return directory
          }, defaults: defaults, resetTips: { accessedState = true })
        #expect(service != nil)
        #expect(!accessedState)
        #expect(conversion.input() == edited)
        #expect(progress.load()?.completed == true)
        #expect(defaults.string(forKey: "appearance.theme") == "dark")
      }
    }

    @Test func rejectsInvalidArgumentsBeforeReset() throws {
      let invalid = [
        ["-CurrencyE2EState", "ready-converter"], ["-CurrencyE2E", "-CurrencyE2EState"],
        ["-CurrencyE2E", "-CurrencyE2EState", "unknown"], ["-CurrencyE2E", "-CurrencyE2E"],
        ["-CurrencyE2EUnknown"],
        [
          "-CurrencyE2E", "-CurrencyE2EState", "ready-converter", "-CurrencyE2EState",
          "fresh-onboarding"
        ]
      ]
      for arguments in invalid {
        var reset = false
        #expect(throws: CurrencyE2EStartup.StartupError.invalidArguments) {
          try CurrencyE2EStartup.prepare(arguments: arguments, resetTips: { reset = true })
        }
        #expect(!reset)
      }
      var accessedState = false
      #expect(
        try CurrencyE2EStartup.prepare(
          arguments: ["-AppleLanguages", "(en)"],
          directory: {
            accessedState = true
            return URL(fileURLWithPath: "/unused")
          }, resetTips: { accessedState = true }) == nil)
      #expect(!accessedState)
    }

    @Test func propagatesTipResetAndPersistenceFailures() async throws {
      try await withFixture { directory, defaults in
        let arguments = ["-CurrencyE2E", "-CurrencyE2EState", "ready-converter"]
        #expect(throws: CocoaError(.fileWriteUnknown)) {
          try CurrencyE2EStartup.prepare(
            arguments: arguments, directory: { directory }, defaults: defaults,
            resetTips: { throw CocoaError(.fileWriteUnknown) })
        }
        try Data("blocks directory creation".utf8).write(to: directory)
        #expect(throws: (any Error).self) {
          try CurrencyE2EStartup.prepare(
            arguments: arguments, directory: { directory }, defaults: defaults, resetTips: {})
        }
      }
    }

    private func withFixture(
      _ body: @MainActor (URL, UserDefaults) async throws -> Void
    ) async throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      let suite = UUID().uuidString
      let defaults = try #require(UserDefaults(suiteName: suite))
      defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
      }
      try await body(directory, defaults)
    }
  }

  private struct UnexpectedHistoryClient: HTTPClient {
    func get(_ url: URL) async throws -> Data {
      Issue.record("Fresh seeded history must not request \(url)")
      throw RateError.unavailable
    }
  }
#endif
