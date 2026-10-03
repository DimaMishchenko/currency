import Conversion
import DesignSystem
import ExchangeRates
import ExchangeRatesUI
import Home
import SwiftUI

struct ManageCurrencies: View {
  let model: HomeModel
  @Environment(\.dismiss) private var dismiss
  @State private var editMode: EditMode = .inactive
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
            if model.withFeedback({ model.removeDestinations(removed) }) {
              AppHaptics.play(.delete)
            }
          }
          .onMove { source, destination in
            let list = model.input.manualDestinations
            let moved = source.map { list[$0] }
            let anchor = list.dropFirst(destination).first { !moved.contains($0) }
            if model.withFeedback({ model.moveDestinations(moved, before: anchor) }) {
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
              if model.withFeedback({ model.removeDestinations([CurrencySelection.localID]) }) {
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
      .navigationTitle(.Converter.currenciesTitle)
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          EditButton()
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(.Converter.close, systemImage: "xmark") {
            AppHaptics.play(.action); dismiss()
          }
          .labelStyle(.iconOnly).tint(nil)
        }
      }
    }
    .environment(\.editMode, $editMode)
  }
}
