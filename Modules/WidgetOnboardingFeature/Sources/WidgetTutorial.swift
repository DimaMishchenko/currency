import CurrencySelectionUI
import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit
import WidgetPresentation

struct WidgetTutorialStep: Equatable {
  let title: String
  let detail: String
}

struct WidgetTutorial: View {
  @Environment(\.localCurrencyDestination) private var localCurrencyDestination
  let kind: WidgetShowcaseKind
  let family: WidgetFamily
  let editing: Bool
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var step = 0
  @State private var replay = 0
  @State private var custom = false
  @State private var comparison = "USD"
  @State private var currencyPicker: TutorialPicker?
  @State private var currencies: [String] = ["EUR", "USD", "GBP", "JPY"]
  @State private var base = "EUR"
  @State private var amount = "100"
  @FocusState private var amountFocused: Bool
  @State private var includeLocal = false
  private enum TutorialPicker: String, Identifiable {
    case base, comparison, add; var id: Self { self }
  }
  init(kind: WidgetShowcaseKind, family: WidgetFamily? = nil, editing: Bool = false) {
    self.kind = kind
    self.family = family.flatMap { kind.families.contains($0) ? $0 : nil } ?? kind.families[0]
    self.editing = editing
    _base = State(initialValue: kind.codes[0])
    _comparison = State(initialValue: kind.codes.last ?? "USD")
  }
  private var previewCodes: [String] {
    if kind == .calculator {
      return custom ? currencies : kind.codes + (includeLocal ? [WidgetSelection.localID] : [])
    }
    if kind == .board {
      return custom ? WidgetSelection.board(base: base, targets: currencies) : kind.codes
    }
    return [base, comparison]
  }
  @State private var location = false
  @AccessibilityFocusState private var headingFocused: Bool
  private var lockScreen: Bool { kind == .quick }
  private var steps: [WidgetTutorialStep] {
    if lockScreen {
      return [
        .init(
          title: String(localized: .WidgetOnboarding.guideHoldLockTitle),
          detail: String(localized: .WidgetOnboarding.guideHoldLockDetail)
        ),
        .init(
          title: String(localized: .WidgetOnboarding.guideCustomizeTitle),
          detail: String(localized: .WidgetOnboarding.guideCustomizeDetail)),
        .init(
          title: String(localized: .WidgetOnboarding.guideWidgetAreaTitle),
          detail: family == .accessoryInline
            ? String(localized: .WidgetOnboarding.guideInlineAreaDetail)
            : String(localized: .WidgetOnboarding.guideRectangleAreaDetail)),
        .init(
          title: String(localized: .WidgetOnboarding.guideFindCurrencyTitle),
          detail: String(localized: .WidgetOnboarding.guideLockCurrencyDetail)),
        .init(
          title: String(localized: .WidgetOnboarding.guideFinishLockTitle),
          detail:
            String(localized: .WidgetOnboarding.guideFinishLockDetail)
        )
      ]
    }
    if editing {
      return [
        .init(
          title: String(localized: .WidgetOnboarding.guideHoldWidgetTitle),
          detail: String(localized: .WidgetOnboarding.guideHoldInstalled(kind.title))),
        .init(
          title: String(localized: .WidgetOnboarding.guideEditTitle),
          detail: String(localized: .WidgetOnboarding.guideEditDetail)),
        .init(
          title: kind == .calculator || kind == .board
            ? String(localized: .WidgetOnboarding.guidePersonalizeTitle)
            : String(localized: .WidgetOnboarding.guideCurrenciesTitle),
          detail: kind == .calculator || kind == .board
            ? String(localized: .WidgetOnboarding.guideListsDetail)
            : String(localized: .WidgetOnboarding.guidePairDetail)),
        .init(
          title: String(localized: .WidgetOnboarding.guideLocalTitle),
          detail: kind == .board
            ? String(localized: .WidgetOnboarding.guideBoardLocalDetail)
            : (kind == .calculator && !custom
              ? String(localized: .WidgetOnboarding.guideDefaultLocalDetail)
              : String(localized: .WidgetOnboarding.guideCustomLocalDetail))
        ),
        .init(
          title: String(localized: .WidgetOnboarding.guideFinishEditTitle),
          detail:
            String(localized: .WidgetOnboarding.guideFinishEditDetail)
        )
      ]
    }
    return [
      .init(
        title: String(localized: .WidgetOnboarding.guideHoldHomeTitle),
        detail:
          String(localized: .WidgetOnboarding.guideHoldHomeDetail)),
      .init(
        title: String(localized: .WidgetOnboarding.guideTapEditTitle),
        detail: String(localized: .WidgetOnboarding.guideTapEditDetail)),
      .init(
        title: String(localized: .WidgetOnboarding.guideChooseAddTitle),
        detail: String(localized: .WidgetOnboarding.guideChooseAddDetail)),
      .init(
        title: String(localized: .WidgetOnboarding.guideFindCurrencyTitle),
        detail: String(localized: .WidgetOnboarding.guideSearchDetail)),
      .init(
        title: String(localized: .WidgetOnboarding.guideChooseWidgetTitle),
        detail:
          String(
            localized: .WidgetOnboarding.guideChooseFamily(
              kind.title, family.showcaseTitle.lowercased()))
      ),
      .init(
        title: String(localized: .WidgetOnboarding.guideFinishHomeTitle),
        detail:
          String(localized: .WidgetOnboarding.guideFinishHomeDetail)
      )
    ]
  }
  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        let illustrationWidth: CGFloat =
          editing && step == 2
          ? 200 : min(340, max(210, (geometry.size.height - 200) * 1.03))
        let canvasWidth: CGFloat = editing && step == 2 ? 340 : illustrationWidth
        ScrollViewReader { scroll in
          ScrollView {
            VStack(spacing: 24) {
              HStack(spacing: 4) {
                ForEach(steps.indices, id: \.self) { index in
                  Capsule().fill(index <= step ? Color.primary : Color.primary.opacity(0.12))
                    .frame(height: 3)
                }
              }
              .accessibilityLabel(.WidgetOnboarding.guideStep(step + 1, steps.count))
              .id("tutorialStart")
              MiniHomeScreen(
                kind: kind, family: family, step: step, editing: editing, lockScreen: lockScreen,
                codes: previewCodes, amount: kind == .board && custom ? amount : nil,
                synchronized: kind == .calculator && !custom,
                paused: location || currencyPicker != nil
              )
              .id(replay)
              .frame(width: canvasWidth, height: canvasWidth / 1.03)
              .scaleEffect(illustrationWidth / canvasWidth)
              .frame(width: illustrationWidth, height: illustrationWidth / 1.03)
              .accessibilityHidden(true)
              VStack(spacing: 12) {
                Text(steps[step].title).font(AppStyle.font(.title2, weight: .semibold))
                  .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                Text(steps[step].detail).font(AppStyle.font(.body)).foregroundStyle(.secondary)
              }
              .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
              if editing && !lockScreen && step == 2 { configurationDemo }
              if editing && !lockScreen && step == 3 && kind != .board {
                Button {
                  location = true
                } label: {
                  Label(.WidgetOnboarding.guideAutomaticLocal, systemImage: "location")
                }
                .buttonStyle(.bordered).controlSize(.large)
                Text(.WidgetOnboarding.guideLocalPrivacy)
                  .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
              }
              if textSize.isAccessibilitySize { actions }
            }
            .padding(24)
          }
          .onChange(of: step) { _, _ in
            if textSize.isAccessibilitySize { scroll.scrollTo("tutorialStart", anchor: .top) }
          }
        }
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if !textSize.isAccessibilitySize { actions }
      }
      .navigationTitle(
        lockScreen
          ? String(localized: .WidgetOnboarding.guideLockTitle)
          : editing
            ? String(localized: .WidgetOnboarding.guideEditNavigation)
            : String(localized: .WidgetOnboarding.guideAddWidget)
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.WidgetOnboarding.close, systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(.WidgetOnboarding.done) { amountFocused = false }
        }
      }
      .sheet(item: $currencyPicker) { purpose in
        CurrencyChooser(
          purpose: purpose == .add ? .add : .source,
          selected: purpose == .add ? currencies : [], homeCurrencies: kind.codes,
          available: Set(WidgetPreviewState.rates.quotes.keys),
          allowedCodes: kind == .cash
            ? Set(CurrencyCatalog.codes.filter(WidgetPresets.allows)) : nil,
          title: purpose == .comparison ? .WidgetOnboarding.guideComparison : nil
        ) { code in
          switch purpose {
          case .base: base = code
          case .comparison: comparison = code
          case .add: currencies = WidgetSelection.normalize(currencies + [code], allowsLocal: true)
          }
        }
      }
      .sheet(isPresented: $location) { localCurrencyDestination() }
    }
  }
  private var actions: some View {
    VStack(spacing: 12) {
      Button {
        if step == steps.count - 1 { dismiss() } else { move(to: step + 1) }
      } label: {
        Text(
          step == steps.count - 1
            ? String(localized: .WidgetOnboarding.guideGotIt)
            : String(localized: .WidgetOnboarding.guideNext)
        )
        .font(AppStyle.font(.headline)).frame(maxWidth: .infinity).padding(.vertical, 8)
      }
      .foregroundStyle(Color(uiColor: .systemBackground))
      .buttonStyle(.borderedProminent).controlSize(.large)
      let secondaryLayout =
        textSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        : AnyLayout(HStackLayout())
      secondaryLayout {
        Button(.WidgetOnboarding.guideBack, systemImage: "chevron.left") { move(to: step - 1) }
          .disabled(step == 0)
        if !textSize.isAccessibilitySize { Spacer() }
        Button(.WidgetOnboarding.guideReplay, systemImage: "arrow.counterclockwise") {
          replay += 1
        }
      }
      .font(AppStyle.font(.subheadline)).frame(minHeight: 32)
    }
    .padding(.horizontal, textSize.isAccessibilitySize ? 0 : 24).padding(.vertical, 12)
    .background(Color(uiColor: .systemGroupedBackground))
  }
  private func move(to index: Int) {
    amountFocused = false
    withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86)) {
      step = index
    }
    headingFocused = true
  }
  private func currencyRow(_ title: String, code: String, action: @escaping () -> Void) -> some View
  {
    Button(action: action) {
      HStack {
        Text(title); Spacer(); CurrencyIcon(code, size: 20); Text(code);
        Image(systemName: "chevron.up.chevron.down").font(.caption)
      }
    }
  }
  private var configurationDemo: some View {
    VStack(alignment: .leading, spacing: 16) {
      if kind == .calculator || kind == .board {
        Picker(.WidgetOnboarding.guideCurrencyList, selection: $custom) {
          Text(.WidgetOnboarding.guideDefault).tag(false)
          Text(.WidgetOnboarding.guideCustom).tag(true)
        }
        .pickerStyle(.segmented)
        Text(
          custom
            ? String(localized: .WidgetOnboarding.guideCustomListHint)
            : String(localized: .WidgetOnboarding.guideDefaultListHint)
        )
        .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
      }
      if kind == .calculator && !custom {
        Toggle(.WidgetOnboarding.guideAddLocalDefault, isOn: $includeLocal)
      }
      if kind == .board && custom {
        currencyRow(String(localized: .WidgetOnboarding.guideBase), code: base) {
          currencyPicker = .base
        }
        HStack {
          Text(.WidgetOnboarding.guideAmount).accessibilityHidden(true)
          TextField(.WidgetOnboarding.guideAmount, text: $amount).multilineTextAlignment(.trailing)
            .keyboardType(.decimalPad)
            .accessibilityLabel(.WidgetOnboarding.guideAmount)
            .focused($amountFocused)
        }
      }
      if (kind == .calculator || kind == .board) && custom {
        Text(.WidgetOnboarding.currencies).font(AppStyle.font(.subheadline, weight: .semibold))
        ForEach(currencies, id: \.self) { code in
          HStack {
            if code == WidgetSelection.localID {
              Label(.WidgetOnboarding.guideLocalCurrency, systemImage: "location")
            } else {
              CurrencyIcon(code, size: 20); Text(code)
              Text(CurrencyDisplay.name(code)).foregroundStyle(.secondary)
                .font(AppStyle.font(.caption))
            }
            Spacer()
            Button(
              .WidgetOnboarding.guideRemoveCurrency(
                code == WidgetSelection.localID
                  ? String(localized: .WidgetOnboarding.guideLocalCurrency) : code
              ), systemImage: "minus.circle"
            ) {
              currencies.removeAll { $0 == code }
            }
            .labelStyle(.iconOnly).disabled(currencies.count == 1)
          }
        }
        Button(.WidgetOnboarding.addCurrency, systemImage: "plus") { currencyPicker = .add }
        if kind == .calculator && !currencies.contains(WidgetSelection.localID) {
          Button(.WidgetOnboarding.guideAddLocal, systemImage: "location") {
            currencies.append(WidgetSelection.localID)
          }
        }
      } else if kind != .calculator && kind != .board {
        currencyRow(String(localized: .WidgetOnboarding.guideBase), code: base) {
          currencyPicker = .base
        }
        currencyRow(String(localized: .WidgetOnboarding.guideComparison), code: comparison) {
          currencyPicker = .comparison
        }
      }
      Text(.WidgetOnboarding.guidePracticeOnly)
        .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
    }
    .padding(16).background(.background, in: .rect(cornerRadius: 20))
  }
}

/// An intentional crop of the Home Screen, assembled from separate native pieces.
private struct MiniHomeScreen: View {
  let kind: WidgetShowcaseKind
  let family: WidgetFamily
  let step: Int
  let editing: Bool
  let lockScreen: Bool
  let codes: [String]
  let amount: String?
  let synchronized: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var paused = false
  @Environment(\.scenePhase) private var scenePhase
  private var animationEnabled: Bool { !paused && scenePhase == .active && !reduceMotion }
  @State private var pressed = false
  @State private var engaged = false
  @State private var settled = false
  @State private var jiggle = false
  @State private var typed = ""
  @Namespace private var continuity
  private var gallery: Bool {
    (!editing && !lockScreen && (3...4).contains(step)) || (lockScreen && step == 3)
  }
  private var widgetVisible: Bool { editing || (!lockScreen && step == 5) }
  private var wiggling: Bool {
    !editing && !lockScreen
      && ((step == 0 && engaged) || (1...2).contains(step) || (step == 5 && !settled))
  }
  var body: some View {
    GeometryReader { geometry in
      let w = geometry.size.width
      let h = geometry.size.height
      let homeWidth =
        family == .systemLarge && widgetVisible
        ? h * 0.67 * family.previewSize.width / family.previewSize.height : w - 48
      let homeScale = homeWidth / 292
      ZStack(alignment: .top) {
        Rectangle().fill(Color(uiColor: .secondarySystemGroupedBackground))
        LinearGradient(
          colors: [Color.blue.opacity(0.17), Color.cyan.opacity(0.07), Color.indigo.opacity(0.18)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        VStack(spacing: 20) {
          HStack {
            if wiggling || (!editing && !lockScreen && step >= 1 && !settled) {
              Text(.WidgetOnboarding.guideNativeEdit)
                .matchedGeometryEffect(id: "edit", in: continuity)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
              Spacer()
              Text(.WidgetOnboarding.done).padding(.horizontal, 16).padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
            } else if lockScreen && step >= 2 && !settled {
              Spacer()
              Text(.WidgetOnboarding.done).padding(.horizontal, 16).padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
            } else {
              Color.clear.frame(height: 30)
            }
          }
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          if lockScreen {
            lockFace
          } else {
            if widgetVisible {
              Group {
                if editing { widget } else { widgetSlot }
              }
              .frame(maxWidth: family == .systemSmall ? w * 0.43 : .infinity)
              .frame(height: family == .systemLarge ? h * 0.67 : w * 0.42)
              .scaleEffect(editing && step == 0 && pressed ? 1.035 : 1)
            }
            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), spacing: 16 * homeScale), count: 4),
              spacing: 20 * homeScale
            ) {
              ForEach(0..<(widgetVisible ? 4 : 12), id: \.self) { index in
                appIcon(index, scale: homeScale)
                  .rotationEffect(
                    .degrees(
                      wiggling && animationEnabled
                        ? (jiggle ? 1.3 : -1.3) * (index.isMultiple(of: 2) ? 1 : -1) : 0))
              }
            }
          }
          Spacer(minLength: 0)
        }
        .frame(width: homeWidth)
        .padding(.vertical, 24)
        .frame(width: w, height: h)
        if !lockScreen && ((!editing && step == 2) || (editing && step == 1)) {
          VStack(spacing: 0) {
            menuRow(
              editing
                ? String(localized: .WidgetOnboarding.guideNativeEditWidget)
                : String(localized: .WidgetOnboarding.guideNativeAddWidget),
              icon: editing ? "slider.horizontal.3" : "plus", selected: true)
            Divider()
            menuRow(
              editing
                ? String(localized: .WidgetOnboarding.guideNativeEditHome)
                : String(localized: .WidgetOnboarding.guideNativeCustomize),
              icon: "square.grid.2x2",
              selected: false)
          }
          .background(.regularMaterial, in: .rect(cornerRadius: 18))
          .shadow(color: .black.opacity(0.12), radius: 20, y: 12)
          .frame(width: w * 0.77).offset(x: -w * 0.04, y: editing ? h * 0.47 : 60)
          .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity))
        }
        if gallery { galleryCard(height: h) }
        if editing && step == 2 {
          VStack(spacing: 12) {
            Text(kind.title).font(.system(size: 13, weight: .semibold, design: .rounded))
            HStack {
              Text(
                kind == .calculator || kind == .board
                  ? String(localized: .WidgetOnboarding.guideCurrencyList)
                  : String(localized: .WidgetOnboarding.guideComparison));
              Spacer();
              Text(
                kind == .calculator || kind == .board
                  ? String(localized: .WidgetOnboarding.guideNativeLists) : codes.last ?? "USD"
              )
              .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, design: .rounded))
            .padding(12).background(.quaternary, in: .rect(cornerRadius: 10))
          }
          .padding(16).background(.regularMaterial, in: .rect(cornerRadius: 24))
          .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
          .padding(.horizontal, 20).frame(maxHeight: .infinity, alignment: .bottom)
          .padding(.bottom, 20)
          .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        if step < (lockScreen ? 4 : editing ? 2 : 5) || (!editing && !settled) {
          touchIndicator
            .position(touchPoint(w: w, h: h))
        }
      }
      .frame(width: w, height: h)
      .overlayPreferenceValue(TutorialWidgetBounds.self) { anchor in
        GeometryReader { proxy in
          if let anchor {
            let rect = proxy[anchor]
            widget.frame(width: rect.width, height: rect.height)
              .position(x: rect.midX, y: rect.midY)
              .animation(
                reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: rect
              )
              .allowsHitTesting(false)
          }
        }
      }
      .clipShape(.rect(cornerRadius: 32))
      .overlay {
        RoundedRectangle(cornerRadius: 32).strokeBorder(.primary.opacity(0.05), lineWidth: 0.5)
      }
    }
    .task(
      id: TutorialPlayback(
        step: step, active: !paused && scenePhase == .active, reducedMotion: reduceMotion)
    ) {
      guard !paused && scenePhase == .active else { return }
      pressed = false; engaged = false; settled = false; typed = ""
      if reduceMotion { pressed = true; engaged = true; settled = true; typed = "Currency"; return }
      do {
        try await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeInOut(duration: step == 0 ? 0.85 : 0.35)) { pressed = true }
        try await Task.sleep(for: .milliseconds(step == 0 ? 900 : 350))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { engaged = true }
        if !editing && step == (lockScreen ? 4 : 5) {
          try await Task.sleep(for: .milliseconds(450))
          withAnimation(.smooth(duration: 0.4)) { settled = true }
        }
        if gallery && !lockScreen && step == 3 {
          for character in "Currency" {
            try await Task.sleep(for: .milliseconds(100)); typed.append(character)
          }
        }
      } catch { return }
    }
    .onChange(of: wiggling && animationEnabled) { _, value in
      if value {
        withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) {
          jiggle.toggle()
        }
      } else {
        withAnimation(nil) { jiggle = false }
      }
    }
  }
  private var widget: some View {
    FittedWidgetPreview(
      kind: kind, family: family, codes: codes, amount: amount, synchronized: synchronized
    )
    .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
  }
  private var widgetSlot: some View {
    Color.clear.aspectRatio(family.previewSize, contentMode: .fit)
      .anchorPreference(key: TutorialWidgetBounds.self, value: .bounds) { $0 }
  }
  private func appIcon(_ index: Int, scale: CGFloat) -> some View {
    let symbols = [
      "sun.max.fill", "calendar", "camera.fill", "music.note", "clock.fill", "envelope.fill",
      "map.fill", "heart.fill", "cloud.fill", "book.fill", "gearshape.fill", "message.fill"
    ]
    let colors: [Color] = [
      .orange, .red, .gray, .pink, .primary, .blue, .green, .pink, .cyan, .orange, .gray, .green
    ]
    return RoundedRectangle(cornerRadius: 14 * scale).fill(.background.opacity(0.86))
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        Image(systemName: symbols[index]).font(.system(size: 23 * scale, weight: .medium))
          .foregroundStyle(colors[index].opacity(0.8))
      }
      .overlay(alignment: .topLeading) {
        if wiggling {
          Image(systemName: "minus").font(.system(size: 8, weight: .bold)).padding(4)
            .background(.regularMaterial, in: .circle).offset(x: -4, y: -4)
        }
      }
      .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
  }
  private var lockFace: some View {
    VStack(spacing: 8) {
      if family == .accessoryInline && step >= 2 {
        HStack(spacing: 4) {
          Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day()))
            .font(.system(size: 11, weight: .medium, design: .rounded)).fixedSize()
          FittedWidgetPreview(kind: .quick, family: .accessoryInline).frame(height: 24)
        }
      } else {
        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
          .font(.system(size: 13, weight: .medium, design: .rounded))
      }
      Text("9:41").font(.system(size: 64, weight: .semibold, design: .rounded))
      if family != .accessoryInline && step >= 2 {
        RoundedRectangle(cornerRadius: 14)
          .strokeBorder(.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
          .frame(height: 58)
          .overlay {
            if step >= 3 {
              FittedWidgetPreview(kind: .quick, family: family).padding(6)
            } else {
              Text(.WidgetOnboarding.guideNativeAddWidgets)
                .font(.system(size: 12, design: .rounded))
            }
          }
      }
      if step == 1 {
        Text(.WidgetOnboarding.guideNativeCustomize)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .padding(12).background(.regularMaterial, in: .capsule).padding(.top, 44)
      }
    }
  }
  private func galleryCard(height: CGFloat) -> some View {
    VStack(spacing: 14) {
      Capsule().fill(.tertiary).frame(width: 30, height: 4)
      if lockScreen && family == .accessoryInline {
        Text(.WidgetOnboarding.guideNativeChooseWidget)
          .font(.system(size: 14, weight: .semibold, design: .rounded))
        VStack(alignment: .leading, spacing: 8) {
          Text("Currency").font(.system(size: 13, weight: .semibold, design: .rounded))
          VStack(alignment: .leading, spacing: 4) {
            FittedWidgetPreview(kind: .quick, family: family)
              .frame(maxWidth: family == .accessoryInline ? .infinity : 170)
              .frame(height: family == .accessoryInline ? 28 : 76)
            Text(kind.title).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
          }
          .padding(12).frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary, in: .rect(cornerRadius: 12))
        }
      } else if lockScreen {
        HStack {
          Text("Currency"); Spacer(); Image(systemName: "xmark")
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        Text(kind.title).font(.system(size: 17, weight: .semibold, design: .rounded))
        FittedWidgetPreview(kind: .quick, family: family)
          .frame(width: 150, height: 67)
          .padding(8).background(.quaternary, in: .rect(cornerRadius: 12))
        Text(.WidgetOnboarding.guideNativeTapToAdd)
          .font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
      } else if step == 3 {
        HStack {
          Image(systemName: "magnifyingglass");
          Text(typed.isEmpty ? String(localized: .WidgetOnboarding.guideNativeSearch) : typed);
          Spacer()
        }
        .font(.system(size: 13, design: .rounded)).padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        HStack {
          Image(systemName: "equal").font(.title2).padding(8)
            .background(.quaternary, in: .rect(cornerRadius: 12))
          Text("Currency"); Spacer(); Image(systemName: "chevron.right")
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .opacity(typed.isEmpty ? 0 : 1)
        Spacer(minLength: 0)
      } else {
        Text(kind.title).font(.system(size: 14, weight: .semibold, design: .rounded))
        widgetSlot.frame(
          maxWidth: family == .systemSmall ? 116 : family == .systemLarge ? 174 : .infinity)
        HStack(spacing: 4) {
          ForEach(0..<3) { index in
            Circle().fill(.primary.opacity(index == 1 ? 0.8 : 0.15)).frame(width: 4, height: 4)
          }
        }
        Text(.WidgetOnboarding.guideNativeAddWidget)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(Color(uiColor: .systemBackground)).frame(maxWidth: .infinity).padding(12)
          .background(.primary, in: .capsule)
      }
    }
    .padding(16)
    .frame(
      height: height
        * (lockScreen ? (family == .accessoryInline ? 0.60 : 0.74) : step == 4 ? 0.94 : 0.77)
    )
    .background(.regularMaterial, in: .rect(topLeadingRadius: 26, topTrailingRadius: 26))
    .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
    .frame(maxHeight: .infinity, alignment: .bottom)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }
  private var touchIndicator: some View {
    Circle().fill(.white.opacity(0.55))
      .overlay { Circle().strokeBorder(.black.opacity(0.18), lineWidth: 1) }
      .overlay {
        Circle().trim(from: 0, to: pressed ? 1 : 0)
          .stroke(.primary.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .frame(width: 32, height: 32).scaleEffect(pressed ? 0.86 : 1.1)
      .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
      .opacity(engaged ? 0 : 1)
  }
  private func menuRow(_ title: String, icon: String, selected: Bool) -> some View {
    HStack {
      Text(title); Spacer(); Image(systemName: icon)
    }
    .font(.system(size: 14, weight: selected ? .semibold : .regular, design: .rounded))
    .padding(16).background(Color.primary.opacity(selected ? 0.04 : 0))
  }
  private func touchPoint(w: CGFloat, h: CGFloat) -> CGPoint {
    if !editing && step == (lockScreen ? 4 : 5) {
      let width =
        family == .systemLarge
        ? h * 0.67 * family.previewSize.width / family.previewSize.height : w - 48
      return CGPoint(x: (w + width) / 2 - 28, y: 39)
    }
    if lockScreen {
      return CGPoint(x: w * 0.5, y: step == 1 ? h * 0.8 : step == 3 ? h * 0.72 : h * 0.47)
    }
    if editing { return CGPoint(x: w * 0.5, y: step == 0 ? h * 0.32 : h * 0.53) }
    switch step {
    case 0: return CGPoint(x: w * 0.7, y: h * 0.88)
    case 1: return CGPoint(x: 52, y: 39)
    case 2: return CGPoint(x: w * 0.66, y: 86)
    case 3: return CGPoint(x: w * 0.65, y: h * 0.36)
    default: return CGPoint(x: w * 0.65, y: h - 38)
    }
  }
}

private struct TutorialWidgetBounds: PreferenceKey {
  static var defaultValue: Anchor<CGRect>? { nil }
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = nextValue() ?? value
  }
}

private struct TutorialPlayback: Equatable {
  let step: Int
  let active: Bool
  let reducedMotion: Bool
}
