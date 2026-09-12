import CurrencySelectionUI
import CurrencySupport
import SwiftUI
import WidgetKit
import WidgetPresentation

struct WidgetGuide: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var selection: WidgetShowcaseKind?
  @State private var selectedFamily: WidgetFamily = .systemMedium
  @State private var selectedSource = ""
  @Namespace private var expansion
  @State private var tutorial = false
  @State private var collection = false
  @State private var paused = false
  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 12) {
            WidgetGalleryWall(
              moving: !paused && selection == nil && !tutorial && !collection,
              selection: $selection, selectedFamily: $selectedFamily,
              selectedSource: $selectedSource, expansion: expansion
            )
            .frame(
              height: textSize.isAccessibilitySize ? 220 : max(160, geometry.size.height - 208)
            )
            .accessibilityRepresentation {
              Button(.WidgetOnboarding.guideExploreCollection) { collection = true }
            }
            .overlay(alignment: .bottomTrailing) {
              if !reduceMotion {
                Button(
                  paused
                    ? String(localized: .WidgetOnboarding.guidePlayMotion)
                    : String(localized: .WidgetOnboarding.guidePauseMotion),
                  systemImage: paused ? "play.fill" : "pause.fill"
                ) {
                  paused.toggle()
                }
                .font(.subheadline).labelStyle(.iconOnly)
                .buttonStyle(.plain).frame(width: 44, height: 44)
                .background(.thinMaterial, in: .circle)
                .padding(.trailing, 24).padding(.bottom, 8)
              }
            }
            VStack(spacing: 12) {
              Text(.WidgetOnboarding.guideHeadline)
                .font(AppStyle.font(.largeTitle, weight: .semibold))
                .tracking(-0.8).lineSpacing(-2)
                .accessibilityAddTraits(.isHeader)
              Text(.WidgetOnboarding.guideSummary)
                .font(AppStyle.font(.body)).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24).padding(.bottom, 20)
            if textSize.isAccessibilitySize { actions }
          }
        }
        .scrollIndicators(.hidden)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if !textSize.isAccessibilitySize { actions }
      }
      .navigationTitle(.WidgetOnboarding.widgets).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.WidgetOnboarding.close, systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
        }
      }
      .sheet(item: $selection) { kind in
        WidgetPlayground(kind: kind, family: selectedFamily)
          .navigationTransition(.zoom(sourceID: selectedSource, in: expansion))
      }
      .sheet(isPresented: $tutorial) { WidgetTutorial(kind: .calculator) }
      .sheet(isPresented: $collection) { WidgetCollection() }
    }
  }
  private var actions: some View {
    VStack(spacing: 4) {
      Button {
        tutorial = true
      } label: {
        Text(.WidgetOnboarding.guideAddWidget)
          .font(AppStyle.font(.headline)).frame(maxWidth: .infinity).padding(.vertical, 8)
      }
      .foregroundStyle(Color(uiColor: .systemBackground))
      .buttonStyle(.borderedProminent).controlSize(.large)
      Button(.WidgetOnboarding.guideExploreCollection) { collection = true }
        .font(AppStyle.font(.subheadline, weight: .medium)).frame(minHeight: 44)
    }
    .padding(.horizontal, 24).padding(.top, 8)
    .background(Color(uiColor: .systemGroupedBackground))
  }

}

/// A continuous gallery of real widgets. Each column loops at its own measured height.
private struct WidgetGalleryWall: View {
  let moving: Bool
  @Binding var selection: WidgetShowcaseKind?
  @Binding var selectedFamily: WidgetFamily
  @Binding var selectedSource: String
  let expansion: Namespace.ID
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var elapsed: TimeInterval = 0
  @State private var started = Date.now
  private var running: Bool { moving && !reduceMotion && scenePhase == .active }
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 60, paused: !running)) { context in
      let time = elapsed + (running ? context.date.timeIntervalSince(started) : 0)
      GeometryReader { geometry in
        let width = min(280, geometry.size.width * 0.52)
        HStack(alignment: .top, spacing: 12) {
          column(width: width, time: time, reverse: false)
          column(width: width, time: time, reverse: true)
        }
        .frame(width: width * 2 + 12, alignment: .top)
        .offset(x: (geometry.size.width - width * 2 - 12) / 2)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
      }
    }
    .clipped()
    .contentShape(.rect)
    .mask {
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0), .init(color: .black, location: 0.08),
          .init(color: .black, location: 0.82), .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
    .onChange(of: running) { _, value in
      if value { started = .now } else { elapsed += Date.now.timeIntervalSince(started) }
    }
  }
  private func column(width: CGFloat, time: TimeInterval, reverse: Bool) -> some View {
    let small = (width - 12) / 2
    let medium = width * 164 / 348
    let large = width * 364 / 348
    let cycle = medium * 2 + small + large + 48
    let travel = CGFloat(time * 10).truncatingRemainder(dividingBy: cycle)
    return VStack(spacing: 12) {
      ForEach(0..<3) { repetition in
        VStack(spacing: 12) {
          if reverse {
            card(.calculator, .systemLarge, width: width, source: "right-\(repetition)-calculator")
            HStack(spacing: 12) {
              card(.mental, .systemSmall, width: small, source: "right-\(repetition)-mental")
              card(.pocket, .systemSmall, width: small, source: "right-\(repetition)-pocket")
            }
            card(.board, .systemMedium, width: width, source: "right-\(repetition)-board")
            card(.cash, .systemMedium, width: width, source: "right-\(repetition)-cash")
          } else {
            card(.calculator, .systemMedium, width: width, source: "left-\(repetition)-calculator")
            card(.cash, .systemMedium, width: width, source: "left-\(repetition)-cash")
            HStack(spacing: 12) {
              card(.pocket, .systemSmall, width: small, source: "left-\(repetition)-pocket")
              card(.mental, .systemSmall, width: small, source: "left-\(repetition)-mental")
            }
            card(.board, .systemLarge, width: width, source: "left-\(repetition)-board")
          }
        }
      }
    }
    .frame(width: width)
    .offset(y: reverse ? travel - cycle : -travel)
  }
  private func card(
    _ kind: WidgetShowcaseKind, _ family: WidgetFamily, width: CGFloat, source: String
  ) -> some View {
    Button {
      selectedFamily = family
      selectedSource = source
      selection = kind
    } label: {
      FittedWidgetPreview(kind: kind, family: family)
        .frame(width: width, height: width * family.previewSize.height / family.previewSize.width)
        .overlay { Color.clear.contentShape(.rect) }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
    .buttonStyle(.plain)
    .matchedTransitionSource(id: source, in: expansion)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(.WidgetOnboarding.guideExploreWidget(kind.title, family.showcaseTitle))
  }
}

private struct WidgetCollection: View {
  @Environment(\.localCurrencyDestination) private var localCurrencyDestination
  @Environment(\.dismiss) private var dismiss
  @State private var selection: WidgetShowcaseKind?
  @State private var location = false
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 40) {
          VStack(alignment: .leading, spacing: 8) {
            Text(.WidgetOnboarding.collectionHeadline)
              .font(AppStyle.font(.largeTitle, weight: .bold)).tracking(-0.7)
            Text(.WidgetOnboarding.collectionSummary)
              .font(AppStyle.font(.body)).foregroundStyle(.secondary)
          }
          ForEach(WidgetShowcaseKind.allCases) { kind in
            Button {
              selection = kind
            } label: {
              VStack(alignment: .leading, spacing: 16) {
                ZStack {
                  RoundedRectangle(cornerRadius: 32).fill(.quaternary.opacity(0.5))
                  if kind == .quick {
                    VStack(spacing: 8) {
                      Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(AppStyle.font(.caption))
                      Text("9:41").font(.system(size: 56, weight: .semibold, design: .rounded))
                      FittedWidgetPreview(kind: kind, family: .accessoryRectangular)
                        .frame(width: 170)
                    }
                    .padding(32)
                  } else {
                    FittedWidgetPreview(kind: kind, family: kind.families[0])
                      .frame(maxWidth: kind.families[0] == .systemSmall ? 172 : 320)
                      .padding(24)
                      .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
                  }
                }
                .frame(minHeight: 212).contentShape(.rect)
                HStack(alignment: .top) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title).font(AppStyle.font(.title3, weight: .semibold))
                    Text(kind.detail).font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
                  }
                  Spacer(minLength: 8)
                  Image(systemName: "arrow.up.right").font(.body)
                    .padding(12).background(.quaternary, in: .circle)
                }
              }
            }
            .buttonStyle(.plain).accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.title).accessibilityHint(kind.detail)
          }
          Button {
            location = true
          } label: {
            HStack(spacing: 16) {
              Image(systemName: "location").font(.title2)
              VStack(alignment: .leading, spacing: 4) {
                Text(.WidgetOnboarding.localCollectionTitle).font(AppStyle.font(.headline))
                Text(.WidgetOnboarding.localSetupAction).font(AppStyle.font(.subheadline))
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
              Image(systemName: "chevron.right").font(.caption)
            }
            .padding(20).background(.background, in: .rect(cornerRadius: 24))
          }
          .buttonStyle(.plain)
        }
        .padding(24)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle(.WidgetOnboarding.collectionTitle).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.WidgetOnboarding.close, systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
        }
      }
      .sheet(item: $selection) { WidgetPlayground(kind: $0) }
      .sheet(isPresented: $location) { localCurrencyDestination() }
    }
  }
}

struct WidgetPlayground: View {
  let kind: WidgetShowcaseKind
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var family: WidgetFamily
  @State private var replay = UUID()
  @State private var tutorial = false
  @State private var edit = false
  init(kind: WidgetShowcaseKind, family: WidgetFamily? = nil) {
    self.kind = kind; _family = State(initialValue: family ?? kind.families[0])
  }
  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 20) {
            HStack {
              Text(.WidgetOnboarding.previewSampleRates).font(AppStyle.font(.caption))
                .foregroundStyle(.secondary)
              Spacer()
              if kind.interactive {
                Button(.WidgetOnboarding.previewReset, systemImage: "arrow.counterclockwise") {
                  replay = UUID()
                }
                .font(AppStyle.font(.subheadline))
              }
            }
            if kind.families.count > 1 {
              Picker(.WidgetOnboarding.previewSize, selection: $family) {
                ForEach(kind.families, id: \.self) { Text($0.showcaseTitle).tag($0) }
              }
              .pickerStyle(.segmented)
            }
            Spacer(minLength: 0)
            if kind == .quick {
              lockScreenPreview
            } else if kind == .calculator {
              let width = min(380, geometry.size.width - 48)
              AnimatedCalculatorPreview(progress: family == .systemMedium ? 0 : 1, width: width)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: family)
                .id(replay)
                .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
            } else if kind == .board {
              AnimatedWidgetFamilyPreview(
                kind: .board, family: family, maximumWidth: min(380, geometry.size.width - 48),
                availableHeight: max(220, geometry.size.height - 212)
              )
              .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
            } else {
              let available = max(220, geometry.size.height - 212)
              FittedWidgetPreview(kind: kind, family: family, interactive: true)
                .animation(
                  reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.88), value: family
                )
                .id(replay)
                .frame(
                  maxWidth: family == .systemSmall
                    ? 220
                    : min(380, available * family.previewSize.width / family.previewSize.height)
                )
                .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
            }
            Spacer(minLength: 0)
            Text(
              kind.interactive
                ? (kind == .calculator
                  ? String(localized: .WidgetOnboarding.previewCalculatorHint)
                  : String(localized: .WidgetOnboarding.previewCashHint))
                : kind.detail
            )
            .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if textSize.isAccessibilitySize { actions }
          }
          .padding(24).frame(minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if !textSize.isAccessibilitySize { actions }
      }
      .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.WidgetOnboarding.close, systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
        }
      }
      .sheet(isPresented: $tutorial) { WidgetTutorial(kind: kind, family: family) }
      .sheet(isPresented: $edit) { WidgetTutorial(kind: kind, family: family, editing: true) }
    }
  }

  private var actions: some View {
    VStack(spacing: 4) {
      Button {
        tutorial = true
      } label: {
        Text(
          kind == .quick
            ? String(localized: .WidgetOnboarding.guideAddLockScreen)
            : String(localized: .WidgetOnboarding.guideAddHomeScreen)
        )
        .font(AppStyle.font(.headline)).frame(maxWidth: .infinity).padding(.vertical, 8)
      }
      .foregroundStyle(Color(uiColor: .systemBackground))
      .buttonStyle(.borderedProminent).controlSize(.large)
      if kind == .quick {
        Text(.WidgetOnboarding.quickFollowsApp).font(AppStyle.font(.caption))
          .foregroundStyle(.secondary).frame(minHeight: 44)
      } else {
        Button(.WidgetOnboarding.guideEditWidget) { edit = true }
          .font(AppStyle.font(.subheadline, weight: .medium)).frame(minHeight: 44)
      }
    }
    .padding(.horizontal, textSize.isAccessibilitySize ? 0 : 24).padding(.top, 12)
    .background(Color(uiColor: .systemGroupedBackground))
  }
  private var lockScreenPreview: some View {
    VStack(spacing: 8) {
      if family == .accessoryInline {
        HStack(spacing: 4) {
          Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day()))
            .font(.system(size: 13, weight: .medium, design: .rounded)).fixedSize()
          FittedWidgetPreview(kind: .quick, family: family).frame(height: 28)
        }
      } else {
        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
          .font(AppStyle.font(.subheadline))
      }
      Text("9:41").font(.system(size: 76, weight: .semibold, design: .rounded))
      if family == .accessoryRectangular {
        FittedWidgetPreview(kind: .quick, family: family).frame(width: 170).padding(.top, 8)
      }
      Spacer(minLength: 48)
      HStack {
        Image(systemName: "flashlight.off.fill").padding(16)
          .background(.regularMaterial, in: .circle)
        Spacer()
        Image(systemName: "camera.fill").padding(16).background(.regularMaterial, in: .circle)
      }
      .font(.body)
    }
    .padding(24).frame(height: 320)
    .background(
      LinearGradient(
        colors: [Color.blue.opacity(0.17), Color.cyan.opacity(0.07), Color.indigo.opacity(0.18)],
        startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 32)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(.WidgetOnboarding.quickSampleScreenAccessibility)
  }

}
