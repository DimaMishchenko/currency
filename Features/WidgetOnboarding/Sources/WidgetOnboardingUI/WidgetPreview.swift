import Conversion
import DesignSystem
import ExchangeRates
import ExchangeRatesUI
import SwiftUI
import WidgetKit
import WidgetOnboarding
import Widgets
import WidgetsUI

extension WidgetShowcaseKind {
  var title: String {
    switch self {
    case .calculator: String(localized: .WidgetOnboarding.widgetCalculatorTitle)
    case .cash: String(localized: .WidgetOnboarding.widgetCashTitle)
    case .pocket: String(localized: .WidgetOnboarding.widgetPocketTitle)
    case .mental: String(localized: .WidgetOnboarding.widgetMentalTitle)
    case .board: String(localized: .WidgetOnboarding.widgetBoardTitle)
    case .icon: String(localized: .WidgetOnboarding.widgetQuickTitle)
    }
  }
  var detail: String {
    switch self {
    case .calculator: String(localized: .WidgetOnboarding.widgetCalculatorDetail)
    case .cash: String(localized: .WidgetOnboarding.widgetCashDetail)
    case .pocket: String(localized: .WidgetOnboarding.widgetPocketDetail)
    case .mental: String(localized: .WidgetOnboarding.widgetMentalDetail)
    case .board: String(localized: .WidgetOnboarding.widgetBoardDetail)
    case .icon: String(localized: .WidgetOnboarding.widgetQuickDetail)
    }
  }
  var families: [WidgetFamily] {
    switch self {
    case .calculator: [.systemMedium, .systemLarge]
    case .cash: [.systemMedium]
    case .pocket, .mental: [.systemSmall]
    case .board: [.systemSmall, .systemMedium, .systemLarge]
    case .icon: [.accessoryCircular]
    }
  }
}

extension WidgetFamily {
  var showcaseTitle: String {
    switch self {
    case .systemSmall: String(localized: .WidgetOnboarding.widgetSizeSmall)
    case .systemMedium: String(localized: .WidgetOnboarding.widgetSizeMedium)
    case .systemLarge: String(localized: .WidgetOnboarding.widgetSizeLarge)
    case .accessoryCircular: "Circular"
    case .accessoryInline: String(localized: .WidgetOnboarding.widgetSizeInline)
    default: String(localized: .WidgetOnboarding.widgetSizeRectangular)
    }
  }
  var previewSize: CGSize {
    switch self {
    case .systemSmall: CGSize(width: 164, height: 164)
    case .systemLarge: CGSize(width: 348, height: 364)
    case .accessoryCircular: CGSize(width: 76, height: 76)
    case .accessoryInline: CGSize(width: 300, height: 40)
    case .accessoryRectangular: CGSize(width: 170, height: 76)
    default: CGSize(width: 348, height: 164)
    }
  }
}

extension WidgetPreviewState {
  static var sampleLocalCurrencyCode: String { "CZK" }

  /// Every preview family receives the same canonical input; only production layout limits it.
  func entry(
    synchronized: Bool = false, configuredCodes: [String]? = nil, sampleLocation: Bool = false
  ) -> SuiteEntry {
    let selection = configuredCodes ?? input.codes
    var spec = WidgetSpec(
      kind: "preview", codes: selection, amount: input.amount,
      location: sampleLocation ? .init(country: "CZ", currency: Self.sampleLocalCurrencyCode) : nil,
      status: sampleLocation ? .available : .notDetermined)
    spec.synchronized = synchronized
    var resolvedInput = input
    if input.active == WidgetSelection.localID, spec.localCode != nil {
      resolvedInput = WidgetInput(codes: spec.codes, amount: input.amount)
    } else {
      resolvedInput.reconcile(codes: spec.codes)
    }
    return SuiteEntry(date: .now, spec: spec, input: resolvedInput, snapshot: snapshot)
  }

}

struct WidgetPreview: View {
  let kind: WidgetShowcaseKind
  let family: WidgetFamily
  var symbol: CurrencySymbol = .dollar
  var interactive = false
  var codes: [String]? = nil
  var amount: String? = nil
  var synchronized = false
  var calculatorProgress: CGFloat? = nil
  let snapshot: RateSnapshot
  let converterInput: ConverterState?
  @State private var localState: WidgetPreviewState
  private let sharedState: Binding<WidgetPreviewState>?
  @Environment(\.colorScheme) private var colorScheme
  init(
    kind: WidgetShowcaseKind, family: WidgetFamily, interactive: Bool = false,
    codes: [String]? = nil, amount: String? = nil, synchronized: Bool = false,
    snapshot: RateSnapshot = WidgetPreviewState.rates, converterInput: ConverterState? = nil,
    state: Binding<WidgetPreviewState>? = nil, symbol: CurrencySymbol = .dollar
  ) {
    self.symbol = symbol
    self.kind = kind; self.family = family; self.interactive = interactive; self.codes = codes;
    self.amount = amount; self.synchronized = synchronized
    self.snapshot = snapshot; self.converterInput = converterInput
    sharedState = state
    _localState = State(
      initialValue: WidgetPreviewState(kind: kind, snapshot: snapshot, codes: codes, amount: amount)
    )
  }
  private var previewState: Binding<WidgetPreviewState> { sharedState ?? $localState }
  private func currentState() -> WidgetPreviewState {
    var current = previewState.wrappedValue
    // Resolve the demo list before updating state so Local tile/keypad edits keep their identity.
    let projected = current.entry(
      synchronized: synchronized, configuredCodes: codes, sampleLocation: converterInput == nil)
    current.input = projected.input
    current.update(snapshot: snapshot, codes: projected.spec.codes, amount: amount)
    return current
  }
  private var entry: SuiteEntry {
    currentState()
      .entry(
        synchronized: synchronized, configuredCodes: codes, sampleLocation: converterInput == nil)
  }

  private func apply(_ command: WidgetCommand) {
    var current = currentState()
    AppHaptics.play(.selection)
    current.apply(command)
    previewState.wrappedValue = current
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
      case .icon:
        CurrencySymbolLayout(symbol: symbol)
      }
    }
    .environment(\.isWidgetPreview, true)
    .environment(
      \.widgetButtonRenderer,
      WidgetButtonRenderer { command, label in
        if interactive {
          AnyView(
            Button {
              apply(command)
            } label: {
              label
            })
        } else {
          label
        }
      }
    )
    .padding(kind == .icon || family == .accessoryInline ? 0 : 12)
    .frame(
      width: family.previewSize.width,
      height: calculatorProgress.map { CalculatorPreviewTransition(progress: $0).canvasHeight }
        ?? family.previewSize.height
    )
    .background(
      Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground)
        .opacity(kind == .icon ? 0 : 1),
      in: .rect(cornerRadius: family == .accessoryInline ? 12 : 24)
    )
    .clipShape(.rect(cornerRadius: family == .accessoryInline ? 12 : 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(
          .primary.opacity(kind == .icon ? 0 : colorScheme == .dark ? 0.16 : 0.06), lineWidth: 1)
    }
    .environment(\.openURL, OpenURLAction { _ in .handled })
    .allowsHitTesting(interactive)
  }
}

/// Scales the real fixed widget bounds into an available preview slot without changing its layout.
struct FittedWidgetPreview: View {
  let kind: WidgetShowcaseKind
  let family: WidgetFamily
  var symbol: CurrencySymbol = .dollar
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
        synchronized: synchronized, symbol: symbol
      )
      .scaleEffect(scale)
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .aspectRatio(family.previewSize, contentMode: .fit)
  }
}

/// One progress value resizes the calculator and repositions its persistent currency cells.
struct AnimatedCalculatorPreview: View, @preconcurrency Animatable {
  var progress: CGFloat
  var width: CGFloat
  var codes: [String]? = nil
  var amount: String? = nil
  var snapshot = WidgetPreviewState.rates
  var state: Binding<WidgetPreviewState>? = nil

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(progress, width) }
    set { progress = newValue.first; width = newValue.second }
  }

  var body: some View {
    let height = CalculatorPreviewTransition(progress: progress).canvasHeight
    let atMediumEndpoint = progress <= 0.0001
    var preview = WidgetPreview(
      kind: .calculator, family: atMediumEndpoint ? .systemMedium : .systemLarge, interactive: true,
      codes: codes, amount: amount, snapshot: snapshot, state: state)
    // Keep the same cell tree at both endpoints and throughout the interpolation.
    preview.calculatorProgress = progress
    return
      preview
      .scaleEffect(width / 348, anchor: .topLeading)
      .frame(width: width, height: height * width / 348, alignment: .topLeading)
      .transaction {
        $0.animation = nil; $0.disablesAnimations = true
      }
  }
}

/// One live preview retains its input while the widget surface and production layout resize.
struct AnimatedWidgetFamilyPreview: View {
  let kind: WidgetShowcaseKind
  let family: WidgetFamily
  let maximumWidth: CGFloat
  let availableHeight: CGFloat
  var codes: [String]? = nil
  var amount: String? = nil
  var snapshot = WidgetPreviewState.rates
  var converterInput: ConverterState? = nil
  var state: Binding<WidgetPreviewState>? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    let natural = family.previewSize
    let width = min(
      family == .systemSmall ? min(220, maximumWidth) : maximumWidth,
      availableHeight * natural.width / natural.height,
      kind == .icon ? natural.width * 1.08 : .infinity)
    WidgetPreview(
      kind: kind, family: family, interactive: kind.interactive,
      codes: codes, amount: amount, snapshot: snapshot, converterInput: converterInput,
      state: state
    )
    .scaleEffect(width / natural.width)
    .frame(width: width, height: width * natural.height / natural.width)
    .animation(
      reduceMotion || scenePhase != .active ? nil : .smooth(duration: 0.55), value: family)
  }
}
