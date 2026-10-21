import DesignSystem
import Settings
import SwiftUI

struct SettingsAppIconPicker: View {
  @Bindable var model: SettingsModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .subheadline) private var scaledTileWidth: CGFloat = 96

  private var minimumTileWidth: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? min(300, max(220, scaledTileWidth)) : scaledTileWidth
  }

  var body: some View {
    List {
      ForEach(SettingsAppIconStyle.allCases) { style in
        Section {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumTileWidth), spacing: 16)],
            alignment: .leading, spacing: 20
          ) {
            ForEach(style.icons) { icon in tile(icon) }
          }
          .id(dynamicTypeSize)
          .frame(maxWidth: 656)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, AppStyle.Space.small)
          .buttonStyle(.plain)
        } header: {
          Text(style.pickerTitle)
            .accessibilityIdentifier("settings.appIcon.section.\(style.rawValue)")
        }
      }
      if model.issue == .appIconChangeFailed {
        Section {
          Text(.Settings.appIconChangeFailed)
            .foregroundStyle(.red)
            .accessibilityIdentifier("settings.appIcon.error")
        }
      }
    }
    .navigationTitle(.Settings.appIcon)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func tile(_ icon: SettingsAppIcon) -> some View {
    Button {
      AppHaptics.play(.selection)
      model.selectAppIcon(icon)
    } label: {
      VStack(spacing: AppStyle.Space.small) {
        icon.previewImage
          .resizable()
          .scaledToFit()
          .frame(width: 76, height: 76)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(alignment: .bottomTrailing) {
            if model.pendingAppIcon == icon {
              ProgressView()
                .controlSize(.mini)
                .dynamicTypeSize(.medium)
                .frame(width: 20, height: 20)
                .background(.regularMaterial, in: Circle())
                .offset(x: 5, y: 5)
            } else if model.selectedAppIcon == icon {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBackground), Color.primary)
                .frame(width: 20, height: 20)
                .background(.background, in: Circle())
                .offset(x: 5, y: 5)
            }
          }
          .accessibilityHidden(true)
        Text(icon.currency.pickerTitle)
          .font(AppStyle.font(.subheadline, weight: .medium))
          .foregroundStyle(Color.primary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .top)
      .padding(.vertical, AppStyle.Space.small)
      .contentShape(Rectangle())
    }
    .disabled(model.pendingAppIcon != nil)
    .accessibilityLabel(icon.pickerDescription)
    .accessibilityIdentifier("settings.appIcon.\(icon.rawValue)")
    .accessibilityValue(
      model.pendingAppIcon == icon
        ? Text(.Settings.appIconChanging)
        : model.selectedAppIcon == icon ? Text(.Settings.appIconSelected) : Text("")
    )
    .accessibilityAddTraits(model.selectedAppIcon == icon ? .isSelected : [])
  }
}

extension SettingsAppIcon {
  /// The feature-owned icon preview, resolving its light or dark artwork from the host appearance.
  public var previewImage: Image { Image(previewImageName, bundle: .module) }

  var pickerDescription: Text {
    Text("\(Text(currency.pickerTitle)) · \(Text(style.pickerTitle))")
  }

  var previewImageName: String {
    let family = style == .world ? "AppIconWorld" : "AppIconGrid"
    return currency == .yenYuan ? family : family + currency.rawValue
  }
}

extension SettingsAppIconStyle {
  var pickerTitle: LocalizedStringResource {
    self == .world ? .Settings.appIconWorld : .Settings.appIconGrid
  }
}

extension SettingsAppIconCurrency {
  var pickerTitle: LocalizedStringResource {
    switch self {
    case .yenYuan: .Settings.appIconYenYuan
    case .euro: .Settings.appIconEuro
    case .pound: .Settings.appIconPound
    case .rupee: .Settings.appIconRupee
    case .won: .Settings.appIconWon
    case .bitcoin: .Settings.appIconBitcoin
    }
  }
}
