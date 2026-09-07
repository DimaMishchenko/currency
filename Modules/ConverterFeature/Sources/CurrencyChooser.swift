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
  let homeCurrencies: [String]
  let available: Set<String>
  var choose: (String) -> Void
  @State private var search = ""
  @State private var category: CurrencyCategory
  @Environment(\.dismiss) private var dismiss
  init(
    purpose: PickerPurpose, selected: [String], homeCurrencies: [String],
    available: Set<String>, choose: @escaping (String) -> Void
  ) {
    self.purpose = purpose
    self.selected = selected
    self.homeCurrencies = homeCurrencies
    self.available = available
    self.choose = choose
    _category = State(initialValue: purpose == .source ? .selected : .currencies)
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(filteredCodes, id: \.self) { code in
          Button {
            choose(code)
            dismiss()
          } label: {
            HStack(spacing: AppStyle.Space.large) {
              CurrencyIcon(code)
              VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
                Text(code).font(AppStyle.font(.headline))
                Text(CurrencyDisplay.name(code, locale: locale)).font(AppStyle.font(.caption))
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if selected.contains(code) {
                Image(systemName: "checkmark").foregroundStyle(.secondary)
              } else if !available.contains(code) {
                Text(.Converter.unavailable).font(AppStyle.font(.caption2))
                  .foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, AppStyle.Space.xs)
          }
          .foregroundStyle(.primary).disabled(selected.contains(code))
          .listRowBackground(Color.clear)
        }
      }
      .scrollContentBackground(.hidden)
      .safeAreaInset(edge: .top, spacing: 0) {
        if search.isEmpty {
          Picker(selection: $category) {
            ForEach(categories, id: \.self) { category in
              Text(category.title).tag(category)
            }
          } label: {
            Text(.Converter.assetCategory)
          }
          .pickerStyle(.segmented)
          .padding(.horizontal)
          .padding(.vertical, AppStyle.Space.small)

        }
      }
      .searchable(text: $search)
      .navigationTitle(
        purpose == .source ? .Converter.baseCurrency : .Converter.addCurrency
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.Converter.close, systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
        }
      }
    }
    .presentationBackground {
      Rectangle().fill(.clear)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }
  }

  private var categories: [CurrencyCategory] {
    CurrencyCategory.allCases.filter { purpose == .source || $0 != .selected }
  }

  private var filteredCodes: [String] {
    if search.isEmpty, category == .selected { return homeCurrencies }
    return CurrencyCatalog.codes.filter { code in
      if search.isEmpty { return category.contains(code) }
      return "\(code) \(CurrencyDisplay.name(code, locale: locale))"
        .localizedCaseInsensitiveContains(search)
    }
  }
}

private enum CurrencyCategory: CaseIterable {
  case selected, currencies, metals, crypto

  var title: LocalizedStringResource {
    switch self {
    case .selected: .Converter.selectedCurrencies
    case .crypto: .Converter.crypto
    case .metals: .Converter.metals
    case .currencies: .Converter.currencies
    }
  }

  func contains(_ code: String) -> Bool {
    let isMetal = ["XAU", "XAG", "XPT", "XPD"].contains(code)
    switch self {
    case .selected: return false
    case .crypto: return CurrencyCatalog.crypto.contains(code)
    case .metals: return isMetal
    case .currencies: return !isMetal && !CurrencyCatalog.crypto.contains(code)
    }
  }
}
