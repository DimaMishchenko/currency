import CurrencySupport
import SwiftUI

/// A single draft choice, confirmed separately from destination selection.
struct BaseCurrencyStep: View {
  let model: OnboardingModel
  let progress: CGFloat
  let reduced: Bool
  let compact: Bool
  let openPicker: () -> Void
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var textSize
  @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 56

  var body: some View {
    VStack(spacing: compact ? 20 : 28) {
      Spacer(minLength: compact ? 12 : 28)
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
      .frame(minHeight: textSize.isAccessibilitySize ? 0 : compact ? 100 : 140)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text(.Onboarding.baseCurrency))
      .accessibilityValue(
        "\(CurrencyDisplay.name(model.draft.source, locale: locale)), \(model.draft.source)"
      )
      .accessibilityIdentifier("onboarding.base")
      .modifier(OnboardingReveal(progress: progress, offset: 10, reduced: reduced))

      if !model.hasUsableRates {
        VStack(spacing: 8) {
          Text(.Onboarding.baseMissing).font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          Button(.Onboarding.retry) { model.retry() }.disabled(model.isRefreshing)
        }
        .multilineTextAlignment(.center).padding(.horizontal, 24)
      }

      VStack(spacing: 20) {
        if !textSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 10) {
            Text(.Onboarding.popularCurrencies)
              .font(AppStyle.font(.headline, weight: .bold))
              .padding(.horizontal, 24)
            ScrollView(.horizontal) {
              HStack(spacing: 8) {
                ForEach(["EUR", "USD", "GBP", "CZK", "JPY", "CHF"], id: \.self) { code in
                  quickChoice(code)
                }
                Button(action: openPicker) {
                  HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text(.Onboarding.more)
                  }
                  .font(AppStyle.font(.subheadline, weight: .medium))
                  .frame(width: 104, height: 44)
                  .background(
                    Color(uiColor: .secondarySystemBackground).opacity(0.45), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.Onboarding.moreCurrencies))
                .accessibilityIdentifier("onboarding.baseMore")
              }
              .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("onboarding.baseRecommendations")
          }
        }
      }
      .modifier(OnboardingReveal(progress: progress, delay: 0.14, offset: 10, reduced: reduced))
      Spacer(minLength: compact ? 12 : 28)
    }
  }

  private func quickChoice(_ code: String) -> some View {
    let selected = model.draft.source == code
    let available = model.canUseAsBase(code)
    return Button {
      model.changeBase(code)
    } label: {
      HStack(spacing: 6) {
        CurrencyIcon(code, size: 22)
        Text(code).font(AppStyle.font(.subheadline, weight: .medium))
        if selected {
          OnboardingSelectionMark()
        }
      }
      .frame(width: 104, height: 44)
      .background(
        Color(uiColor: .secondarySystemBackground).opacity(selected ? 1 : 0.45), in: .capsule
      )
      .contentShape(.capsule)
    }
    .buttonStyle(.plain).disabled(!available)
    .accessibilityLabel("\(CurrencyDisplay.name(code, locale: locale)), \(code)")
    .accessibilityValue(
      selected
        ? Text(.Onboarding.selected)
        : available ? Text(.Onboarding.notSelected) : Text(.Onboarding.unavailable)
    )
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("onboarding.baseChoice.\(code)")
  }
}
