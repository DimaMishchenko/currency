import CurrencySupport
import ExchangeRates
import SwiftUI

/// Whether the reusable picker chooses a base currency or adds to a list.
public enum PickerPurpose: String, Identifiable {
  /// Selects the currency receiving input.
  case source
  /// Appends a currency to a collection.
  case add
  /// Stable presentation identity.
  public var id: String { rawValue }
}

/// A searchable currency picker shared by app features.
public struct CurrencyChooser: View {
  @Environment(\.locale) private var locale
  let purpose: PickerPurpose
  let selected: [String]
  let homeCurrencies: [String]
  let available: Set<String>
  let allowedCodes: Set<String>?
  let title: LocalizedStringResource?
  let allowsMultipleSelection: Bool
  let requiresAvailableRate: Bool
  let showsSelectedCategory: Bool
  let showsLocalCurrency: Bool
  let localCurrencyCode: String?
  let localCurrencySelected: Bool
  let setUpLocalCurrency: (() -> Void)?
  var choose: (String) -> Void
  @State private var search = ""
  @State private var category: CurrencyCategory
  @Environment(\.dismiss) private var dismiss
  /// Creates a picker with caller-owned selection and optional supported-code filtering.
  public init(
    purpose: PickerPurpose, selected: [String], homeCurrencies: [String],
    available: Set<String>, allowedCodes: Set<String>? = nil,
    title: LocalizedStringResource? = nil, allowsMultipleSelection: Bool = false,
    requiresAvailableRate: Bool = false, showsSelectedCategory: Bool = true,
    showsLocalCurrency: Bool = false, localCurrencyCode: String? = nil,
    localCurrencySelected: Bool = false,
    setUpLocalCurrency: (() -> Void)? = nil,
    choose: @escaping (String) -> Void
  ) {
    self.purpose = purpose
    self.selected = selected
    self.homeCurrencies = homeCurrencies
    self.available = available
    self.allowedCodes = allowedCodes
    self.title = title
    self.choose = choose
    self.allowsMultipleSelection = allowsMultipleSelection
    self.requiresAvailableRate = requiresAvailableRate
    self.showsSelectedCategory = showsSelectedCategory
    self.showsLocalCurrency = showsLocalCurrency
    self.localCurrencyCode = localCurrencyCode
    self.localCurrencySelected = localCurrencySelected
    self.setUpLocalCurrency = setUpLocalCurrency
    _category = State(
      initialValue: showsSelectedCategory && purpose == .source && !homeCurrencies.isEmpty
        ? .selected : .currencies)
  }

  /// The searchable currency list and category controls.
  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if search.isEmpty {
          Picker(selection: $category) {
            ForEach(categories, id: \.self) { category in
              Text(category.title).tag(category)
            }
          } label: {
            Text(.CurrencySelection.assetCategory)
          }
          .pickerStyle(.segmented)
          .padding(.horizontal)
          .padding(.vertical, AppStyle.Space.small)

        }
        ScrollViewReader { scroll in
          currencyList
            .onChange(of: category) { _, _ in
              AppHaptics.play(.selection)
              if let first = filteredCodes.first { scroll.scrollTo(first, anchor: .top) }
            }
            .onChange(of: search) { _, _ in
              if let first = filteredCodes.first { scroll.scrollTo(first, anchor: .top) }
            }
        }
      }

      .searchable(text: $search)
      .autocorrectionDisabled()
      .textInputAutocapitalization(.never)
      .navigationTitle(
        title
          ?? (purpose == .source ? .CurrencySelection.baseCurrency : .CurrencySelection.addCurrency)
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.CurrencySelection.close, systemImage: "xmark") {
            AppHaptics.play(.action); dismiss()
          }
          .labelStyle(.iconOnly)
        }
      }
    }
  }

  private var currencyList: some View {
    List {
      if showsLocalCurrency && localMatchesSearch {
        Section(.CurrencySelection.location) {
          localCurrencyRow
        }
      }
      ForEach(filteredCodes, id: \.self) { code in
        Button {
          AppHaptics.play(.selection)
          choose(code)
          if !allowsMultipleSelection { dismiss() }
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
              Text(.CurrencySelection.unavailable).font(AppStyle.font(.caption2))
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, AppStyle.Space.xs)
        }
        .foregroundStyle(.primary)
        .disabled(
          (selected.contains(code) && !allowsMultipleSelection)
            || (requiresAvailableRate && !available.contains(code) && !selected.contains(code))
        )
        .accessibilityIdentifier("currency.picker.\(code)")
        .accessibilityAddTraits(selected.contains(code) ? .isSelected : [])
        .listRowBackground(Color.clear)
      }
    }
    .scrollContentBackground(.hidden)
    .overlay {
      if filteredCodes.isEmpty && !(showsLocalCurrency && localMatchesSearch) {
        ContentUnavailableView {
          Label(.CurrencySelection.noResults, systemImage: "magnifyingglass")
        } description: {
          Text(.CurrencySelection.noResultsDetail)
        }
      }
    }
    .listStyle(.plain)
    .clipped()
  }

  private var localCurrencyRow: some View {
    Button {
      AppHaptics.play(.selection)
      if localCurrencyCode != nil {
        choose(WidgetSelection.localID)
      } else {
        setUpLocalCurrency?()
      }
      dismiss()
    } label: {
      HStack(spacing: AppStyle.Space.large) {
        ZStack(alignment: .bottomTrailing) {
          if let localCurrencyCode {
            CurrencyIcon(localCurrencyCode)
          } else {
            Image(systemName: "location.fill")
              .font(AppStyle.font(.headline))
              .frame(width: 28, height: 28)
              .background(.quaternary, in: .circle)
          }
          if localCurrencyCode != nil {
            Image(systemName: "location.fill")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(Color(uiColor: .systemBackground))
              .padding(3)
              .background(.primary, in: .circle)
              .offset(x: 4, y: 4)
          }
        }
        VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
          Text(localCurrencyCode ?? String(localized: .CurrencySelection.localCurrency))
            .font(AppStyle.font(.headline))
          Text(
            localCurrencyCode.map {
              String(
                localized: .CurrencySelection.localCurrencyName(
                  CurrencyDisplay.name($0, locale: locale)))
            } ?? String(localized: .CurrencySelection.setUpLocation)
          )
          .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
        }
        Spacer()
        if localCurrencySelected {
          Image(systemName: "checkmark").foregroundStyle(.secondary)
        } else if let localCurrencyCode,
          requiresAvailableRate && !available.contains(localCurrencyCode)
        {
          Text(.CurrencySelection.unavailable).font(AppStyle.font(.caption2))
            .foregroundStyle(.secondary)
        } else if localCurrencyCode == nil {
          Image(systemName: "chevron.right").font(AppStyle.font(.caption, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
      }
      .padding(.vertical, AppStyle.Space.xs)
    }
    .foregroundStyle(.primary)
    .disabled(
      localCurrencyCode.map {
        localCurrencySelected || (requiresAvailableRate && !available.contains($0))
      } ?? (setUpLocalCurrency == nil)
    )
    .accessibilityIdentifier("currency.picker.local")
    .accessibilityAddTraits(
      localCurrencySelected ? .isSelected : []
    )
    .listRowBackground(Color.clear)
  }

  private var localMatchesSearch: Bool {
    guard !search.isEmpty else { return true }
    let content = [
      String(localized: .CurrencySelection.localCurrency),
      String(localized: .CurrencySelection.location),
      localCurrencyCode ?? "",
      localCurrencyCode.map { CurrencyDisplay.name($0, locale: locale) } ?? ""
    ]
    .joined(separator: " ")
    return content.localizedCaseInsensitiveContains(search)
  }

  private var categories: [CurrencyCategory] {
    CurrencyCategory.allCases.filter {
      $0 != .selected || (showsSelectedCategory && (purpose == .source || allowsMultipleSelection))
    }
  }

  private var filteredCodes: [String] {
    if search.isEmpty, category == .selected {
      return homeCurrencies.filter { allowedCodes?.contains($0) ?? true }
    }
    return CurrencyCatalog.codes.filter { code in
      guard allowedCodes?.contains(code) ?? true else { return false }
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
    case .selected: .CurrencySelection.selectedCurrencies
    case .crypto: .CurrencySelection.crypto
    case .metals: .CurrencySelection.metals
    case .currencies: .CurrencySelection.currencies
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
