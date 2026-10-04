import Conversion
import CurrencyApplication
import CurrencyDetails
import CurrencyDetailsWatchUI
import ExchangeRates
import Home
import HomeWatchUI
import SwiftUI

@main
struct CurrencyWatchApp: App {
  private let composition = WatchComposition()
  var body: some Scene {
    WindowGroup { WatchRoot(composition: composition) }
  }
}

private struct WatchDetail: Identifiable, Hashable {
  let id = UUID()
  let input: CurrencyDetailsInput
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct WatchRoot: View {
  let composition: WatchComposition
  @State private var model: HomeModel
  @State private var detail: WatchDetail?
  @State private var routeIssue = false
  @Environment(\.scenePhase) private var phase

  init(composition: WatchComposition) {
    self.composition = composition
    _model = State(initialValue: HomeModel(dependencies: composition.home))
  }

  var body: some View {
    NavigationStack {
      HomeWatchScreen(model: model) { output in
        if case .detailsRequested(let request) = output {
          detail = WatchDetail(
            input: .init(
              code: request.code, reference: request.reference, snapshot: request.snapshot))
        }
      }
      .navigationDestination(item: $detail) { item in
        CurrencyDetailsWatchScreen(input: item.input, dependencies: composition.details)
      }
    }
    .task(id: phase) {
      guard phase == .active else { return }
      composition.startCompanionSync()
      model.reloadSharedState()
      _ = await model.refresh(force: false)
    }
    .onOpenURL(perform: open)
    .alert("Choose a supported currency.", isPresented: $routeIssue) {
      Button("Done", role: .cancel) {}
    }
  }

  private func open(_ url: URL) {
    guard url.scheme == "currency-watch" else { return }
    guard let route = WatchCurrencyRoute(url: url) else { routeIssue = true; return }
    switch route {
    case .converter:
      detail = nil
      model.reloadSharedState()
    case .details(let source, let quote):
      detail = WatchDetail(
        input: .init(
          code: source, reference: quote, snapshot: composition.rates.loadRates(),
          referencePolicy: .requestedPair))
    case .convert(let source, let quote, let amount):
      do {
        _ = try composition.edit {
          $0.changeSource(source)
          $0.setDestinations([quote] + $0.manualDestinations.filter { $0 != quote })
          if let amount { $0.setAmount(amount) }
        }
        detail = nil
        model.reloadSharedState()
      } catch { routeIssue = true }
    }
  }
}
