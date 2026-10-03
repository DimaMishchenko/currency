import Conversion
import DesignSystem
import ExchangeRatesUI
import Onboarding
import SwiftUI

struct OnboardingCurrencyTile: View {
  let code: String
  let selected: Bool
  let available: Bool
  let compact: Bool
  let identifier: String
  let action: () -> Void
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var textSize

  var body: some View {
    Button {
      action()
    } label: {
      VStack(spacing: compact ? 6 : 8) {
        CurrencyIcon(code, size: compact ? 24 : 30).frame(height: compact ? 28 : 36)
        Text(code).font(AppStyle.font(.headline))
        Text(
          available
            ? CurrencyDisplay.name(code, locale: locale)
            : String(localized: .Onboarding.unavailable)
        )
        .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
        .lineLimit(2).frame(height: textSize.isAccessibilitySize ? 52 : 30, alignment: .top)
      }
      .frame(width: textSize.isAccessibilitySize ? 152 : 96).padding(.vertical, compact ? 10 : 16)
      .background { OnboardingSurface(radius: 18, selected: selected) }
      .overlay(alignment: .topTrailing) {
        if selected {
          OnboardingSelectionMark().padding(6)
        }
      }
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
  let compact: Bool
  let action: () -> Void
  @Environment(\.dynamicTypeSize) private var textSize

  var body: some View {
    Button(action: action) {
      VStack(spacing: compact ? 6 : 8) {
        Image(systemName: "magnifyingglass").font(.system(size: 24))
          .frame(height: compact ? 28 : 36)
        Text(.Onboarding.more).font(AppStyle.font(.headline))
        Text(.Onboarding.fiat)
          .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
          .lineLimit(2).frame(height: textSize.isAccessibilitySize ? 52 : 30, alignment: .top)
      }
      .frame(width: textSize.isAccessibilitySize ? 152 : 96).padding(.vertical, compact ? 10 : 16)
      .background { OnboardingSurface(radius: 18) }
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.Onboarding.moreCurrencies))
    .accessibilityIdentifier("onboarding.destinationsMore")
  }
}
