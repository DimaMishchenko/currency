import Conversion
import DesignSystem
import ExchangeRates
import ExchangeRatesUI
import Home
import SwiftUI

struct ManageCurrencies: View {
  let model: HomeModel
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(model.input.manualDestinations, id: \.self) { code in
            Label {
              Text(code).font(AppStyle.font(.body).weight(.medium))
            } icon: {
              CurrencyIcon(code)
            }
          }
          .onDelete { offsets in
            let removed = offsets.map { model.input.manualDestinations[$0] }
            if model.updateWithFeedback({
              $0.setDestinations($0.manualDestinations.filter { !removed.contains($0) })
            }) {
              AppHaptics.play(.delete)
            }
          }
          .onMove { source, destination in
            let list = model.input.manualDestinations
            let moved = source.map { list[$0] }
            let anchor = list.dropFirst(destination).first { !moved.contains($0) }
            if model.updateWithFeedback({ $0.moveDestinations(moved, before: anchor) }) {
              AppHaptics.play(.selection)
            }
          }
        } footer: {
          Text(.Converter.reorderHint)
        }
        if model.input.usesLocalCurrency {
          Section {
            ForEach([CurrencySelection.localID], id: \.self) { _ in
              Label(.Converter.localCurrency, systemImage: "location")
            }
            .onDelete { _ in
              if model.updateWithFeedback({ $0.setUsesLocalCurrency(false) }) {
                AppHaptics.play(.delete)
              }
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if let warning = model.warningText {
          Text(warning).font(AppStyle.font(.caption)).foregroundStyle(.secondary).padding()
        }
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle(.Converter.manageCurrencies)
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.Converter.close, systemImage: "xmark") {
            AppHaptics.play(.action); dismiss()
          }
          .labelStyle(.iconOnly).tint(nil)
        }
      }
    }
  }
}
