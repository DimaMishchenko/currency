import Conversion
import DesignSystem
import ExchangeRatesUI
import Onboarding
import SwiftUI

struct OnboardingCurrencyTile: View {
  let code: String
  let selected: Bool
  let available: Bool
  let identifier: String
  let action: () -> Void
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var textSize
  @ScaledMetric(relativeTo: .subheadline) private var minimumHeight: CGFloat = 64

  var body: some View {
    Button {
      action()
    } label: {
      HStack(spacing: 10) {
        CurrencyIcon(code, size: 28).frame(width: 32)
        VStack(alignment: .leading, spacing: 4) {
          Text(code).font(AppStyle.font(.subheadline, weight: .semibold))
          Text(
            available
              ? CurrencyDisplay.name(code, locale: locale)
              : String(localized: .Onboarding.unavailable)
          )
          .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
          .lineLimit(textSize.isAccessibilitySize ? nil : 2)
          .fixedSize(horizontal: false, vertical: true)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        OnboardingSelectionMark().opacity(selected ? 1 : 0).frame(width: 20)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: minimumHeight)
      .background { OnboardingSurface(radius: 18, selected: selected) }

    }
    .buttonStyle(.plain).disabled(!available && !selected)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(CurrencyDisplay.name(code, locale: locale)), \(code)")
    .accessibilityValue(
      selected
        ? Text(.Onboarding.selected)
        : available ? Text(.Onboarding.notSelected) : Text(.Onboarding.unavailable)
    )
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier(identifier)
  }

}

struct OnboardingSelectionMark: View {
  @Environment(AppAppearance.self) private var appearance
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast
  var body: some View {
    Image(systemName: "checkmark.circle.fill")
      .font(.system(size: 17))
      .symbolRenderingMode(.palette)
      .foregroundStyle(
        appearance.accentForeground(colorScheme: colorScheme, contrast: contrast), appearance.accent
      )
      .accessibilityHidden(true)
  }
}

struct OnboardingMoreCurrenciesTile: View {
  var fullWidth = false
  let action: () -> Void
  @Environment(\.dynamicTypeSize) private var textSize
  @ScaledMetric(relativeTo: .subheadline) private var minimumHeight: CGFloat = 64

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").font(.system(size: 24)).frame(width: 32)
        VStack(alignment: .leading, spacing: 4) {
          Text(.Onboarding.moreCurrencies)
            .font(AppStyle.font(.subheadline, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Color.clear.frame(width: 20)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: fullWidth ? minimumHeight * 0.75 : minimumHeight)
      .background { OnboardingSurface(radius: 18) }

    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.Onboarding.moreCurrencies))
    .accessibilityIdentifier("onboarding.destinationsMore")
  }
}

struct OnboardingRecommendationList<Content: View>: View {
  @ViewBuilder let content: Content
  @Environment(\.dynamicTypeSize) private var textSize

  var body: some View {
    LazyVGrid(
      columns: [
        GridItem(textSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 220), spacing: 8)
      ], spacing: 8
    ) {
      content
    }
    .padding(.horizontal, 24)
  }
}
