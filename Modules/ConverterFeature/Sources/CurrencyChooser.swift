import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

enum PickerPurpose: String, Identifiable {
  case source, add
  var id: String { rawValue }
}
struct CurrencyChooser: View {
  @Environment(\.locale) private var locale
  let purpose: PickerPurpose
  let selected: [String]
  let available: Set<String>
  var choose: (String) -> Void
  @State private var search = ""
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        ForEach([false, true], id: \.self) { crypto in
          Section(crypto ? .Converter.crypto : .Converter.currencies) {
            ForEach(
              CurrencyCatalog.codes.filter {
                CurrencyCatalog.crypto.contains($0) == crypto
                  && (search.isEmpty
                    || "\($0) \(CurrencyDisplay.name($0, locale: locale))"
                      .localizedCaseInsensitiveContains(search))
              }, id: \.self
            ) { code in
              Button {
                choose(code)
                dismiss()
              } label: {
                HStack(spacing: 14) {
                  CurrencyIcon(code)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(code).font(.headline)
                    Text(CurrencyDisplay.name(code, locale: locale)).font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  if selected.contains(code) {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                  } else if !available.contains(code) {
                    Text(.Converter.unavailable).font(.caption2)
                      .foregroundStyle(.secondary)
                  }
                }
                .padding(.vertical, 4)
              }
              .foregroundStyle(.primary).disabled(selected.contains(code))
            }
          }
        }
      }
      .searchable(text: $search)
      .navigationTitle(
        purpose == .source ? .Converter.baseCurrency : .Converter.addCurrency
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(.Converter.done) { dismiss() }
        }
      }
    }
  }
}
