import Conversion
import DesignSystem
import ExchangeRates
import ExchangeRatesUI
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
  let selectionFailureMessage: LocalizedStringResource?
  var choose: (String) -> Bool
  @State private var search = ""
  @State private var selectionFailed = false
  @State private var category: CurrencyCategory
  @Environment(\.dismiss) private var dismiss
  /// Creates a picker with caller-owned selection and optional supported-code filtering.
  /// `choose` returns true only after accepting the selection. Rejection preserves presentation
  /// and displays `selectionFailureMessage`, or the picker's default save-failure message.
  public init(
    purpose: PickerPurpose, selected: [String], homeCurrencies: [String],
    available: Set<String>, allowedCodes: Set<String>? = nil,
    title: LocalizedStringResource? = nil, allowsMultipleSelection: Bool = false,
    requiresAvailableRate: Bool = false, showsSelectedCategory: Bool = true,
    showsLocalCurrency: Bool = false, localCurrencyCode: String? = nil,
    localCurrencySelected: Bool = false,
    setUpLocalCurrency: (() -> Void)? = nil,
    selectionFailureMessage: LocalizedStringResource? = nil,
    choose: @escaping (String) -> Bool
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
    self.selectionFailureMessage = selectionFailureMessage
    _category = State(
      initialValue: showsSelectedCategory && purpose == .source && !homeCurrencies.isEmpty
        ? .selected : .currencies)
  }

  /// The searchable currency list and category controls.
  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if search.isEmpty {
          Group {
            if dynamicTypeSize.isAccessibilitySize {
              AdaptiveSegmentedPicker(
                .CurrencySelection.assetCategory,
                choices: categories,
                selection: $category,
                optionTitle: { Text($0.title) },
                fullTitle: { Text($0.accessibilityTitle) }
              )
            } else {
              Picker(selection: $category) {
                ForEach(categories, id: \.self) { category in
                  Text(category.title).accessibilityLabel(Text(category.accessibilityTitle))
                    .tag(category)
                }
              } label: {
                Text(.CurrencySelection.assetCategory)
              }
              .pickerStyle(.segmented)
            }
          }
          .accessibilityIdentifier("currency.picker.category")
          .padding(.horizontal)
          .padding(.vertical, AppStyle.Space.small)

        }
        currencyList
          .id("\(category)-\(search)")
          .onChange(of: category) { _, _ in AppHaptics.play(.selection) }

      }

      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
      .searchable(text: $search, prompt: Text(.CurrencySelection.search))
      .autocorrectionDisabled()
      .textInputAutocapitalization(.never)
      .navigationTitle(
        title
          ?? (purpose == .source
            ? .CurrencySelection.baseCurrency : .CurrencySelection.addCurrency)
      )
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) {
        if selectionFailed {
          Label {
            Text(selectionFailureMessage ?? .CurrencySelection.selectionSaveFailed)
          } icon: {
            Image(systemName: "exclamationmark.circle")
          }
          .font(AppStyle.font(.caption))
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.regularMaterial)
          .accessibilityIdentifier("currency.picker.saveFailure")
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.CurrencySelection.close, systemImage: "xmark") {
            AppHaptics.play(.action); dismiss()
          }
          .labelStyle(.iconOnly).tint(nil)
          .accessibilityIdentifier("currency.picker.close")
        }
      }
    }
  }

  private var currencyList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if showsLocalCurrency && localMatchesSearch {
          Text(.CurrencySelection.location)
            .font(AppStyle.font(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.bottom, 12).accessibilityAddTraits(.isHeader)
          localCurrencyRow.padding(.vertical, 12)
          if !filteredCodes.isEmpty {
            Divider().padding(.top, 8).padding(.bottom, 24)
          }
        }
        ForEach(Array(browseSections.enumerated()), id: \.offset) { _, section in
          if let title = section.title {
            Text(title)
              .font(AppStyle.font(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
              .padding(.top, 16).padding(.bottom, 8).accessibilityAddTraits(.isHeader)
          }
          ForEach(section.codes, id: \.self) { code in
            currencyRow(code)
          }
        }

      }
      .padding(.horizontal, 20).padding(.vertical, 24)
    }
    .overlay {
      if filteredCodes.isEmpty && !(showsLocalCurrency && localMatchesSearch) {
        ContentUnavailableView {
          Label(.CurrencySelection.noResults, systemImage: "magnifyingglass")
        } description: {
          Text(.CurrencySelection.noResultsDetail)
        }
      }
    }
    .clipped()
  }

  @ViewBuilder
  private func currencyRow(_ code: String) -> some View {
    Button {
      select(code)
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
          Image(systemName: "checkmark").foregroundStyle(.tint)
        } else if !available.contains(code) {
          Text(.CurrencySelection.unavailable).font(AppStyle.font(.caption2))
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, AppStyle.Space.xs)
      .contentShape(Rectangle())
    }
    .foregroundStyle(Color.primary)
    .disabled(
      (selected.contains(code) && !allowsMultipleSelection)
        || (requiresAvailableRate && !available.contains(code) && !selected.contains(code))
    )
    .accessibilityIdentifier("currency.picker.\(code)")
    .accessibilityAddTraits(selected.contains(code) ? .isSelected : [])
    .buttonStyle(.plain)
    .padding(.vertical, 12)
    Divider()
  }

  private var localCurrencyRow: some View {
    Button {
      if localCurrencyCode != nil {
        select(CurrencySelection.localID)
      } else {
        AppHaptics.play(.selection)
        setUpLocalCurrency?()
        dismiss()
      }
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
              .background(Color.primary, in: .circle)
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
          Image(systemName: "checkmark").foregroundStyle(.tint)
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
      .contentShape(Rectangle())
    }
    .foregroundStyle(Color.primary)
    .disabled(
      localCurrencyCode.map {
        localCurrencySelected || (requiresAvailableRate && !available.contains($0))
      } ?? (setUpLocalCurrency == nil)
    )
    .accessibilityIdentifier("currency.picker.local")
    .accessibilityAddTraits(
      localCurrencySelected ? .isSelected : []
    )
    .buttonStyle(.plain)
  }

  private var localMatchesSearch: Bool {
    guard !search.isEmpty else { return category == .currencies || category == .selected }
    let content = [
      String(localized: .CurrencySelection.localCurrency),
      String(localized: .CurrencySelection.location),
      localCurrencyCode ?? "",
      localCurrencyCode.map { CurrencyDisplay.name($0, locale: locale) } ?? ""
    ]
    .joined(separator: " ")
    return content.localizedCaseInsensitiveContains(search)
  }

  private func select(_ code: String) {
    let accepted = choose(code)
    selectionFailed = !accepted
    AppHaptics.play(accepted ? .selection : .error)
    if accepted && !allowsMultipleSelection { dismiss() }
  }

  private var categories: [CurrencyCategory] {
    CurrencyCategory.allCases.filter {
      $0 != .selected || (showsSelectedCategory && (purpose == .source || allowsMultipleSelection))
    }
  }

  private var filteredCodes: [String] { browseSections.flatMap(\.codes) }

  private var browseSections: [(title: LocalizedStringResource?, codes: [String])] {
    if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return [
        (
          nil,
          CurrencyCatalog.search(search, allowedCodes: allowedCodes, locale: locale) {
            CurrencyDisplay.name($0, locale: locale)
          }
        )
      ]
    }
    let sections: [(LocalizedStringResource?, [String])]
    switch category {
    case .selected: sections = [(nil, homeCurrencies)]
    case .currencies:
      sections = [
        (.CurrencySelection.popularCurrencies, CurrencyCatalog.popularFiat),
        (.CurrencySelection.allCurrencies, CurrencyCatalog.otherFiat)
      ]
    case .crypto:
      sections = [
        (.CurrencySelection.popularCrypto, CurrencyCatalog.popularCrypto),
        (.CurrencySelection.allCrypto, CurrencyCatalog.otherCrypto)
      ]
    case .metals: sections = [(nil, CurrencyCatalog.metals.sorted())]
    }
    return sections.compactMap { title, codes in
      let filtered = codes.filter { allowedCodes?.contains($0) ?? true }
      return filtered.isEmpty ? nil : (title, filtered)
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

  var accessibilityTitle: LocalizedStringResource {
    switch self {
    case .crypto: .CurrencySelection.cryptoAccessibility
    case .selected: .CurrencySelection.selectedCurrenciesAccessibility
    default: title
    }
  }

}
