import CurrencySelectionUI
import CurrencySupport
import ExchangeRates
import SwiftUI

/// The same segmented, searchable picker used by the converter, with draft multi-selection.
struct OnboardingCurrencySearch: View {
  let model: OnboardingModel
  let choosingBase: Bool

  var body: some View {
    CurrencyChooser(
      purpose: choosingBase ? .source : .add,
      selected: choosingBase ? [model.draft.source] : model.draft.destinations,
      homeCurrencies: [model.draft.source] + model.draft.destinations,
      available: Set(
        CurrencyCatalog.codes.filter {
          choosingBase ? model.canUseAsBase($0) : model.isAvailable($0)
        }),
      allowedCodes: choosingBase
        ? nil : Set(CurrencyCatalog.codes.filter { $0 != model.draft.source }),
      title: choosingBase ? .Onboarding.baseCurrency : .Onboarding.chooseCurrencies,
      allowsMultipleSelection: !choosingBase, requiresAvailableRate: true,
      showsSelectedCategory: false
    ) { code in
      if choosingBase { model.changeBase(code) } else { model.toggle(code) }
    }
    .sensoryFeedback(.selection, trigger: model.draft)
  }
}
