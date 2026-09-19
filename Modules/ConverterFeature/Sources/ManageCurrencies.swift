import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

struct ManageCurrencies: View {
  let model: ConverterModel
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(model.input.destinations, id: \.self) { code in
            Label {
              Text(code).font(AppStyle.font(.body).weight(.medium))
            } icon: {
              CurrencyIcon(code)
            }
          }
          .onDelete { offsets in
            let removed = offsets.map { model.input.destinations[$0] }
            if model.updateInput({
              $0.setDestinations($0.destinations.filter { !removed.contains($0) })
            }) {
              AppHaptics.play(.delete)
            }
          }
          .onMove { source, destination in
            let list = model.input.destinations
            let moved = source.map { list[$0] }
            let anchor = list.dropFirst(destination).first { !moved.contains($0) }
            if model.updateInput({ $0.moveDestinations(moved, before: anchor) }) {
              AppHaptics.play(.selection)
            }
          }
        } footer: {
          Text(.Converter.reorderHint)
        }
      }
      .safeAreaInset(edge: .bottom) {
        if let warning = model.warning {
          Text(warning).font(AppStyle.font(.caption)).foregroundStyle(.secondary).padding()
        }
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle(.Converter.yourCurrencies)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.Converter.close, systemImage: "xmark") {
            AppHaptics.play(.action); dismiss()
          }
          .labelStyle(.iconOnly)
        }
      }
    }
  }
}
