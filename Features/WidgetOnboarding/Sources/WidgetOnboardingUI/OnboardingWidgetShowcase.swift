import Conversion
import DesignSystem
import ExchangeRates
import ExchangeRatesUI
import SwiftUI
import WidgetKit
import WidgetOnboarding
import Widgets
import WidgetsUI

/// First-launch discovery built from the same layouts used by the widget extension.
/// All preview inputs stay in memory. The host owns onboarding completion persistence.
public struct OnboardingWidgetShowcase: View {
  private let snapshot: RateSnapshot
  private let input: ConverterState
  private let onGuideFinished: () -> Void
  @Binding private var guideRequested: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var page: WidgetShowcaseKind? = .calculator
  private let featured: [WidgetShowcaseKind] = [.calculator, .history, .board]
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
      ScrollView {
        WidgetShowcaseLayout(availableHeight: geometry.size.height) {
          GeometryReader { preview in
            carousel(width: preview.size.width, height: preview.size.height)
          }
          showcaseControls
        }
        .frame(width: geometry.size.width)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollIndicators(.hidden)
    }
    .onChange(of: page) { _, _ in AppHaptics.play(.selection) }
    .navigationDestination(isPresented: $guideRequested) {
      WidgetPresentation {
        WidgetTutorial(kind: selected, family: family, continuation: true) {
          onGuideFinished()
        }
      }
    }
  }

  private var showcaseControls: some View {
    VStack(spacing: AppStyle.Space.small) {
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
      Text(.WidgetOnboarding.moreWidgetsInApp)
        .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center).padding(.horizontal, AppStyle.Space.section)
    }
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
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
    let cardWidth = min(420, max(1, width - 48))
    return ScrollView(.horizontal) {
      HStack(spacing: 0) {
        ForEach(featured) { kind in
          let chosenFamily = family(for: kind)
          let configuration = OnboardingWidgetConfiguration(
            kind: kind, snapshot: snapshot, input: input)
          OnboardingWidgetCard(
            kind: kind, family: chosenFamily, configuration: configuration,
            width: cardWidth, height: height
          )
          .frame(width: width)
          .id(kind)
        }
      }
      .scrollTargetLayout()
    }
    .scrollTargetBehavior(.paging)
    .scrollPosition(id: $page)
    .scrollIndicators(.hidden)
    .frame(height: height)
  }

  @ViewBuilder private var familyControl: some View {
    if selected.families.count > 1 {
      AdaptiveSegmentedPicker(
        .WidgetOnboarding.previewSize,
        choices: selected.families,
        selection: Binding(
          get: { family },
          set: {
            AppHaptics.play(.transition)
            families[selected] = $0
          }),
        optionTitle: { Text($0.showcaseTitle) }
      )
      .frame(maxWidth: 300, minHeight: 44)
      .accessibilityIdentifier("onboarding.widgetFamily")
    } else {
      Color.clear.frame(height: 44).accessibilityHidden(true)
    }
  }

  private var pageControl: some View {
    HStack(spacing: 0) {
      ForEach(featured) { kind in
        Button {
          withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { page = kind }
        } label: {
          Circle()
            .fill(
              selected == kind
                ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.16))
            )
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

private struct WidgetShowcaseLayout: Layout {
  let availableHeight: CGFloat
  private let spacing = AppStyle.Space.medium
  private let bottomInset = AppStyle.Space.section
  private let minimumPreviewHeight: CGFloat = 104
  private let maximumPreviewHeight: CGFloat = 380

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let width = proposal.width ?? 0
    guard subviews.count == 2 else { return CGSize(width: width, height: availableHeight) }
    let controls = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
    return CGSize(
      width: width,
      height: max(availableHeight, minimumPreviewHeight + spacing + controls.height + bottomInset))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard subviews.count == 2 else { return }
    let controls = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
    let previewHeight = min(
      maximumPreviewHeight,
      max(minimumPreviewHeight, bounds.height - spacing - controls.height - bottomInset))
    let topInset = max(
      0, (bounds.height - previewHeight - spacing - controls.height - bottomInset) / 2)
    subviews[0]
      .place(
        at: CGPoint(x: bounds.minX, y: bounds.minY + topInset), anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.width, height: previewHeight))
    subviews[1]
      .place(
        at: CGPoint(x: bounds.minX, y: bounds.minY + topInset + previewHeight + spacing),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.width, height: controls.height))
  }
}

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
      .frame(width: width, height: max(1, height - 16), alignment: .bottom)
      .padding(.bottom, 16)
      .shadow(color: .black.opacity(0.07), radius: 12, y: 7)
      .accessibilityElement(children: kind.interactive ? .contain : .ignore)
      .accessibilityLabel(kind.title)
      .accessibilityValue(configuration.accessibilitySummary(family: family))
      .accessibilityIdentifier("onboarding.preview.\(kind.rawValue)")
  }

  @ViewBuilder private var preview: some View {
    let availableHeight = max(1, height - 16)
    if kind == .calculator {
      let fittedWidth = min(
        width, availableHeight * family.previewSize.width / family.previewSize.height)
      AnimatedCalculatorPreview(
        progress: family == .systemMedium ? 0 : 1, width: fittedWidth,
        codes: configuration.codes, amount: configuration.input.amount,
        snapshot: configuration.snapshot, state: $state
      )
      .animation(
        reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.64), value: family)
    } else if kind == .history {
      let natural = family.previewSize
      let scale = min(width / natural.width, availableHeight / natural.height, 1.08)
      AnimatedHistoryPreview(family: family, canvasWidth: natural.width, scale: scale)
        .animation(
          reduceMotion || scenePhase != .active ? nil : .smooth(duration: 0.55), value: family)
    } else if kind == .board {
      AnimatedWidgetFamilyPreview(
        kind: .board, family: family, maximumWidth: width, availableHeight: availableHeight,
        codes: configuration.codes, amount: configuration.input.amount,
        snapshot: configuration.snapshot, state: $state)
    } else if kind == .icon {
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

extension OnboardingWidgetConfiguration {
  func accessibilitySummary(family: WidgetFamily) -> String {
    let currencies = codes.map { "\(CurrencyDisplay.name($0)), \($0)" }.joined(separator: "; ")
    return "\(family.showcaseTitle). \(currencies)"
  }
}
