import Conversion
import DesignSystem
import ExchangeRates
import ExchangeRatesUI
import Onboarding
import SwiftUI

struct OnboardingScreen<Widgets: View>: View {
  private let model: OnboardingModel
  private let widgets:
    (OnboardingModel.Step, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void) ->
      Widgets
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var textSize
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.locale) private var locale
  @Environment(\.layoutDirection) private var layoutDirection
  @Namespace private var searchMotion
  @State private var appeared = false
  @State private var navigating = false
  @State private var displayedStep: OnboardingModel.Step
  @State private var leavingStep: OnboardingModel.Step?
  @State private var arrival: CGFloat = 1
  @State private var departure: CGFloat = 0
  @State private var forward = true
  @State private var transitionTask: Task<Void, Never>?
  @State private var search: SearchDestination?
  @State private var guide = false
  @State private var expandedRecommendations = false
  @State private var sceneHeights: [OnboardingModel.Step: CGFloat] = [:]
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 64
  @ScaledMetric(relativeTo: .subheadline) private var tickerHeight = 44
  private enum SearchDestination: String, Identifiable {
    case base, destinations; var id: String { rawValue }
  }

  init(
    model: OnboardingModel,
    @ViewBuilder widgets:
      @escaping (
        OnboardingModel.Step, RateSnapshot, ConverterState, Binding<Bool>, @escaping () -> Void
      ) -> Widgets
  ) {
    self.model = model
    self.widgets = widgets
    _appeared = State(initialValue: model.step == .ready)
    _displayedStep = State(initialValue: model.step)
  }

  private var moving: Bool {
    !reduceMotion && scenePhase == .active && search == nil && !guide
      && model.phase != .offline && model.phase != .failed && model.phase != .saveFailed
  }
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
      .background(AppStyle.background)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarVisibility(.visible, for: .navigationBar)
      .toolbar { navigationControls }
      .sheet(item: $search) { destination in
        if reduceMotion {
          OnboardingCurrencySearch(model: model, choosingBase: destination == .base)
        } else {
          OnboardingCurrencySearch(model: model, choosingBase: destination == .base)
            .navigationTransition(.zoom(sourceID: "search", in: searchMotion))
        }
      }
      .task(id: needsWelcomeBootstrap) {
        guard !needsWelcomeBootstrap else { appeared = false; return }
        if reduceMotion { appeared = true; return }
        do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
        withAnimation(.easeOut(duration: 0.65)) { appeared = true }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { model.resume() } else { model.pause() }
      }
      .onChange(of: model.step) { _, step in transition(to: step) }
      .onDisappear { transitionTask?.cancel() }
      .onChange(of: model.draft) { _, _ in
        if search == nil && model.saveError == nil { AppHaptics.play(.selection) }
      }
      .onChange(of: model.phase) { _, phase in
        if phase == .offline || phase == .failed { AppHaptics.play(.warning) }
      }
      .onChange(of: model.saveError) { _, error in
        if error != nil { AppHaptics.play(.error) }
      }
      .onChange(of: needsWelcomeBootstrap) { old, new in
        if old && !new { AppHaptics.play(.success) }
      }
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
    GeometryReader { geometry in
      AdaptivePairLayout(
        division: activeDivision(in: geometry),
        wide: geometry.size.width > geometry.size.height && !textSize.isAccessibilitySize,
        rightToLeft: layoutDirection == .rightToLeft
      ) {
        welcomeBootstrapStatus.frame(maxWidth: .infinity, maxHeight: .infinity)
        if isLoadingWelcome {
          Color.clear.frame(height: 0)
        } else {
          ViewThatFits(in: .vertical) {
            footer.frame(maxWidth: 480)
            ScrollView { footer.frame(maxWidth: 480).frame(maxWidth: .infinity) }
              .scrollBounceBehavior(.basedOnSize)
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
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
      let division = activeDivision(in: geometry)
      let wide =
        geometry.size.width > geometry.size.height && !accessible
        && !(displayedStep == .ready && geometry.size.height < 500)
      let split = wide || division != nil
      let choicesBelow = division.map { $0.width > $0.height } ?? false
      AdaptivePairLayout(
        division: division, wide: wide, rightToLeft: layoutDirection == .rightToLeft
      ) {
        GeometryReader { viewport in
          scene(
            height: viewport.size.height, includesFooter: accessible && !split,
            previewOnly: choicesBelow)
        }
        if !accessible || split {
          if split {
            GeometryReader { viewport in
              ScrollView {
                VStack(spacing: 24) {
                  if choicesBelow { stagedChoices }
                  footer(fillHeight: choicesBelow ? nil : max(0, viewport.size.height - 48))
                    .frame(maxWidth: 480)
                }
                .frame(maxWidth: choicesBelow ? 640 : .infinity)
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(0, viewport.size.height - 48))
                .padding(.vertical, 24)
              }
              .scrollBounceBehavior(.basedOnSize)
            }
          } else {
            ViewThatFits(in: .vertical) {
              footer.frame(maxWidth: 480).frame(maxWidth: .infinity)
              ScrollView { footer.frame(maxWidth: 480).frame(maxWidth: .infinity) }
                .scrollBounceBehavior(.basedOnSize)
            }
          }
        } else {
          Color.clear.frame(height: 0)
        }
      }
      .frame(height: geometry.size.height, alignment: .top)
      .background(AppStyle.background)
    }
  }

  private func activeDivision(in geometry: GeometryProxy) -> CGRect? {
    if #available(iOS 27.1, *) {
      return geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed).first?.frame
    }
    return nil
  }

  @ToolbarContentBuilder
  private var navigationControls: some ToolbarContent {
    if !guide {
      ToolbarItem(placement: .topBarLeading) {
        if model.step == .welcome {
          Color.clear.frame(width: 44, height: 44)
            .allowsHitTesting(false).accessibilityHidden(true)
        } else {
          Button(.Onboarding.back, systemImage: "chevron.backward") {
            settleTransition()
            navigate { model.back() }
          }
          .labelStyle(.iconOnly).tint(nil)
          .accessibilityIdentifier("onboarding.back")
        }
      }
      .sharedBackgroundVisibility(model.step == .welcome ? .hidden : .automatic)
    }
    if #available(iOS 27.1, *) {
      searchControl.axisBehavior(.verticalPreferred)
    } else {
      searchControl
    }
  }

  private var searchControl: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button(.Onboarding.searchAction, systemImage: "magnifyingglass") {
        settleTransition()
        search = model.step == .baseCurrency ? .base : .destinations
      }
      .labelStyle(.iconOnly).tint(nil)
      .matchedTransitionSource(id: "search", in: searchMotion)
      .opacity(hasSearch ? 1 : 0)
      .disabled(!hasSearch)
      .accessibilityHidden(!hasSearch)
      .accessibilityIdentifier(
        model.step == .baseCurrency ? "onboarding.baseSearch" : "onboarding.search")
    }
    .sharedBackgroundVisibility(hasSearch ? .automatic : .hidden)
  }

  private var hasSearch: Bool {
    model.step == .baseCurrency || model.step == .selection
  }

  private func scene(height: CGFloat, includesFooter: Bool, previewOnly: Bool) -> some View {
    ZStack(alignment: .top) {
      if !textSize.isAccessibilitySize && model.step != .ready {
        CurrencyDepthField(moving: moving, sparse: model.step != .welcome, appeared: appeared)
          .frame(height: height * 0.66)
      }
      ForEach([leavingStep, displayedStep].compactMap { $0 }, id: \.self) { step in
        let sceneHeight = step == displayedStep ? height : sceneHeights[step] ?? height
        Group {
          if textSize.isAccessibilitySize || (step != .baseCurrency && step != .selection) {
            ScrollView {
              VStack(spacing: 0) {
                stagedScene(step, height: sceneHeight, previewOnly: previewOnly)
                if includesFooter {
                  footer(fillHeight: nil, fixedStep: step)
                    .padding(.top, 32)
                    .opacity(step == displayedStep ? arrival : 1 - departure)
                }
              }
              .frame(minHeight: sceneHeight, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
          } else {
            stagedScene(step, height: sceneHeight, previewOnly: previewOnly)
          }
        }
        .frame(height: sceneHeight, alignment: .top)
        .accessibilityHidden(step != displayedStep)
        .allowsHitTesting(step == displayedStep && !navigating)
        .zIndex(step == displayedStep ? 1 : 0)
      }
    }
    .onChange(of: height, initial: true) { _, height in
      sceneHeights[displayedStep] = height
    }
    .onChange(of: displayedStep) { _, step in sceneHeights[step] = height }
  }

  private func stagedScene(
    _ step: OnboardingModel.Step, height: CGFloat, previewOnly: Bool
  ) -> some View {
    sceneContent(
      step, progress: step == displayedStep ? arrival : 1, compact: height < 460,
      previewOnly: previewOnly
    )
    .frame(maxWidth: step == .baseCurrency || step == .selection ? 640 : .infinity)
    .frame(height: step == .homeScreen || step == .widgets || step == .ready ? height : nil)
    .frame(minHeight: height, alignment: .top)
    .modifier(
      OnboardingDeparture(
        progress: step == leavingStep ? departure : 0,
        forward: forward, reduced: reduceMotion || textSize.isAccessibilitySize)
    )
    .allowsHitTesting(step == displayedStep && !navigating)
  }

  @ViewBuilder
  private func sceneContent(
    _ step: OnboardingModel.Step, progress: CGFloat, compact: Bool, previewOnly: Bool
  ) -> some View {
    switch step {
    case .welcome:
      welcome.modifier(reveal(progress, offset: 24, scale: 0.96))
    case .baseCurrency:
      VStack(spacing: compact ? 12 : 20) {
        Spacer(minLength: 0)
        BaseCurrencyPreview(model: model, compact: compact)
          .frame(minHeight: textSize.isAccessibilitySize ? nil : compact ? 96 : 188)
        if !previewOnly && !textSize.isAccessibilitySize {
          BaseCurrencyChoices(model: model) { search = .base }
            .frame(height: compact ? 140 : 190)
        }
        Spacer(minLength: 0)
      }
      .frame(maxHeight: textSize.isAccessibilitySize ? nil : 520)
      .frame(maxHeight: .infinity)
      .modifier(reveal(progress, offset: 24, scale: 0.96))
    case .selection:
      VStack(spacing: compact ? 12 : 20) {
        Spacer(minLength: 0)
        selectionPreview(compact: compact)
          .frame(minHeight: textSize.isAccessibilitySize ? nil : compact ? 96 : 188)
        if !previewOnly {
          selectionChoices(compact: compact)
            .frame(minHeight: textSize.isAccessibilitySize ? nil : compact ? 140 : 190)
        }
        Spacer(minLength: 0)
      }
      .frame(maxHeight: textSize.isAccessibilitySize ? nil : 520)
      .frame(maxHeight: .infinity)
      .modifier(reveal(progress, offset: 24, scale: 0.96))
    case .homeScreen, .widgets:
      widgets(step, model.snapshot, model.draft, $guide) {
        navigate { model.continueFromWidgets() }
        if model.step == .widgets && model.saveError != nil { guide = false }
      }
      .modifier(
        reveal(
          progress, offset: step == .homeScreen ? 24 : 16,
          scale: step == .homeScreen ? 0.96 : 0.98))
    case .ready:
      OnboardingFinale(moving: moving)
        .modifier(reveal(progress, offset: 18, scale: 0.96))
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
      Spacer(minLength: 12)
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
      .padding(24).frame(maxWidth: textSize.isAccessibilitySize ? 300 : 256)
      .background {
        OnboardingSurface(radius: 28, raised: true).opacity(appeared ? 1 : 0)
      }
      .scaleEffect(reduceMotion || appeared ? 1 : 0.94)
      .offset(y: reduceMotion || appeared ? 0 : 10)
      .animation(.easeInOut(duration: 0.22), value: model.welcomeDestination)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("onboarding.welcome.quote")
      Spacer(minLength: 12)
    }
  }

  private func selectionPreview(compact: Bool) -> some View {
    VStack(spacing: 16) {
      if compact && !textSize.isAccessibilitySize {
        HStack(spacing: 10) {
          Text(CurrencyDisplay.inputAmount("100", locale: locale))
            .font(.system(size: amountSize * 0.6, weight: .semibold, design: .rounded))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
          HStack(spacing: 6) {
            CurrencyIcon(model.draft.source, size: 22).accessibilityHidden(true)
            Text(model.draft.source).font(AppStyle.font(.headline))
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.baseContext")
      } else {
        VStack(spacing: 8) {
          Text(.Onboarding.baseContext).font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          VStack(spacing: 4) {
            Text(CurrencyDisplay.inputAmount("100", locale: locale))
              .font(
                .system(
                  size: compact ? amountSize * 0.875 : amountSize, weight: .semibold,
                  design: .rounded
                )
              )
              .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 8) {
              CurrencyIcon(model.draft.source, size: 24).accessibilityHidden(true)
              Text(model.draft.source).font(AppStyle.font(.title2, weight: .semibold))
            }
          }
          .foregroundStyle(Color.primary)
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("onboarding.baseContext")
        }
      }
      Group {
        if tickerQuotes.isEmpty {
          Text(.Onboarding.emptySelection).font(AppStyle.font(.subheadline))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: tickerHeight)
        } else {
          ConversionTicker(
            quotes: tickerQuotes, moving: moving && !navigating,
            accessibilitySummary: String(localized: .Onboarding.conversionPreview)
          )
          .frame(height: compact ? tickerHeight * 0.75 : tickerHeight)
        }
      }
    }
  }

  private func selectionChoices(compact: Bool) -> some View {
    VStack(spacing: 16) {
      if model.shouldOfferRateRetry {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            if model.hasUnavailableDestinations {
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
                Text(code).font(AppStyle.font(.headline)).foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                if model.draft.manualDestinations.contains(code) {
                  OnboardingSelectionMark()
                }
              }
              .frame(minHeight: 44).padding(.vertical, 8)
            }
            .disabled(!model.isAvailable(code) && !model.draft.manualDestinations.contains(code))
            .accessibilityLabel("\(CurrencyDisplay.name(code, locale: locale)), \(code)")
            .accessibilityValue(
              model.draft.manualDestinations.contains(code)
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
            HStack(spacing: 10) {
              ForEach(recommendations, id: \.self) { code in recommendation(code, compact: compact)
              }
              OnboardingMoreCurrenciesTile(compact: compact) { search = .destinations }
            }
            .padding(.horizontal, 24)
          }
          .scrollIndicators(.hidden)
          .clipped()
          .accessibilityIdentifier("onboarding.recommendations")
        }
      }
    }
    .padding(.vertical, compact ? 0 : 12)
  }

  private var stagedChoices: some View {
    ZStack(alignment: .top) {
      ForEach([leavingStep, displayedStep].compactMap { $0 }, id: \.self) { step in
        Group {
          if step == .baseCurrency && !textSize.isAccessibilitySize {
            BaseCurrencyChoices(model: model) { search = .base }
          } else if step == .selection {
            selectionChoices(compact: false)
          }
        }
        .frame(minHeight: textSize.isAccessibilitySize ? nil : 190, alignment: .top)
        .modifier(reveal(step == displayedStep ? arrival : 1, offset: 24, scale: 0.96))
        .modifier(
          OnboardingDeparture(
            progress: step == leavingStep ? departure : 0,
            forward: forward, reduced: reduceMotion || textSize.isAccessibilitySize)
        )
        .accessibilityHidden(step != displayedStep)
        .allowsHitTesting(step == displayedStep && !navigating)
      }
    }
  }

  private var recommendations: [String] {
    OnboardingRecommendations.currencies
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
  private func recommendation(_ code: String, compact: Bool) -> some View {
    OnboardingCurrencyTile(
      code: code, selected: model.draft.manualDestinations.contains(code),
      available: model.isAvailable(code), compact: compact,
      identifier: "onboarding.recommendation.\(code)"
    ) { model.toggle(code) }
  }

  private var footer: some View { footer(fillHeight: nil) }

  private func footer(
    fillHeight: CGFloat?, fixedStep: OnboardingModel.Step? = nil
  ) -> some View {
    let footerStep = fixedStep ?? displayedStep
    let steps = fixedStep.map { [$0] } ?? [leavingStep, displayedStep].compactMap { $0 }
    return VStack(spacing: 16) {
      if footerStep == .ready {
        if fillHeight != nil { Spacer(minLength: 0) }
        if let error = model.saveError {
          Text(saveMessage(error)).font(AppStyle.font(.subheadline))
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
      } else {
        ZStack(alignment: .top) {
          if !textSize.isAccessibilitySize {
            ForEach(footerSizingSteps, id: \.self) { step in
              footerText(for: step).hidden().accessibilityHidden(true)
            }
          }
          ForEach(steps, id: \.self) { step in
            footerText(for: step)
              .opacity(fixedStep != nil ? 1 : step == displayedStep ? arrival : 1 - departure)
              .accessibilityHidden(step != displayedStep)
          }
        }
        .frame(minHeight: textSize.isAccessibilitySize ? nil : 84, alignment: .top)
        if fillHeight != nil { Spacer(minLength: 16) }
      }
      VStack(spacing: 0) {
        Button {
          primaryAction()
        } label: {
          ZStack {
            ForEach(steps, id: \.self) { step in
              Text(actionTitle(for: step)).font(AppStyle.font(.headline))
                .modifier(AppAccentLabel())
                .opacity(fixedStep != nil ? 1 : step == displayedStep ? arrival : 1 - departure)
                .accessibilityHidden(step != displayedStep)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
        .disabled(actionDisabled)
        .allowsHitTesting(!navigating)
        .opacity(model.step == .welcome && model.phase == .opening ? 0 : 1)
        .accessibilityIdentifier("onboarding.primary")
        Group {
          if footerStep == .widgets {
            Button(.Onboarding.later) {
              guard !navigating else { return }
              navigate { model.continueFromWidgets() }
            }
            .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .allowsHitTesting(!navigating)
            .accessibilityIdentifier("onboarding.later")
          } else if footerStep != .ready && fillHeight != nil && !textSize.isAccessibilitySize {
            Color.clear.frame(height: 44).allowsHitTesting(false).accessibilityHidden(true)
          }
        }
      }
      if footerStep == .ready && fillHeight != nil { Spacer(minLength: 0) }
    }
    .padding(.horizontal, 24).padding(.top, footerStep == .ready ? 0 : 16)
    .frame(minHeight: fillHeight, alignment: .top)
  }

  private var footerSizingSteps: [OnboardingModel.Step] {
    [.welcome, .baseCurrency, .selection, .homeScreen, .widgets, .ready]
  }

  private func footerText(for step: OnboardingModel.Step) -> some View {
    VStack(spacing: 8) {
      if step != .ready {
        Text(title(for: step)).font(AppStyle.font(.title, weight: .bold)).tracking(-0.6)
          .accessibilityAddTraits(.isHeader)
      }
      Text(subtitle(for: step)).font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
        .frame(minHeight: textSize.isAccessibilitySize ? nil : 42, alignment: .top)
    }
    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
  }

  private var hasBlockingSaveError: Bool {
    guard let error = model.saveError else { return false }
    return error != .rates || !model.hasUsableRates
  }
  private var recoveringBase: Bool {
    model.step == .welcome && model.hasRecoveryRates && !model.hasUsableRates
  }
  private func title(for step: OnboardingModel.Step) -> LocalizedStringResource {
    if recoveringBase { return .Onboarding.baseUnavailableTitle }
    if step == .baseCurrency { return .Onboarding.baseTitle }
    if step == .selection { return .Onboarding.selectionTitle }
    if step == .homeScreen { return .Onboarding.homeScreenTitle }
    if step == .widgets { return .Onboarding.widgetsTitle }
    if step == .ready { return .Onboarding.readyTitle }
    switch model.phase {
    case .waiting: return .Onboarding.waitingTitle
    case .retrying: return .Onboarding.tryingAgain
    case .offline: return .Onboarding.offlineTitle
    case .failed: return .Onboarding.failedTitle
    case .saveFailed: return .Onboarding.saveTitle
    default: return .Onboarding.welcomeTitle
    }
  }
  private func subtitle(for step: OnboardingModel.Step) -> LocalizedStringResource {
    if let error = model.saveError { return saveMessage(error) }
    if recoveringBase { return .Onboarding.baseUnavailableSubtitle }
    if step == .baseCurrency { return .Onboarding.baseSubtitle }
    if step == .selection { return .Onboarding.selectionSubtitle }
    if step == .homeScreen { return .Onboarding.homeScreenSubtitle }
    if step == .widgets { return .Onboarding.widgetsSubtitle }
    if step == .ready { return .Onboarding.readySubtitle }
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
  private func actionTitle(for step: OnboardingModel.Step) -> LocalizedStringResource {
    if hasBlockingSaveError { return .Onboarding.retrySave }
    if recoveringBase { return .Onboarding.changeBaseAction }
    switch step {
    case .baseCurrency, .selection: return .Onboarding.continueAction
    case .homeScreen: return .Onboarding.exploreWidgets
    case .widgets: return .Onboarding.showHow
    case .ready: return .Onboarding.getStarted
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
    case .widgets: AppHaptics.play(.action); guide = true
    case .ready:
      if model.complete() { AppHaptics.play(.success) }
    }
  }
  private func settleTransition() {
    transitionTask?.cancel()
    transitionTask = nil
    leavingStep = nil
    arrival = 1
    departure = 0
    navigating = false
  }

  private func navigate(_ action: () -> Void) {
    guard !navigating else { return }
    let before = model.step
    action()
    if before != model.step { navigating = true }
  }

  private func transition(to next: OnboardingModel.Step) {
    guard next != displayedStep else { navigating = false; return }
    transitionTask?.cancel()
    AppHaptics.play(next == .ready ? .celebration : .transition)
    let order: [OnboardingModel.Step] = [
      .welcome, .baseCurrency, .selection, .homeScreen, .widgets, .ready
    ]
    forward = (order.firstIndex(of: next) ?? 0) > (order.firstIndex(of: displayedStep) ?? 0)
    leavingStep = displayedStep
    displayedStep = next
    arrival = 0
    departure = 0
    navigating = true
    let reduced = reduceMotion || textSize.isAccessibilitySize
    transitionTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .milliseconds(16))
        withAnimation(reduced ? .easeOut(duration: 0.2) : .smooth(duration: 0.54)) {
          departure = 1
          arrival = 1
        }
        try await Task.sleep(for: .milliseconds(reduced ? 220 : 560))
        leavingStep = nil
        navigating = false
      } catch {}
    }
  }
}
