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
      .modifier(WidgetContainerBackground())
      .widgetURL(URL(string: "currency://convert"))
  }
}

struct WidgetFooter: View {
  let entry: SuiteEntry

  var body: some View {
    if entry.spec.usesLocation, entry.spec.localIsStale, let code = entry.spec.localCode,
      let destination = URL(string: "currency://local-currency")
    {
      Link(destination: destination) {
        Label {
          HStack(spacing: 0) {
            Text(verbatim: code + " · ")
            Text(.WidgetPresentation.lastKnownLocal)
          }
        } icon: {
          Image(systemName: "location")
        }
        .font(AppStyle.font(.caption2)).foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.7)
      }
      .accessibilityHint(.WidgetPresentation.localOpenApp)
    }

  }
}

struct LocalCurrencySetup: View {
  let status: WidgetLocationStatus
  private var message: LocalizedStringResource {
    switch status {
    case .denied:
      LocalizedStringResource(
        "localDenied", defaultValue: "Location permission is off", table: "WidgetPresentation",
        bundle: .atURL(Bundle.module.bundleURL))
    case .restricted:
      LocalizedStringResource(
        "localRestricted", defaultValue: "Location is restricted", table: "WidgetPresentation",
        bundle: .atURL(Bundle.module.bundleURL))
    case .failed, .available:
      LocalizedStringResource(
        "localFailed", defaultValue: "Unable to load local currency", table: "WidgetPresentation",
        bundle: .atURL(Bundle.module.bundleURL))
    case .notDetermined, .removed:
      LocalizedStringResource(
        "localSetup", defaultValue: "Set up local currency", table: "WidgetPresentation",
        bundle: .atURL(Bundle.module.bundleURL))
    }
  }
  var body: some View {
    if let destination = URL(string: "currency://local-currency") {
      Link(destination: destination) {
        VStack(alignment: .leading, spacing: AppStyle.Space.xxs) {
          Image(systemName: "location")
          Text(message).font(AppStyle.font(.caption2))
          Text(
            LocalizedStringResource(
              "localOpenApp", defaultValue: "Open app", table: "WidgetPresentation",
              bundle: .atURL(Bundle.module.bundleURL))
          )
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
  @Environment(\.isWidgetPreview) private var preview
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(preview && configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .animation(
        preview && !reduceMotion ? .snappy(duration: 0.16) : nil, value: configuration.isPressed)
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
              WidgetPresentationButton(
                command: WidgetCommand(
                  key, spec: spec, activeCurrency: activeCurrency, hiddenCurrency: hiddenCurrency)
              ) {
                Group {
                  if key == "⌫" {
                    Image(systemName: "delete.left")
                  } else {
                    Text(
                      key == "AC"
                        ? "C"
                        : key == "."
                          ? (locale.decimalSeparator ?? ".")
                          : CurrencyDisplay.inputAmount(key, locale: locale))
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
                  ? Text(.WidgetPresentation.clear)
                  : key == "⌫"
                    ? Text(.WidgetPresentation.delete)
                    : key == "." ? Text(.WidgetPresentation.decimalSeparator) : Text(verbatim: key))
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
  var previewSpread: CGFloat? = nil

  private var displayCode: String { WidgetSelection.currency(code) }
  private var selected: Bool { code == entry.input.active }

  var body: some View {
    if code == WidgetSelection.localID {
      LocalCurrencySetup(status: entry.spec.locationStatus)
    } else {
      WidgetPresentationButton(command: WidgetCommand("select:" + code, spec: entry.spec)) {
        CurrencyTileArrangement(
          stacked: previewSpread.map { 1 - $0 } ?? (stacked ? 1 : 0),
          showsCode: showsCode || WidgetSelection.isLocal(code)
        ) {
          CurrencyIcon(displayCode, size: previewSpread.map { 16 + 6 * $0 } ?? (compact ? 16 : 22))
          currencyCode.opacity(showsCode || WidgetSelection.isLocal(code) ? 1 : 0)
          amount.font(AppStyle.font(stacked && !compact ? .title : .title2, weight: .medium))
        }
        .padding(
          .horizontal,
          previewSpread.map { 4 + 4 * $0 } ?? (compact ? AppStyle.Space.xs : AppStyle.Space.small)
        )
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
              ? " · " + String(localized: .WidgetPresentation.localCurrencyChoice) : ""))
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
      .accessibilityHint(.WidgetPresentation.selectCurrencyHint)
      .accessibilityAddTraits(selected ? .isSelected : [])
    }
  }

  private var currencyCode: some View {
    HStack(spacing: AppStyle.Space.xxs) {
      Text(verbatim: displayCode)
      if WidgetSelection.isLocal(code) {
        Image(systemName: "location.fill")
          .accessibilityLabel(.WidgetPresentation.localCurrencyChoice)
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

/// A flag, code, and value keep one identity while a tile changes its arrangement.
private struct CurrencyTileArrangement: Layout {
  var stacked: CGFloat
  let showsCode: Bool
  var animatableData: CGFloat {
    get { stacked }
    set { stacked = newValue }
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard subviews.count == 3 else { return }
    let p = min(1, max(0, stacked))
    let icon = subviews[0].sizeThatFits(.unspecified)
    let code = subviews[1].sizeThatFits(.unspecified)
    let amountWidth = max(0, bounds.width - (icon.width + AppStyle.Space.xs) * (1 - p))
    let value = subviews[2].sizeThatFits(ProposedViewSize(width: amountWidth, height: nil))
    let codeHeight = showsCode ? code.height : 0
    let headerHeight = max(icon.height, codeHeight)
    let stackedTop = (bounds.height - headerHeight - AppStyle.Space.xs - value.height) / 2
    let rowTop = (bounds.height - codeHeight - value.height) / 2
    let iconY = bounds.midY * (1 - p) + (bounds.minY + stackedTop + headerHeight / 2) * p
    let codeY = rowTop * (1 - p) + (stackedTop + (headerHeight - codeHeight) / 2) * p
    let valueY =
      (rowTop + codeHeight) * (1 - p) + (stackedTop + headerHeight + AppStyle.Space.xs) * p
    subviews[0]
      .place(at: CGPoint(x: bounds.minX, y: iconY), anchor: .leading, proposal: .unspecified)
    subviews[1]
      .place(
        at: CGPoint(x: bounds.maxX, y: bounds.minY + codeY), anchor: .topTrailing,
        proposal: .unspecified)
    subviews[2]
      .place(
        at: CGPoint(x: bounds.maxX, y: bounds.minY + valueY), anchor: .topTrailing,
        proposal: ProposedViewSize(width: amountWidth, height: value.height))
  }
}
