import CurrencySupport
import SwiftUI
import WidgetKit

struct WidgetSurface: ViewModifier {
  func body(content: Content) -> some View {
    content
      // Fixed widget bounds cannot accommodate unbounded text growth; VoiceOver retains full values.
      .dynamicTypeSize(...DynamicTypeSize.large)
      .font(AppStyle.font(.caption))
      .tint(Color(uiColor: .label))
      .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
      .widgetURL(URL(string: "currency://convert"))
  }
}

struct WidgetFooter: View {
  let entry: SuiteEntry

  var body: some View {
    if entry.spec.usesLocation, entry.spec.localIsStale, let code = entry.spec.localCode {
      Link(destination: URL(string: "currency://local-currency")!) {
        Label {
          HStack(spacing: 0) {
            Text(verbatim: code + " · ")
            Text(.Widgets.lastKnownLocal)
          }
        } icon: {
          Image(systemName: "location")
        }
        .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.7)
      }
      .accessibilityHint(.Widgets.localOpenApp)
    }

  }
}

struct LocalCurrencySetup: View {
  let status: WidgetLocationStatus
  private var message: LocalizedStringResource {
    switch status {
    case .denied:
      LocalizedStringResource(
        "localDenied", defaultValue: "Location permission is off", table: "Widgets")
    case .restricted:
      LocalizedStringResource(
        "localRestricted", defaultValue: "Location is restricted", table: "Widgets")
    case .failed, .available:
      LocalizedStringResource(
        "localFailed", defaultValue: "Unable to load local currency", table: "Widgets")
    case .notDetermined, .removed:
      LocalizedStringResource("localSetup", defaultValue: "Set up local currency", table: "Widgets")
    }
  }
  var body: some View {
    Link(destination: URL(string: "currency://local-currency")!) {
      VStack(alignment: .leading, spacing: AppStyle.Space.xxs) {
        Image(systemName: "location")
        Text(message).font(AppStyle.font(.caption2))
        Text(LocalizedStringResource("localOpenApp", defaultValue: "Open app", table: "Widgets"))
          .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding(AppStyle.Space.xs)
      .multilineTextAlignment(.leading)
      .foregroundStyle(.primary)
      .background {
        OpaquePermissionBackground()
          .clipShape(.rect(cornerRadius: AppStyle.Widget.keyRadius))
      }
    }
  }
}

/// A full-color raster fill remains opaque when the Home Screen applies accented/clear rendering.
private struct OpaquePermissionBackground: View {
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.colorScheme) private var colorScheme
  private static func image(_ color: UIColor) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format)
      .image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
      }
  }
  private static let light = image(UIColor(white: 0.95, alpha: 1))
  private static let dark = image(UIColor(white: 0.12, alpha: 1))
  var body: some View {
    Image(uiImage: renderingMode == .accented || colorScheme == .dark ? Self.dark : Self.light)
      .resizable().widgetAccentedRenderingMode(.fullColor)
      .accessibilityHidden(true)
  }
}

/// Interactive widgets show the committed selection; pressing must not fade the whole label.
struct WidgetButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
  }
}

struct WidgetKeypad: View {
  @Environment(\.locale) private var locale
  let spec: WidgetSpec
  var activeCurrency: String? = nil
  var hiddenCurrency: String? = nil

  var body: some View {
    GeometryReader { geometry in
      let cell = max(0, (geometry.size.width - AppStyle.Space.xs * 3) / 4)
      VStack(spacing: AppStyle.Space.xs) {
        ForEach(
          [["7", "8", "9", "⌫"], ["4", "5", "6", "AC"], ["1", "2", "3", "000"], [".", "0", "00"]],
          id: \.self
        ) { row in
          HStack(spacing: AppStyle.Space.xs) {
            ForEach(row, id: \.self) { key in
              Button(
                intent: WidgetAction(
                  key, spec: spec, activeCurrency: activeCurrency, hiddenCurrency: hiddenCurrency)
              ) {
                Group {
                  if key == "⌫" {
                    Image(systemName: "delete.left")
                  } else {
                    Text(key == "AC" ? "C" : CurrencyDisplay.inputAmount(key, locale: locale))
                  }
                }
                .font(
                  AppStyle.font(
                    key.count > 1 && key != "AC" ? .subheadline : .title3, weight: .medium)
                )
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: key == "0" ? cell * 2 + AppStyle.Space.xs : cell)
                .frame(maxHeight: .infinity)
                .background(
                  .primary.opacity(AppStyle.Widget.keyFill),
                  in: .rect(cornerRadius: AppStyle.Widget.keyRadius)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: AppStyle.Widget.keyRadius)
                    .strokeBorder(.primary.opacity(AppStyle.Widget.keyBorder), lineWidth: 1)
                }
                .contentShape(.rect)
              }
              .accessibilityLabel(
                key == "AC"
                  ? Text(.Widgets.clear)
                  : key == "⌫"
                    ? Text(.Widgets.delete)
                    : key == "." ? Text(.Widgets.decimalSeparator) : Text(verbatim: key))
            }
          }
        }
      }
      .buttonStyle(WidgetButtonStyle())
    }
  }
}

struct CurrencyTile: View {
  @Environment(\.locale) private var locale
  let entry: SuiteEntry
  let code: String
  var compact = false
  var stacked = false
  var showsCode = true

  private var displayCode: String { WidgetSelection.currency(code) }
  private var selected: Bool { code == entry.input.active }

  var body: some View {
    if code == WidgetSelection.localID {
      LocalCurrencySetup(status: entry.spec.locationStatus)
    } else {
      Button(intent: WidgetAction("select:" + code, spec: entry.spec)) {
        Group {
          if stacked {
            VStack(alignment: .trailing, spacing: AppStyle.Space.xs) {
              HStack(spacing: AppStyle.Space.xxs) {
                CurrencyIcon(displayCode, size: compact ? 16 : 22)
                Spacer(minLength: 0)
                currencyCode
              }
              amount.font(AppStyle.font(compact ? .title2 : .title, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, AppStyle.Space.xs)
          } else {
            HStack(spacing: AppStyle.Space.xs) {
              CurrencyIcon(displayCode, size: compact ? 16 : 22)
              Spacer(minLength: 0)
              VStack(alignment: .trailing, spacing: 0) {
                if showsCode || WidgetSelection.isLocal(code) { currencyCode }
                amount.font(AppStyle.font(.title2, weight: .medium))
              }
            }
          }
        }
        .padding(.horizontal, compact ? AppStyle.Space.xs : AppStyle.Space.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          .primary.opacity(selected ? AppStyle.Widget.selectedFill : AppStyle.Widget.tileFill),
          in: .rect(cornerRadius: compact ? AppStyle.Widget.keyRadius : AppStyle.Widget.tileRadius)
        )
        .overlay {
          RoundedRectangle(
            cornerRadius: compact ? AppStyle.Widget.keyRadius : AppStyle.Widget.tileRadius
          )
          .strokeBorder(
            .primary.opacity(selected ? AppStyle.Widget.selectedBorder : 0), lineWidth: 1.2)
        }
        .contentShape(.rect)
      }
      .buttonStyle(WidgetButtonStyle())
      .accessibilityLabel(
        Text(
          verbatim: "\(CurrencyDisplay.name(displayCode)), \(displayCode)"
            + (WidgetSelection.isLocal(code)
              ? " · " + String(localized: .Widgets.localCurrencyChoice) : ""))
      )
      .accessibilityValue(
        selected
          ? CurrencyDisplay.inputAmount(entry.input.amount, locale: locale)
          : CurrencyDisplay.format(
            entry.snapshot.convert(
              entry.input.decimal, from: WidgetSelection.currency(entry.input.active),
              to: displayCode),
            code: displayCode, locale: locale)
      )
      .accessibilityHint(.Widgets.selectCurrencyHint)
      .accessibilityAddTraits(selected ? .isSelected : [])
    }
  }

  private var currencyCode: some View {
    HStack(spacing: AppStyle.Space.xxs) {
      Text(verbatim: displayCode)
      if WidgetSelection.isLocal(code) {
        Image(systemName: "location.fill").accessibilityLabel(.Widgets.localCurrencyChoice)
      }
    }
    .font(AppStyle.font(.caption2, weight: .medium))
  }

  private var amount: some View {
    Text(
      selected
        ? (entry.input.replacesOnDigit
          ? CurrencyDisplay.format(entry.input.decimal, code: displayCode, locale: locale)
          : CurrencyDisplay.inputAmount(entry.input.amount, locale: locale))
        : CurrencyDisplay.format(
          entry.snapshot.convert(
            entry.input.decimal, from: WidgetSelection.currency(entry.input.active), to: displayCode
          ),
          code: displayCode, locale: locale)
    )
    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
    .contentTransition(.identity)
  }
}
