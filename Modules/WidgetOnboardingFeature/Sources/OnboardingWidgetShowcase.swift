import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

/// First-launch discovery built from the same layouts used by the widget extension.
/// All preview inputs stay in memory. The host owns onboarding completion persistence.
public struct OnboardingWidgetShowcase: View {
  private let snapshot: RateSnapshot
  private let input: ConverterState
  private let onGuideFinished: () -> Void
  @Binding private var guideRequested: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var page: WidgetShowcaseKind? = .calculator
  @State private var families: [WidgetShowcaseKind: WidgetFamily] = [:]

  /// Creates a personalized showcase and continues into the installation guide when requested.
  /// Only the guide's final action invokes completion; Back returns to this showcase.
  public init(
    snapshot: RateSnapshot, input: ConverterState, guideRequested: Binding<Bool>,
    onGuideFinished: @escaping () -> Void
  ) {
    self.snapshot = snapshot
    self.input = input
    _guideRequested = guideRequested
    self.onGuideFinished = onGuideFinished
  }

  private var selected: WidgetShowcaseKind { page ?? .calculator }
  private var family: WidgetFamily { family(for: selected) }

  /// A paging showcase with family controls and an installation guide in the same navigation stack.
  public var body: some View {
    GeometryReader { geometry in
      let accessible = textSize.isAccessibilitySize
      let heroHeight = max(156, geometry.size.height - (accessible ? 260 : 174))
      VStack(spacing: AppStyle.Space.medium) {
        carousel(width: geometry.size.width, height: heroHeight)
        VStack(spacing: AppStyle.Space.xs) {
          Text(selected.title)
            .font(AppStyle.font(.headline)).accessibilityAddTraits(.isHeader)
          Text(interactionDetail)
            .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if OnboardingWidgetConfiguration(kind: selected, snapshot: snapshot, input: input)
            .isSample
          {
            Text(.WidgetOnboarding.previewSampleRates)
              .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          }
        }
        .multilineTextAlignment(.center).padding(.horizontal, AppStyle.Space.section)
        familyControl
          .padding(.horizontal, AppStyle.Space.section)
        pageControl
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .navigationDestination(isPresented: $guideRequested) {
      WidgetTutorial(kind: selected, family: family, continuation: true) {
        guideRequested = false
        onGuideFinished()
      }
    }
  }

  private var interactionDetail: String {
    switch selected {
    case .calculator: String(localized: .WidgetOnboarding.previewCalculatorHint)
    case .cash: String(localized: .WidgetOnboarding.previewCashHint)
    default: selected.detail
    }
  }

  private func family(for kind: WidgetShowcaseKind) -> WidgetFamily {
    families[kind].flatMap { kind.families.contains($0) ? $0 : nil } ?? kind.families[0]
  }

  private func carousel(width: CGFloat, height: CGFloat) -> some View {
    let cardWidth = min(420, max(240, width - 64))
    return ScrollView(.horizontal) {
      HStack(spacing: AppStyle.Space.large) {
        ForEach(WidgetShowcaseKind.allCases) { kind in
          let chosenFamily = family(for: kind)
          let configuration = OnboardingWidgetConfiguration(
            kind: kind, snapshot: snapshot, input: input)
          OnboardingWidgetCard(
            kind: kind, family: chosenFamily, configuration: configuration,
            width: cardWidth, height: height
          )
          .id(kind)
        }
      }
      .scrollTargetLayout()
    }
    .contentMargins(.horizontal, (width - cardWidth) / 2, for: .scrollContent)
    .scrollTargetBehavior(.viewAligned)
    .scrollPosition(id: $page)
    .scrollIndicators(.hidden)
    .frame(height: height)
  }

  @ViewBuilder private var familyControl: some View {
    if selected.families.count > 1 {
      Picker(
        .WidgetOnboarding.previewSize,
        selection: Binding(get: { family }, set: { families[selected] = $0 })
      ) {
        ForEach(selected.families, id: \.self) { choice in
          Text(choice.showcaseTitle).tag(choice)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 300, minHeight: 44)
      .accessibilityIdentifier("onboarding.widgetFamily")
    } else {
      // Reserve the control row so paging between widgets keeps the composition stable.
      Color.clear.frame(height: 44).accessibilityHidden(true)
    }
  }

  private var pageControl: some View {
    HStack(spacing: 0) {
      ForEach(WidgetShowcaseKind.allCases) { kind in
        Button {
          withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { page = kind }
        } label: {
          Circle().fill(.primary.opacity(selected == kind ? 0.8 : 0.16))
            .frame(width: 6, height: 6).frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(selected == kind ? .isSelected : [])
        .accessibilityIdentifier("onboarding.widget.\(kind.rawValue)")
      }
    }
  }
}

/// Keeps one isolated editor alive while the same widget changes family or rate coverage.
private struct OnboardingWidgetCard: View {
  let kind: WidgetShowcaseKind
  let family: WidgetFamily
  let configuration: OnboardingWidgetConfiguration
  let width: CGFloat
  let height: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var state: WidgetPreviewState

  init(
    kind: WidgetShowcaseKind, family: WidgetFamily, configuration: OnboardingWidgetConfiguration,
    width: CGFloat, height: CGFloat
  ) {
    self.kind = kind
    self.family = family
    self.configuration = configuration
    self.width = width
    self.height = height
    _state = State(
      initialValue: WidgetPreviewState(
        kind: kind, snapshot: configuration.snapshot, codes: configuration.codes,
        amount: configuration.input.amount))
  }

  var body: some View {
    preview
      .frame(width: width, height: max(120, height - 16), alignment: .bottom)
      .padding(.bottom, 16)
      .shadow(color: .black.opacity(0.07), radius: 12, y: 7)
      .accessibilityElement(children: kind.interactive ? .contain : .ignore)
      .accessibilityLabel(kind.title)
      .accessibilityValue(configuration.accessibilitySummary(family: family))
      .accessibilityIdentifier("onboarding.preview.\(kind.rawValue)")
  }

  @ViewBuilder private var preview: some View {
    let availableHeight = max(120, height - 16)
    if kind == .calculator && configuration.codes.count == 4 {
      let fittedWidth = min(
        width, availableHeight * family.previewSize.width / family.previewSize.height)
      AnimatedCalculatorPreview(
        progress: family == .systemMedium ? 0 : 1, width: fittedWidth,
        codes: configuration.codes, amount: configuration.input.amount,
        snapshot: configuration.snapshot, state: $state
      )
      .animation(
        reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.64), value: family)
    } else if kind == .board {
      AnimatedWidgetFamilyPreview(
        kind: .board, family: family, maximumWidth: width, availableHeight: availableHeight,
        codes: configuration.codes, amount: configuration.input.amount,
        snapshot: configuration.snapshot, state: $state)
    } else if kind == .calculator || kind == .quick {
      // Two/eight-tile Calculator grids and accessory layouts are incompatible geometries.
      // A short content fade retains their real endpoints without inventing a tile morph.
      AnimatedWidgetFamilyPreview(
        kind: kind, family: family, maximumWidth: width, availableHeight: availableHeight,
        codes: configuration.codes, amount: configuration.input.amount,
        snapshot: configuration.snapshot, converterInput: configuration.input, state: $state)
    } else {
      let natural = family.previewSize
      let scale = min(width / natural.width, availableHeight / natural.height, 1.08)
      WidgetPreview(
        kind: kind, family: family, interactive: kind.interactive, codes: configuration.codes,
        amount: configuration.input.amount, snapshot: configuration.snapshot,
        converterInput: configuration.input, state: $state
      )
      .scaleEffect(scale)
      .frame(width: natural.width * scale, height: natural.height * scale)
    }
  }
}

/// A pure projection of saved app choices. Missing rates never become made-up preview values.
struct OnboardingWidgetConfiguration {
  let snapshot: RateSnapshot
  let input: ConverterState
  let codes: [String]
  let isSample: Bool

  init(kind: WidgetShowcaseKind, snapshot: RateSnapshot, input: ConverterState) {
    let destinations = input.destinations.filter {
      guard let value = snapshot.convert(1, from: input.source, to: $0) else { return false }
      return value > 0 && !value.isNaN
    }
    let compatible = kind == .cash ? destinations.filter(WidgetPresets.allows) : destinations
    // Cash models banknotes and metal weights, so cryptocurrency pairs need an honest demo.
    isSample = kind == .cash && (!WidgetPresets.allows(input.source) || compatible.isEmpty)
    self.snapshot = isSample ? WidgetPreviewState.rates : snapshot
    var previewInput = input
    if isSample {
      previewInput = ConverterState()
      previewInput.changeSource(kind.codes[0])
      previewInput.setDestinations(Array(kind.codes.dropFirst()))
      previewInput.setAmount("100")
    } else {
      previewInput.setDestinations(compatible)
    }
    self.input = previewInput
    switch kind {
    case .calculator, .board:
      codes = [previewInput.source] + previewInput.destinations
    default:
      codes = [previewInput.source] + Array(previewInput.destinations.prefix(1))
    }
  }

  func accessibilitySummary(family: WidgetFamily) -> String {
    // Cash, Pocket and Mental use their own reference amounts and approximation rules.
    // Announce the configuration without claiming the app's amount is shown by every layout.
    let currencies = codes.map { "\(CurrencyDisplay.name($0)), \($0)" }.joined(separator: "; ")
    return "\(family.showcaseTitle). \(currencies)"
  }
}
