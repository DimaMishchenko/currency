import CurrencySupport
import ExchangeRates
import SwiftUI

/// First-launch presentation. The app supplies widget discovery, keeping feature dependencies separate.
struct OnboardingScreen<Widgets: View>: View {
  private let model: OnboardingModel
  private let widgets:
    (OnboardingModel.Step, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void) ->
      Widgets
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.dynamicTypeSize) private var textSize
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.locale) private var locale
  @State private var appeared = false
  @State private var navigating = false
  @State private var displayedStep: OnboardingModel.Step
  @State private var footerStep: OnboardingModel.Step
  @State private var footerOpacity: CGFloat = 1
  @State private var leavingStep: OnboardingModel.Step?
  @State private var arrival: CGFloat = 1
  @State private var departure: CGFloat = 0
  @State private var forward = true
  @State private var transitionTask: Task<Void, Never>?
  @State private var search: SearchDestination?
  @State private var guide = false
  @State private var expandedRecommendations = false
  @State private var compactHeight = false
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 64
  @ScaledMetric(relativeTo: .subheadline) private var tickerHeight = 44
  private enum SearchDestination: String, Identifiable {
    case base, destinations; var id: String { rawValue }
  }

  /// Composes the welcome and currency selection with an app-supplied widget showcase.
  init(
    model: OnboardingModel,
    @ViewBuilder widgets:
      @escaping (
        OnboardingModel.Step, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void
      ) -> Widgets
  ) {
    self.model = model
    self.widgets = widgets
    _displayedStep = State(initialValue: model.step)
    _footerStep = State(initialValue: model.step)
  }

  private var moving: Bool {
    !reduceMotion && scenePhase == .active && search == nil && !guide
      && model.phase != .offline && model.phase != .failed && model.phase != .saveFailed
  }
  /// Presents the current setup stage and its recoverable loading or persistence state.
  var body: some View {
    NavigationStack {
      ZStack {
        if needsWelcomeBootstrap {
          welcomeBootstrap.transition(.opacity)
        } else {
          content
            .opacity(appeared ? 1 : 0)
            .allowsHitTesting(appeared)
            .accessibilityHidden(!appeared)
            .transition(.opacity)
        }
      }
      .animation(.easeOut(duration: reduceMotion ? 0.16 : 0.32), value: needsWelcomeBootstrap)
      .background(Color(uiColor: .systemBackground))
      .navigationBarTitleDisplayMode(.inline)
      .toolbarVisibility(.visible, for: .navigationBar)
      .toolbar { navigationControls }
      .sheet(item: $search) { destination in
        OnboardingCurrencySearch(model: model, choosingBase: destination == .base)
      }
      .task { model.start() }
      .task(id: needsWelcomeBootstrap) {
        guard !needsWelcomeBootstrap else { appeared = false; return }
        if reduceMotion { appeared = true; return }
        // Mount the hidden welcome before animating its opacity and the card's initial pose.
        do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
        withAnimation(.easeOut(duration: 0.65)) { appeared = true }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { model.resume() } else { model.pause() }
      }
      .onChange(of: model.step) { _, step in transition(to: step) }
      .onDisappear { transitionTask?.cancel() }
      .sensoryFeedback(.selection, trigger: model.draft)
    }
  }

  private var needsWelcomeBootstrap: Bool {
    model.step == .welcome && !model.hasUsableRates
  }

  private var isLoadingWelcome: Bool {
    !hasBlockingSaveError && !recoveringBase
      && [.opening, .waiting, .retrying].contains(model.phase)
  }

  private var welcomeBootstrap: some View {
    Group {
      if textSize.isAccessibilitySize && !isLoadingWelcome {
        ScrollView {
          VStack(spacing: 32) {
            welcomeBootstrapStatus.frame(height: 120)
            footer
          }
        }
      } else {
        VStack(spacing: 0) {
          welcomeBootstrapStatus.frame(maxWidth: .infinity, maxHeight: .infinity)
          if !isLoadingWelcome { footer }
        }
      }
    }
    .frame(maxWidth: 700).frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var welcomeBootstrapStatus: some View {
    VStack(spacing: 16) {
      if isLoadingWelcome {
        CurrencySymbolLoader(moving: moving)
        Text(model.phase == .retrying ? .Onboarding.tryingAgain : .Onboarding.loading)
          .font(AppStyle.font(.footnote)).foregroundStyle(.secondary)
      } else {
        Image(
          systemName: recoveringBase
            ? "arrow.triangle.2.circlepath"
            : model.phase == .offline ? "wifi.slash" : "exclamationmark.circle"
        )
        .font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
      }
    }
    .multilineTextAlignment(.center).padding(.horizontal, 24)
    .accessibilityIdentifier("onboarding.bootstrap")
  }

  private var content: some View {
    GeometryReader { geometry in
      let accessible = textSize.isAccessibilitySize
      VStack(spacing: 0) {
        // Keep the scene's identity across text-size and window-height changes. It owns
        // the widget preview edits and the destination for an in-progress installation guide.
        ScrollViewReader { scroll in
          GeometryReader { viewport in
            let sceneHeight: CGFloat =
              accessible
              ? (model.step == .welcome ? 380 : model.step == .widgets ? 720 : 500)
              : max(geometry.size.height < 700 ? 380 : 320, viewport.size.height)
            let fixedSceneHeight: CGFloat? =
              !accessible
                && (geometry.size.height >= 700 || displayedStep == .homeScreen
                  || displayedStep == .widgets)
              ? sceneHeight : nil
            ScrollView {
              VStack(spacing: 0) {
                scene(height: sceneHeight)
                  .frame(height: fixedSceneHeight)
                  .id("onboardingScene")
                if accessible { footer.padding(.top, 32) }
              }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollIndicators(accessible ? .automatic : .hidden)
            .onChange(of: displayedStep) { _, _ in
              scroll.scrollTo("onboardingScene", anchor: .top)
            }
          }
        }
        if !accessible { footer }
      }
      .frame(maxWidth: 700).frame(maxWidth: .infinity)
      .frame(height: geometry.size.height, alignment: .top)
      .background(Color(uiColor: .systemBackground))
      .onGeometryChange(for: Bool.self) { proxy in
        proxy.size.height < 700
      } action: {
        compactHeight = $0
      }
    }
  }

  @ToolbarContentBuilder
  private var navigationControls: some ToolbarContent {
    if model.step != .welcome && !guide {
      ToolbarItem(placement: .topBarLeading) {
        Button(.Onboarding.back, systemImage: "chevron.backward") { navigate { model.back() } }
          .labelStyle(.iconOnly).disabled(navigating)
          .accessibilityIdentifier("onboarding.back")
      }
    }
    if model.step == .baseCurrency || model.step == .selection {
      ToolbarItem(placement: .topBarTrailing) {
        Button(.Onboarding.searchAction, systemImage: "magnifyingglass") {
          search = model.step == .baseCurrency ? .base : .destinations
        }
        .labelStyle(.iconOnly).disabled(navigating)
        .accessibilityIdentifier(
          model.step == .baseCurrency ? "onboarding.baseSearch" : "onboarding.search")
      }
    }
  }

  private func scene(height: CGFloat) -> some View {
    ZStack {
      if !textSize.isAccessibilitySize {
        CurrencyDepthField(moving: moving, sparse: model.step != .welcome, appeared: appeared)
          .frame(height: height * 0.66).frame(maxHeight: .infinity, alignment: .top)
      }
      ZStack {
        if let leavingStep {
          sceneContent(leavingStep, progress: 1)
            .modifier(
              OnboardingDeparture(
                progress: departure, forward: forward,
                reduced: reduceMotion || textSize.isAccessibilitySize)
            )
            .allowsHitTesting(false).accessibilityHidden(true)
            .zIndex(0)
        }
        sceneContent(displayedStep, progress: arrival)
          .id(displayedStep)
          .allowsHitTesting(!navigating)
          .zIndex(1)
      }
      .clipped()
    }
    .frame(minHeight: height)
  }

  @ViewBuilder
  private func sceneContent(_ step: OnboardingModel.Step, progress: CGFloat) -> some View {
    switch step {
    case .welcome:
      welcome.modifier(reveal(progress, offset: 12))
    case .baseCurrency:
      BaseCurrencyStep(
        model: model, progress: progress, reduced: reduceMotion || textSize.isAccessibilitySize,
        compact: compactHeight
      ) { search = .base }
    case .selection:
      selection(progress: progress)
    case .homeScreen, .widgets:
      widgets(step, model.snapshot, model.draft, $guide) { _ = model.complete() }
        .modifier(
          reveal(
            progress, offset: step == .homeScreen ? 24 : 16,
            scale: step == .homeScreen ? 0.96 : 0.98))
    }
  }

  private func reveal(
    _ progress: CGFloat, delay: CGFloat = 0, offset: CGFloat = 12,
    scale: CGFloat = 1
  ) -> OnboardingReveal {
    OnboardingReveal(
      progress: progress, delay: delay,
      offset: forward ? offset : -offset * 0.6, scale: scale,
      reduced: reduceMotion || textSize.isAccessibilitySize)
  }

  private var welcome: some View {
    VStack(spacing: 24) {
      Spacer(minLength: 16)
      VStack(spacing: 16) {
        HStack(spacing: 12) {
          CurrencyIcon(model.draft.source, size: 32).frame(width: 36)
          HStack(spacing: 4) {
            Text(CurrencyDisplay.inputAmount("100", locale: locale))
            Text(model.draft.source)
          }
          .font(AppStyle.font(.title2, weight: .semibold)).monospacedDigit()
          .lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Divider()
        HStack(spacing: 12) {
          if let destination = model.welcomeDestination {
            CurrencyIcon(destination, size: 32).frame(width: 36)
            Text(
              "\(CurrencyDisplay.format(model.snapshot.convert(100, from: model.draft.source, to: destination), code: destination, locale: locale)) \(destination)"
            )
            .font(AppStyle.font(.title2, weight: .semibold)).monospacedDigit()
            .contentTransition(.opacity)
          } else {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 30, height: 24)
            Text("—").font(AppStyle.font(.title2)).foregroundStyle(.tertiary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
      }
      .padding(24).frame(width: textSize.isAccessibilitySize ? 300 : 256)
      .background {
        RoundedRectangle(cornerRadius: 28)
          .fill(Color(uiColor: reduceTransparency ? .secondarySystemBackground : .systemBackground))
          .shadow(color: .black.opacity(0.08), radius: 22, y: 10)
          .opacity(appeared ? 1 : 0)
      }
      .scaleEffect(reduceMotion || appeared ? 1 : 0.94)
      .offset(y: reduceMotion || appeared ? 0 : 10)
      .animation(.easeInOut(duration: 0.22), value: model.welcomeDestination)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("onboarding.welcome.quote")
      Color.clear.frame(height: 70).accessibilityHidden(true)
      Spacer(minLength: 48)
    }
  }

  private var heroHeight: CGFloat { textSize.isAccessibilitySize ? 0 : compactHeight ? 92 : 144 }

  private func selection(progress: CGFloat) -> some View {
    VStack(spacing: compactHeight ? 12 : 20) {
      VStack(spacing: 8) {
        Text(.Onboarding.baseContext).font(AppStyle.font(.caption)).foregroundStyle(.secondary)
        VStack(spacing: 4) {
          Text(CurrencyDisplay.inputAmount("100", locale: locale))
            .font(
              .system(
                size: compactHeight ? amountSize * 0.875 : amountSize, weight: .semibold,
                design: .rounded)
            )
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
          HStack(spacing: 8) {
            CurrencyIcon(model.draft.source, size: 24).accessibilityHidden(true)
            Text(model.draft.source).font(AppStyle.font(.title2, weight: .semibold))
          }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.baseContext")
      }
      .frame(minHeight: heroHeight)
      .modifier(reveal(progress, offset: 14, scale: 0.98))
      Group {
        if tickerQuotes.isEmpty {
          Text(.Onboarding.emptySelection).font(AppStyle.font(.subheadline))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: tickerHeight)
        } else {
          ConversionTicker(
            quotes: tickerQuotes, moving: moving,
            accessibilitySummary: String(localized: .Onboarding.conversionPreview)
          )
          .frame(height: tickerHeight)
        }
      }
      .modifier(reveal(progress, delay: 0.20, offset: 10))
      if model.draft.destinations.contains(where: { !model.isAvailable($0) })
        || (model.lastUpdated.map { Date.now.timeIntervalSince($0) > 86400 } ?? false)
      {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            if model.draft.destinations.contains(where: { !model.isAvailable($0) }) {
              Text(.Onboarding.partialRates)
            }
            if let date = model.lastUpdated {
              Text(.Onboarding.updated(date.formatted(date: .abbreviated, time: .shortened)))
            }
          }
          .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          Spacer()
          Button(.Onboarding.retry) { model.retry() }.disabled(model.isRefreshing)
        }
        .padding(.horizontal, 24)
      }
      if textSize.isAccessibilitySize {
        DisclosureGroup(.Onboarding.popularCurrencies, isExpanded: $expandedRecommendations) {
          ForEach(recommendations, id: \.self) { code in
            Button {
              model.toggle(code)
            } label: {
              HStack(spacing: 12) {
                CurrencyIcon(code, size: 28)
                Text(code).font(AppStyle.font(.headline))
                Spacer(minLength: 0)
                if model.draft.destinations.contains(code) {
                  OnboardingSelectionMark()
                }
              }
              .frame(minHeight: 44).padding(.vertical, 8)
            }
            .disabled(!model.isAvailable(code) && !model.draft.destinations.contains(code))
            .accessibilityLabel("\(CurrencyDisplay.name(code, locale: locale)), \(code)")
            .accessibilityValue(
              model.draft.destinations.contains(code)
                ? Text(.Onboarding.selected) : Text(.Onboarding.notSelected))
          }
          Button(.Onboarding.moreCurrencies, systemImage: "magnifyingglass") {
            search = .destinations
          }
          .frame(minHeight: 44)
          .accessibilityIdentifier("onboarding.destinationsMore")
        }
        .font(AppStyle.font(.headline, weight: .bold)).padding(.horizontal, 24)
      } else {
        VStack(alignment: .leading, spacing: 12) {
          Text(.Onboarding.popularCurrencies).font(AppStyle.font(.headline, weight: .bold))
            .padding(.horizontal, 24)
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(recommendations, id: \.self) { code in recommendation(code) }
              OnboardingMoreCurrenciesTile(compact: compactHeight) { search = .destinations }
            }
            .padding(.horizontal, 24)
          }
          .scrollIndicators(.hidden)
          .accessibilityIdentifier("onboarding.recommendations")
        }
        .modifier(reveal(progress, delay: 0.30, offset: 12))
      }
      Spacer(minLength: 8)
    }
    .padding(.top, 4)
  }

  private var recommendations: [String] {
    ["USD", "GBP", "JPY", "CHF", "CZK", "CAD", "AUD", "BTC", "ETH", "XAU", "EUR"]
      .filter { $0 != model.draft.source }
  }
  private var tickerQuotes: [TickerQuote] {
    model.draft.destinations.compactMap { code in
      guard model.isAvailable(code) else { return nil }
      return TickerQuote(
        code: code,
        amount: CurrencyDisplay.format(
          model.snapshot.convert(100, from: model.draft.source, to: code), code: code,
          locale: locale))
    }
  }
  private func recommendation(_ code: String) -> some View {
    OnboardingCurrencyTile(
      code: code, selected: model.draft.destinations.contains(code),
      available: model.isAvailable(code),
      compact: compactHeight, identifier: "onboarding.recommendation.\(code)"
    ) { model.toggle(code) }
  }

  private var footer: some View {
    VStack(spacing: 16) {
      VStack(spacing: 8) {
        Text(title).font(AppStyle.font(.title, weight: .bold)).tracking(-0.6)
          .accessibilityAddTraits(.isHeader)
        Text(subtitle).font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
          .frame(minHeight: textSize.isAccessibilitySize ? nil : 42, alignment: .top)
      }
      .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      .opacity(footerOpacity)
      VStack(spacing: 0) {
        Button {
          primaryAction()
        } label: {
          Text(actionTitle).font(AppStyle.font(.headline))
            .opacity(footerOpacity).frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
        .foregroundStyle(
          actionDisabled
            ? Color(uiColor: .secondaryLabel) : Color(uiColor: .systemBackground)
        )
        .disabled(actionDisabled)
        .allowsHitTesting(!navigating)
        .opacity(model.step == .welcome && model.phase == .opening ? 0 : 1)
        .accessibilityIdentifier("onboarding.primary")
        Group {
          if footerStep == .widgets {
            Button(.Onboarding.later) {
              guard !navigating else { return }
              _ = model.complete()
            }
            .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .opacity(footerOpacity).allowsHitTesting(!navigating)
            .accessibilityIdentifier("onboarding.later")
          } else if !textSize.isAccessibilitySize {
            Color.clear.frame(height: 44).allowsHitTesting(false).accessibilityHidden(true)
          }
        }
      }

    }
    .padding(.horizontal, 24).padding(.top, 16)
  }

  private var hasBlockingSaveError: Bool {
    guard let error = model.saveError else { return false }
    return error != .rates || !model.hasUsableRates
  }
  private var recoveringBase: Bool {
    model.step == .welcome && model.hasRecoveryRates && !model.hasUsableRates
  }
  private var title: LocalizedStringResource {
    if recoveringBase { return .Onboarding.baseUnavailableTitle }
    if footerStep == .baseCurrency { return .Onboarding.baseTitle }
    if footerStep == .selection { return .Onboarding.selectionTitle }
    if footerStep == .homeScreen { return .Onboarding.homeScreenTitle }
    if footerStep == .widgets { return .Onboarding.widgetsTitle }
    switch model.phase {
    case .waiting: return .Onboarding.waitingTitle
    case .retrying: return .Onboarding.tryingAgain
    case .offline: return .Onboarding.offlineTitle
    case .failed: return .Onboarding.failedTitle
    case .saveFailed: return .Onboarding.saveTitle
    default: return .Onboarding.welcomeTitle
    }
  }
  private var subtitle: LocalizedStringResource {
    if let error = model.saveError { return saveMessage(error) }
    if recoveringBase { return .Onboarding.baseUnavailableSubtitle }
    if footerStep == .baseCurrency { return .Onboarding.baseSubtitle }
    if footerStep == .selection { return .Onboarding.selectionSubtitle }
    if footerStep == .homeScreen { return .Onboarding.homeScreenSubtitle }
    if footerStep == .widgets { return .Onboarding.widgetsSubtitle }
    switch model.phase {
    case .waiting, .retrying: return .Onboarding.waitingSubtitle
    case .offline: return .Onboarding.offlineSubtitle
    case .failed: return .Onboarding.failedSubtitle
    default: return .Onboarding.welcomeSubtitle
    }
  }
  private func saveMessage(_ error: OnboardingModel.SaveError) -> LocalizedStringResource {
    switch error {
    case .rates: .Onboarding.rateSaveFailed
    case .selection, .draft: .Onboarding.selectionSaveFailed
    case .completion: .Onboarding.completionSaveFailed
    }
  }
  private var actionTitle: LocalizedStringResource {
    if hasBlockingSaveError { return .Onboarding.retrySave }
    if recoveringBase { return .Onboarding.changeBaseAction }
    switch footerStep {
    case .baseCurrency, .selection: return .Onboarding.continueAction
    case .homeScreen: return .Onboarding.exploreWidgets
    case .widgets: return .Onboarding.showHow
    case .welcome:
      switch model.phase {
      case .retrying: return .Onboarding.retrying
      case .offline, .failed: return .Onboarding.retry
      default: return .Onboarding.getStarted
      }
    }
  }
  private var actionDisabled: Bool {
    if hasBlockingSaveError || recoveringBase { return false }
    if model.step == .baseCurrency { return !model.hasUsableRates }
    if model.step == .selection { return !model.canContinue }
    return model.step == .welcome && [.opening, .waiting, .retrying].contains(model.phase)
  }
  private func primaryAction() {
    guard !navigating else { return }
    if hasBlockingSaveError { model.retrySave(); return }
    if recoveringBase { search = .base; return }
    switch model.step {
    case .welcome:
      if model.hasUsableRates { navigate { model.continueFromWelcome() } } else { model.retry() }
    case .baseCurrency: navigate { model.continueFromBaseCurrency() }
    case .selection: navigate { model.continueFromSelection() }
    case .homeScreen: navigate { model.continueFromHomeScreen() }
    case .widgets: guide = true
    }
  }
  private func navigate(_ action: () -> Void) {
    guard !navigating else { return }
    // Persistence and data changes never inherit the presentation animation.
    let before = model.step
    action()
    if before != model.step { navigating = true }
  }

  private func transition(to next: OnboardingModel.Step) {
    guard next != displayedStep else { navigating = false; return }
    transitionTask?.cancel()
    let order: [OnboardingModel.Step] = [.welcome, .baseCurrency, .selection, .homeScreen, .widgets]
    forward = (order.firstIndex(of: next) ?? 0) > (order.firstIndex(of: displayedStep) ?? 0)
    leavingStep = displayedStep
    displayedStep = next
    arrival = 0
    departure = 0
    navigating = true
    let reduced = reduceMotion || textSize.isAccessibilitySize
    transitionTask = Task { @MainActor in
      do {
        // Give the incoming scene its initial pose before starting the staged reveal.
        try await Task.sleep(for: .milliseconds(16))
        withAnimation(.easeOut(duration: 0.12)) {
          departure = 1
          footerOpacity = 0
        }
        // Hand off text only after the outgoing amount has faded away.
        try await Task.sleep(for: .milliseconds(140))
        footerStep = next
        withAnimation(.easeOut(duration: 0.2)) { footerOpacity = 1 }
        withAnimation(reduced ? .easeOut(duration: 0.16) : .smooth(duration: 0.54)) {
          arrival = 1
        }
        try await Task.sleep(for: .milliseconds(reduced ? 220 : 580))
        leavingStep = nil
        navigating = false
      } catch {}
    }
  }
}
