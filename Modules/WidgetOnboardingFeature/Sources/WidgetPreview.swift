import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit
import WidgetPresentation

/// Supported choices deliberately match the extension's supportedFamilies declarations.
enum WidgetShowcaseKind: String, CaseIterable, Identifiable {
  case calculator, cash, pocket, mental, board, quick
  var id: Self { self }
  var title: String {
    switch self {
    case .calculator: String(localized: .WidgetOnboarding.widgetCalculatorTitle)
    case .cash: String(localized: .WidgetOnboarding.widgetCashTitle)
    case .pocket: String(localized: .WidgetOnboarding.widgetPocketTitle)
    case .mental: String(localized: .WidgetOnboarding.widgetMentalTitle)
    case .board: String(localized: .WidgetOnboarding.widgetBoardTitle)
    case .quick: String(localized: .WidgetOnboarding.widgetQuickTitle)
    }
  }
  var detail: String {
    switch self {
    case .calculator: String(localized: .WidgetOnboarding.widgetCalculatorDetail)
    case .cash: String(localized: .WidgetOnboarding.widgetCashDetail)
    case .pocket: String(localized: .WidgetOnboarding.widgetPocketDetail)
    case .mental: String(localized: .WidgetOnboarding.widgetMentalDetail)
    case .board: String(localized: .WidgetOnboarding.widgetBoardDetail)
    case .quick: String(localized: .WidgetOnboarding.widgetQuickDetail)
    }
  }
  var families: [WidgetFamily] {
    switch self {
    case .calculator: [.systemMedium, .systemLarge]
    case .cash: [.systemMedium]
    case .pocket, .mental: [.systemSmall]
    case .board: [.systemSmall, .systemMedium, .systemLarge]
    case .quick: [.accessoryRectangular, .accessoryInline]
    }
  }
  var codes: [String] {
    switch self {
    case .calculator: ["EUR", "USD", "GBP", "JPY"]
    case .board:
      ["EUR", "USD", "GBP", "JPY", "CZK", "CHF", "CAD", "AUD", "SEK", "NOK", "PLN", "HUF"]
    case .cash: ["CZK", "EUR"]
    case .pocket: ["EUR", "USD"]
    case .mental: ["EUR", "CZK"]
    case .quick: ["EUR", "USD"]
    }
  }
  var interactive: Bool { self == .calculator || self == .cash }
}

extension WidgetFamily {
  var showcaseTitle: String {
    switch self {
    case .systemSmall: String(localized: .WidgetOnboarding.widgetSizeSmall)
    case .systemMedium: String(localized: .WidgetOnboarding.widgetSizeMedium)
    case .systemLarge: String(localized: .WidgetOnboarding.widgetSizeLarge)
    case .accessoryInline: String(localized: .WidgetOnboarding.widgetSizeInline)
    default: String(localized: .WidgetOnboarding.widgetSizeRectangular)
    }
  }
  var previewSize: CGSize {
    switch self {
    case .systemSmall: CGSize(width: 164, height: 164)
    case .systemLarge: CGSize(width: 348, height: 364)
    case .accessoryInline: CGSize(width: 300, height: 40)
    case .accessoryRectangular: CGSize(width: 170, height: 76)
    default: CGSize(width: 348, height: 164)
    }
  }
}

/// No store, persistence key, or network dependency. Sample rates are explicitly labeled by the host.
struct WidgetPreviewState {
  var input: WidgetInput
  static let rates = RateSnapshot(quotes: [
    "EUR": ExchangeRate(1, published: "", source: .init(provider: .custom("Preview"))),
    "USD": ExchangeRate(1.08, published: "", source: .init(provider: .custom("Preview"))),
    "GBP": ExchangeRate(0.84, published: "", source: .init(provider: .custom("Preview"))),
    "JPY": ExchangeRate(162, published: "", source: .init(provider: .custom("Preview"))),
    "CZK": ExchangeRate(25, published: "", source: .init(provider: .custom("Preview"))),
    "CHF": ExchangeRate(0.96, published: "", source: .init(provider: .custom("Preview"))),
    "CAD": ExchangeRate(1.48, published: "", source: .init(provider: .custom("Preview"))),
    "AUD": ExchangeRate(1.65, published: "", source: .init(provider: .custom("Preview"))),
    "SEK": ExchangeRate(11.4, published: "", source: .init(provider: .custom("Preview"))),
    "NOK": ExchangeRate(11.7, published: "", source: .init(provider: .custom("Preview"))),
    "PLN": ExchangeRate(4.3, published: "", source: .init(provider: .custom("Preview"))),
    "HUF": ExchangeRate(392, published: "", source: .init(provider: .custom("Preview")))
  ])
  init(kind: WidgetShowcaseKind) {
    input = WidgetInput(codes: kind.codes, amount: kind == .cash ? "200" : "100")
  }
  mutating func apply(_ action: WidgetCommand) {
    if let active = action.activeCurrency, input.active == action.hiddenCurrency {
      input.select(active, snapshot: Self.rates)
    }
    if action.command.hasPrefix("select:") {
      input.select(String(action.command.dropFirst(7)), snapshot: Self.rates)
    } else if action.command.hasPrefix("preset:"),
      let amount = WidgetMath.parseAmount(String(action.command.dropFirst(7)))
    {
      input.preset(amount)
    } else {
      input.press(action.command)
    }
  }
}

struct WidgetPreview: View {
  let kind: WidgetShowcaseKind
  let family: WidgetFamily
  var interactive = false
  var codes: [String]? = nil
  var amount: String? = nil
  var synchronized = false
  var calculatorProgress: CGFloat? = nil
  @State private var state: WidgetPreviewState
  init(
    kind: WidgetShowcaseKind, family: WidgetFamily, interactive: Bool = false,
    codes: [String]? = nil, amount: String? = nil, synchronized: Bool = false
  ) {
    self.kind = kind; self.family = family; self.interactive = interactive; self.codes = codes;
    self.amount = amount; self.synchronized = synchronized
    _state = State(initialValue: WidgetPreviewState(kind: kind))
  }
  private var entry: SuiteEntry {
    let selection = codes ?? state.input.codes
    var spec = WidgetSpec(
      kind: "preview", codes: selection, amount: amount ?? state.input.amount,
      status: .notDetermined)
    spec.codes = selection
    spec.synchronized = synchronized
    return SuiteEntry(
      date: .now, spec: spec,
      input: codes == nil
        ? state.input : WidgetInput(codes: selection, amount: amount ?? state.input.amount),
      snapshot: WidgetPreviewState.rates)
  }
  var body: some View {
    Group {
      switch kind {
      case .calculator:
        CalculatorLayout(entry: entry, family: family, previewProgress: calculatorProgress)
      case .cash: CashView(entry: entry)
      case .pocket: AnchorView(entry: entry)
      case .mental: AnchorView(entry: entry, mental: true)
      case .board: BoardLayout(family: family, entry: entry)
      case .quick:
        QuickRateLayout(input: ConverterState(), snapshot: WidgetPreviewState.rates, family: family)
      }
    }
    .environment(\.isWidgetPreview, true)
    .environment(
      \.widgetButtonRenderer,
      WidgetButtonRenderer { command, label in
        if interactive {
          AnyView(
            Button {
              state.apply(command)
            } label: {
              label
            })
        } else {
          label
        }
      }
    )
    .padding(family == .accessoryInline ? 0 : 12)
    .frame(
      width: family.previewSize.width,
      height: calculatorProgress.map { CalculatorPreviewTransition(progress: $0).canvasHeight }
        ?? family.previewSize.height
    )
    .background(
      Color(uiColor: .systemBackground).opacity(kind == .quick ? 0 : 1),
      in: .rect(cornerRadius: family == .accessoryInline ? 12 : 24)
    )
    .clipShape(.rect(cornerRadius: family == .accessoryInline ? 12 : 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(.primary.opacity(kind == .quick ? 0 : 0.06), lineWidth: 0.5)
    }
    .environment(\.openURL, OpenURLAction { _ in .handled })
    .allowsHitTesting(interactive)
  }
}

/// Scales the real fixed widget bounds into an available preview slot without changing its layout.
struct FittedWidgetPreview: View {
  let kind: WidgetShowcaseKind
  let family: WidgetFamily
  var interactive = false
  var codes: [String]? = nil
  var amount: String? = nil
  var synchronized = false
  var body: some View {
    GeometryReader { geometry in
      let scale = min(
        geometry.size.width / family.previewSize.width,
        geometry.size.height / family.previewSize.height)
      WidgetPreview(
        kind: kind, family: family, interactive: interactive, codes: codes, amount: amount,
        synchronized: synchronized
      )
      .scaleEffect(scale)
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .aspectRatio(family.previewSize, contentMode: .fit)
  }
}

/// The calculator's canvas and contents share one interpolated value and one fitting scale.
struct AnimatedCalculatorPreview: View, @preconcurrency Animatable {
  var progress: CGFloat
  let width: CGFloat
  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  var body: some View {
    let height = CalculatorPreviewTransition(progress: progress).canvasHeight
    var preview = WidgetPreview(kind: .calculator, family: .systemMedium, interactive: true)
    preview.calculatorProgress = progress
    return
      preview
      .scaleEffect(width / 348, anchor: .topLeading)
      .frame(width: width, height: height * width / 348, alignment: .topLeading)
      .transaction { $0.animation = nil }
  }
}

/// Changes Board families between two legible states without interpolating incompatible row grids.
struct AnimatedBoardPreview: View {
  let family: WidgetFamily
  let maximumWidth: CGFloat
  let availableHeight: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var displayedFamily: WidgetFamily
  @State private var contentOpacity = 1.0

  init(family: WidgetFamily, maximumWidth: CGFloat, availableHeight: CGFloat) {
    self.family = family
    self.maximumWidth = maximumWidth
    self.availableHeight = availableHeight
    _displayedFamily = State(initialValue: family)
  }

  var body: some View {
    let width =
      displayedFamily == .systemSmall
      ? min(220, maximumWidth)
      : min(
        maximumWidth,
        availableHeight * displayedFamily.previewSize.width / displayedFamily.previewSize.height)
    let height = width * displayedFamily.previewSize.height / displayedFamily.previewSize.width
    RoundedRectangle(cornerRadius: 24 * width / displayedFamily.previewSize.width)
      .fill(Color(uiColor: .systemBackground))
      .overlay {
        WidgetPreview(kind: .board, family: displayedFamily)
          .transaction { $0.animation = nil }
          .scaleEffect(width / displayedFamily.previewSize.width)
          .frame(width: width, height: height)
          .opacity(contentOpacity)
      }
      .frame(width: width, height: height)
      .task(id: Playback(family: family, reduceMotion: reduceMotion)) {
        guard family != displayedFamily else {
          withAnimation(reduceMotion ? nil : .easeIn(duration: 0.15)) { contentOpacity = 1 }
          return
        }
        if reduceMotion {
          displayedFamily = family; contentOpacity = 1
          return
        }
        do {
          withAnimation(.easeOut(duration: 0.12)) { contentOpacity = 0 }
          try await Task.sleep(for: .milliseconds(140))
          withAnimation(.smooth(duration: 0.45)) { displayedFamily = family }
          try await Task.sleep(for: .milliseconds(120))
          withAnimation(.easeIn(duration: 0.25)) { contentOpacity = 1 }
        } catch { return }
      }
  }

  private struct Playback: Equatable {
    let family: WidgetFamily
    let reduceMotion: Bool
  }
}
