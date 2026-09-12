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
  private(set) var snapshot: RateSnapshot
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
  init(
    kind: WidgetShowcaseKind, snapshot: RateSnapshot = Self.rates,
    codes: [String]? = nil, amount: String? = nil
  ) {
    self.snapshot = snapshot
    input = WidgetInput(
      codes: codes ?? kind.codes, amount: amount ?? (kind == .cash ? "200" : "100"))
  }
  /// External coverage changes do not replay a user's temporary keypad or tile interaction.
  mutating func update(snapshot: RateSnapshot, codes: [String]?, amount: String?) {
    self.snapshot = snapshot
    if let codes { input.reconcile(codes: codes) }
    if input.editedAt == nil, let amount, input.amount != amount {
      input = WidgetInput(codes: input.codes, amount: amount)
    }
  }

  /// Every preview family receives the same canonical input; only production layout limits it.
  func entry(synchronized: Bool = false, configuredCodes: [String]? = nil) -> SuiteEntry {
    let selection = configuredCodes ?? input.codes
    var spec = WidgetSpec(
      kind: "preview", codes: selection, amount: input.amount, status: .notDetermined)
    spec.codes = selection
    spec.synchronized = synchronized
    return SuiteEntry(date: .now, spec: spec, input: input, snapshot: snapshot)
  }

  mutating func apply(_ action: WidgetCommand) {
    if let active = action.activeCurrency, input.active == action.hiddenCurrency {
      input.select(active, snapshot: snapshot)
    }
    if action.command.hasPrefix("select:") {
      input.select(String(action.command.dropFirst(7)), snapshot: snapshot)
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
  let snapshot: RateSnapshot
  let converterInput: ConverterState?
  @State private var localState: WidgetPreviewState
  private let sharedState: Binding<WidgetPreviewState>?
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

/// The calculator's compatible four-tile canvas shares one progress value and fitting scale.
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
    let atLargeEndpoint = progress >= 0.9999
    var preview = WidgetPreview(
      kind: .calculator, family: atLargeEndpoint ? .systemLarge : .systemMedium, interactive: true,
      codes: codes, amount: amount, snapshot: snapshot, state: state)
    // At rest use the exact production family, including its footer and full visible capacity.
    preview.calculatorProgress = progress > 0.0001 && !atLargeEndpoint ? progress : nil
    return
      preview
      .scaleEffect(width / 348, anchor: .topLeading)
      .frame(width: width, height: height * width / 348, alignment: .topLeading)
      .transaction { $0.animation = nil }
  }
}

/// A brief content fade covers incompatible grids while the outer widget surface resizes smoothly.
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
  @State private var displayedFamily: WidgetFamily?
  @State private var contentOpacity = 1.0

  private var visibleFamily: WidgetFamily { displayedFamily ?? family }

  var body: some View {
    let natural = visibleFamily.previewSize
    let width = min(
      visibleFamily == .systemSmall ? min(220, maximumWidth) : maximumWidth,
      availableHeight * natural.width / natural.height,
      kind == .quick ? natural.width * 1.08 : .infinity)
    let height = width * natural.height / natural.width
    RoundedRectangle(cornerRadius: 24 * width / natural.width)
      .fill(kind == .quick ? Color.clear : Color(uiColor: .systemBackground))
      .frame(width: width, height: height)
      .overlay {
        GeometryReader { geometry in
          WidgetPreview(
            kind: kind, family: visibleFamily, interactive: kind.interactive,
            codes: codes, amount: amount, snapshot: snapshot, converterInput: converterInput,
            state: state
          )
          .transaction { $0.animation = nil }
          .scaleEffect(geometry.size.width / natural.width, anchor: .topLeading)
          .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
          .opacity(contentOpacity)
        }
      }
      .clipShape(.rect(cornerRadius: 24 * width / natural.width))
      .task(id: Playback(family: family, reduceMotion: reduceMotion, active: scenePhase == .active))
    {
      guard let displayedFamily else { self.displayedFamily = family; return }
      guard family != displayedFamily else {
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.15)) { contentOpacity = 1 }
        return
      }
      guard scenePhase == .active else { return }
      if reduceMotion {
        self.displayedFamily = family; contentOpacity = 1
        return
      }
      do {
        withAnimation(.easeOut(duration: 0.10)) { contentOpacity = 0 }
        try await Task.sleep(for: .milliseconds(120))
        withAnimation(.smooth(duration: 0.42)) { self.displayedFamily = family }
        try await Task.sleep(for: .milliseconds(100))
        withAnimation(.easeIn(duration: 0.24)) { contentOpacity = 1 }
      } catch { return }
    }
  }

  private struct Playback: Equatable {
    let family: WidgetFamily
    let reduceMotion: Bool
    let active: Bool
  }
}
