import CurrencySupport
import SwiftUI

/// A destination choice in the onboarding carousel.
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
      VStack(spacing: 8) {
        if compact {
          HStack(spacing: 6) {
            CurrencyIcon(code, size: 22)
            Text(code).font(AppStyle.font(.subheadline, weight: .semibold))
          }
          .padding(.top, 8)
        } else {
          CurrencyIcon(code, size: 30).frame(height: 36)
          Text(code).font(AppStyle.font(.headline))
        }
        Text(
          available
            ? CurrencyDisplay.name(code, locale: locale)
            : String(localized: .Onboarding.unavailable)
        )
        .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
        .lineLimit(2).frame(height: textSize.isAccessibilitySize ? 52 : 30, alignment: .top)
      }
      .frame(width: textSize.isAccessibilitySize ? 152 : 96).padding(.vertical, 16)
      .background(
        Color(uiColor: .secondarySystemBackground).opacity(selected ? 0.9 : 0.6),
        in: .rect(cornerRadius: 18)
      )
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

/// A shared selected state; unselected choices keep their content uncluttered.
struct OnboardingSelectionMark: View {
  var body: some View {
    Image(systemName: "checkmark.circle.fill")
      .font(.system(size: 17)).foregroundStyle(.primary)
      .accessibilityHidden(true)
  }
}

/// Opens the same destination picker as toolbar Search, using the carousel's card geometry.
struct OnboardingMoreCurrenciesTile: View {
  let compact: Bool
  let action: () -> Void
  @Environment(\.dynamicTypeSize) private var textSize

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        if compact {
          HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 20))
              .frame(width: 22, height: 22)
            Text(.Onboarding.more).font(AppStyle.font(.subheadline, weight: .semibold))
          }
          .padding(.top, 8)
        } else {
          Image(systemName: "magnifyingglass").font(.system(size: 24)).frame(height: 36)
          Text(.Onboarding.more).font(AppStyle.font(.headline))
        }
        Text(.Onboarding.fiat)
          .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
          .lineLimit(2).frame(height: textSize.isAccessibilitySize ? 52 : 30, alignment: .top)
      }
      .frame(width: textSize.isAccessibilitySize ? 152 : 96).padding(.vertical, 16)
      .background(
        Color(uiColor: .secondarySystemBackground).opacity(0.6), in: .rect(cornerRadius: 18)
      )
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.Onboarding.moreCurrencies))
    .accessibilityIdentifier("onboarding.destinationsMore")
  }
}
