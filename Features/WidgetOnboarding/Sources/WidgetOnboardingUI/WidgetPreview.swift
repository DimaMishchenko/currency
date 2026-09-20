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

extension WidgetPreviewState {
  /// Every preview family receives the same canonical input; only production layout limits it.
  func entry(synchronized: Bool = false, configuredCodes: [String]? = nil) -> SuiteEntry {
    let selection = configuredCodes ?? input.codes
    var spec = WidgetSpec(
      kind: "preview", codes: selection, amount: input.amount, status: .notDetermined)
    spec.codes = selection
    spec.synchronized = synchronized
    return SuiteEntry(date: .now, spec: spec, input: input, snapshot: snapshot)
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
  let snapshot: RateSnapshot
  let converterInput: ConverterState?
  @State private var localState: WidgetPreviewState
  private let sharedState: Binding<WidgetPreviewState>?
  @Environment(\.colorScheme) private var colorScheme
  init(
    kind: WidgetShowcaseKind, family: WidgetFamily, interactive: Bool = false,
    codes: [String]? = nil, amount: String? = nil, synchronized: Bool = false,
    snapshot: RateSnapshot = WidgetPreviewState.rates, converterInput: ConverterState? = nil,
    state: Binding<WidgetPreviewState>? = nil
  ) {
    self.kind = kind; self.family = family; self.interactive = interactive; self.codes = codes;
    self.amount = amount; self.synchronized = synchronized
    self.snapshot = snapshot; self.converterInput = converterInput
    sharedState = state
    _localState = State(
      initialValue: WidgetPreviewState(kind: kind, snapshot: snapshot, codes: codes, amount: amount)
    )
  }
  private var previewState: Binding<WidgetPreviewState> { sharedState ?? $localState }
  private var entry: SuiteEntry {
    var current = previewState.wrappedValue
    current.update(snapshot: snapshot, codes: codes, amount: amount)
    return current.entry(synchronized: synchronized, configuredCodes: codes)
  }

  private func apply(_ command: WidgetCommand) {
    var current = previewState.wrappedValue
    current.update(snapshot: snapshot, codes: codes, amount: amount)
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
      case .quick:
        QuickRateLayout(
          input: converterInput ?? ConverterState(), snapshot: snapshot, family: family)
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
    .padding(family == .accessoryInline ? 0 : 12)
    .frame(
      width: family.previewSize.width,
      height: calculatorProgress.map { CalculatorPreviewTransition(progress: $0).canvasHeight }
        ?? family.previewSize.height
    )
    .background(
      Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground)
        .opacity(kind == .quick ? 0 : 1),
      in: .rect(cornerRadius: family == .accessoryInline ? 12 : 24)
    )
    .clipShape(.rect(cornerRadius: family == .accessoryInline ? 12 : 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24)
        .strokeBorder(
          .primary.opacity(kind == .quick ? 0 : colorScheme == .dark ? 0.16 : 0.06), lineWidth: 1)
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
      kind == .quick ? natural.width * 1.08 : .infinity)
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
