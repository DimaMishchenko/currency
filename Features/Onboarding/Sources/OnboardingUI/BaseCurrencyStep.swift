import Conversion
import DesignSystem
import ExchangeRatesUI
import Onboarding
import SwiftUI

struct BaseCurrencyStep: View {
  let model: OnboardingModel
  let progress: CGFloat
  let reduced: Bool
  let compact: Bool
  let heroHeight: CGFloat
  let openPicker: () -> Void
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var textSize
  @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 40

  var body: some View {
    VStack(spacing: compact ? 12 : 20) {
      VStack(spacing: 8) {
        Text(model.draft.source)
          .font(
            .system(
              size: compact ? codeSize * 0.8 : codeSize, weight: .semibold, design: .rounded)
          )
          .lineLimit(1).minimumScaleFactor(0.6)
        HStack(spacing: 8) {
          CurrencyIcon(model.draft.source, size: 24).accessibilityHidden(true)
          Text(CurrencyDisplay.name(model.draft.source, locale: locale))
            .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.horizontal, 24)
      .frame(minHeight: heroHeight)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text(.Onboarding.baseCurrency))
      .accessibilityValue(
        "\(CurrencyDisplay.name(model.draft.source, locale: locale)), \(model.draft.source)"
      )
      .accessibilityIdentifier("onboarding.base")

      if !model.hasUsableRates {
        VStack(spacing: 8) {
          Text(.Onboarding.baseMissing).font(AppStyle.font(.caption))
            .foregroundStyle(.secondary)
          Button(.Onboarding.retry) { model.retry() }.disabled(model.isRefreshing)
        }
        .multilineTextAlignment(.center).padding(.horizontal, 24)
      }

      if !textSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          Text(.Onboarding.popularCurrencies)
            .font(AppStyle.font(.headline, weight: .bold))
            .padding(.horizontal, 24)
          OnboardingRecommendationList {
            ForEach(OnboardingRecommendations.currencies, id: \.self) { code in
              quickChoice(code)
            }
          }
          .accessibilityIdentifier("onboarding.baseRecommendations")
          OnboardingMoreCurrenciesTile(fullWidth: true, action: openPicker)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("onboarding.baseMore")
        }
      }
    }
    .padding(.vertical, 12)
    .modifier(OnboardingReveal(progress: progress, offset: 24, scale: 0.96, reduced: reduced))
  }

  private func quickChoice(_ code: String) -> some View {
    OnboardingCurrencyTile(
      code: code, selected: model.draft.source == code, available: model.canUseAsBase(code),
      identifier: "onboarding.baseChoice.\(code)"
    ) { model.changeBase(code) }
  }
}
