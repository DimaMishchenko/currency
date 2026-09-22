import Conversion
import DesignSystem
import ExchangeRates
import Foundation
import Home
import HomeUI
import LocalCurrency
import SwiftUI

@MainActor
private final class HomeHarnessFixture {
  let name: String
  var input = ConverterState()
  var snapshot: RateSnapshot
  var local: WidgetLocation?
  var status: WidgetLocationStatus = .notDetermined
  var notification: AsyncStream<Void>.Continuation?
  var didFailSave = false
  var rateIssue: HomeIssue?

  init(name: String) {
    self.name = name
    snapshot = RateSnapshot(
      quotes: [
        "EUR": ExchangeRate(1, published: "2026-09-19", source: .init(provider: .ecb)),
        "USD": ExchangeRate(1.08, published: "2026-09-19", source: .init(provider: .ecb)),
        "GBP": ExchangeRate(0.84, published: "2026-09-19", source: .init(provider: .ecb)),
        "CZK": ExchangeRate(25, published: "2026-09-19", source: .init(provider: .ecb))
      ], fetchedAt: .now)
    if name == "empty" { input.setDestinations([]) }
    if name == "unavailable" { snapshot = RateSnapshot() }
    if name == "local-stale" {
      input.setUsesLocalCurrency(true)
      local = WidgetLocation(
        country: "CZ", currency: "CZK", updatedAt: .now.addingTimeInterval(-172_800))
      status = .available
      input.resolveLocalCurrency(local, status: status)
    }
  }

  var dependencies: HomeDependencies {
    .init(
      readInput: { self.input }, readRates: { self.snapshot },
      readRateIssue: { self.rateIssue },
      readLocalCurrency: { (self.local, self.status) },
      editInput: { edit in
        if self.name == "save-failure", !self.didFailSave {
          self.didFailSave = true
          throw CocoaError(.fileWriteOutOfSpace)
        }
        var next = self.input
        try edit(&next)
        self.input = next
        self.notification?.yield(())
        return next
      },
      refreshRates: { _ in
        if self.name == "loading" || self.name == "interrupted" {
          try await Task.sleep(for: .seconds(30))
        }
        if self.name == "refresh-failure" {
          self.rateIssue = .rateSaveFailed
          throw CocoaError(.fileWriteOutOfSpace)
        }
        self.rateIssue = self.name == "refresh-warning" ? .rateWarning(.dailyRatesUnavailable) : nil
        return RefreshResult(
          snapshot: self.snapshot,
          warning: self.name == "refresh-warning" ? .dailyRatesUnavailable : nil)
      },
      changes: { AsyncStream { self.notification = $0 } })
  }
}

@main
struct HomeHarnessApp: App {
  @State private var flowID = UUID()
  @Namespace private var widgets
  @Namespace private var details
  @State private var appearance = AppAppearance(
    theme: .system, accent: .primary, onThemeChange: { _ in }, onAccentChange: { _ in })
  @State private var fixture: HomeHarnessFixture

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    let index = arguments.firstIndex(of: "--case")
    let name =
      index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "normal"
    _fixture = State(initialValue: HomeHarnessFixture(name: name))
  }

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        HomeEntry(
          flowID: flowID, active: true, detailsNamespace: details, widgetsNamespace: widgets,
          onOutput: { _ in })
      }
      .environment(\.homeDependencies, fixture.dependencies)
      .environment(appearance)
      .tint(appearance.accent)
      .preferredColorScheme(appearance.theme.colorScheme)
    }
  }
}
