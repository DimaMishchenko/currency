import AppearancePreferences
import CurrencyApplication
import CurrencyDetails
import CurrencyDetailsUI
import DesignSystem
import HomeUI
import LocalCurrency
import LocationOnboardingUI
import OnboardingUI
import SettingsUI
import SwiftUI
import WidgetOnboarding
import WidgetOnboardingUI

struct CurrencyRoot: View {
  let composition: AppComposition
  @State private var scene: CurrencyScene
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var widgetsMotion
  @Namespace private var detailsMotion
  init(composition: AppComposition) {
    self.composition = composition
    _scene = State(initialValue: composition.makeScene())
  }
  private var appearance: AppAppearance {
    AppAppearance(
      theme: .init(rawValue: composition.appearance.theme.rawValue) ?? .system,
      accent: .init(rawValue: composition.appearance.accent.rawValue) ?? .primary,
      onThemeChange: { composition.appearance.theme = .init(rawValue: $0.rawValue) ?? .system },
      onAccentChange: { composition.appearance.accent = .init(rawValue: $0.rawValue) ?? .primary })
  }
  var body: some View {
    @Bindable var scene = scene
    let onboardingID = scene.onboardingID
    ZStack {
      if scene.preloadsHome {
        NavigationStack(path: $scene.path) {
          HomeEntry(
            flowID: scene.homeID, active: !scene.showsOnboarding && scenePhase == .active,
            detailsNamespace: detailsMotion, widgetsNamespace: widgetsMotion,
            onOutput: scene.receive
          )
          .navigationDestination(for: CurrencyScene.Route.self) { route in
            switch route {
            case .settings(let id):
              SettingsEntry(flowID: id)
                .environment(\.settingsDependencies, composition.settings(scene: scene))
            }
          }
        }
        .allowsHitTesting(!scene.showsOnboarding)
        .accessibilityHidden(scene.showsOnboarding)
      }
      if scene.showsOnboarding {
        OnboardingEntry(flowID: onboardingID, onOutput: { scene.receive($0, flowID: onboardingID) })
        { step, snapshot, input, guide, finished in
          if step == .homeScreen {
            OnboardingHomeScreen(snapshot: snapshot, input: input)
          } else {
            OnboardingWidgetShowcase(
              snapshot: snapshot, input: input, guideRequested: guide, onGuideFinished: finished)
          }
        }
        .transition(.opacity).zIndex(1)
      }
    }
    .animation(
      reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.65),
      value: scene.showsOnboarding
    )
    .sheet(item: $scene.detail) { detail in
      if reduceMotion {
        detailsContent(detail)
      } else {
        detailsContent(detail)
          .navigationTransition(.zoom(sourceID: detail.request.selectionID, in: detailsMotion))
      }
    }
    .sheet(item: $scene.sheet, onDismiss: composition.changed) { sheet in
      sheetContent(sheet)
        .sheet(item: applicationLocation, onDismiss: composition.changed) { location in
          locationContent(location)
        }
    }
    .sheet(item: rootLocation, onDismiss: composition.changed) { location in
      locationContent(location)
    }
    .environment(
      \.widgetOnboardingDependencies,
      WidgetOnboardingDependencies(output: { output in
        switch output {
        case .locationRequested: scene.requestLocation(addsToApp: false)
        case .closed: scene.sheet = nil
        }
      })
    )
    .environment(
      \.widgetOnboardingPresentation,
      WidgetOnboardingPresentation { content in
        AnyView(WidgetLocationPresenter(composition: composition, scene: scene, content: content))
      }
    )
    .environment(\.homeDependencies, composition.home)
    .environment(\.onboardingDependencies, composition.onboarding)
    .environment(\.currencyDetailsDependencies, composition.details)
    .environment(appearance)
    .tint(appearance.accent)
    .preferredColorScheme(appearance.theme.colorScheme)
    .onOpenURL(perform: scene.open)
    .onChange(of: scenePhase, initial: true) { _, phase in
      AppHaptics.configure(active: phase == .active, reducedMotion: reduceMotion)
      composition.foreground.setActive(
        phase == .active && !scene.showsOnboarding, sceneID: scene.id)
    }
    .onChange(of: scene.showsOnboarding) { _, shows in
      composition.foreground.setActive(scenePhase == .active && !shows, sceneID: scene.id)
    }
    .onChange(of: reduceMotion) { _, value in
      AppHaptics.configure(active: scenePhase == .active, reducedMotion: value)
    }
    .onDisappear { composition.foreground.setActive(false, sceneID: scene.id) }
  }
  private var rootLocation: Binding<CurrencyScene.Location?> {
    Binding(
      get: { scene.sheet == nil ? scene.locationPresented(by: nil) : nil },
      set: { if scene.sheet == nil { applicationLocation.wrappedValue = $0 } })
  }
  private var applicationLocation: Binding<CurrencyScene.Location?> {
    Binding(
      get: { scene.locationPresented(by: nil) },
      set: { value in
        if value == nil, let location = scene.locationPresented(by: nil) {
          scene.finishLocation(id: location.id)
        }
      })
  }
  @ViewBuilder private func sheetContent(_ sheet: CurrencyScene.Sheet) -> some View {
    switch sheet.kind {
    case .widgets:
      if reduceMotion {
        WidgetOnboardingEntry(flowID: sheet.id)
      } else {
        WidgetOnboardingEntry(flowID: sheet.id)
          .navigationTransition(.zoom(sourceID: "widgets", in: widgetsMotion))
      }
    }
  }
  private func detailsContent(_ detail: CurrencyScene.Details) -> some View {
    CurrencyDetailsEntry(
      flowID: detail.id,
      input: CurrencyDetailsInput(
        code: detail.request.code, reference: detail.request.reference,
        snapshot: detail.request.snapshot))
  }
  private func locationContent(_ location: CurrencyScene.Location) -> some View {
    LocationHost(composition: composition, scene: scene, location: location).id(location.id)
  }
}

private struct LocationHost: View {
  let composition: AppComposition
  let scene: CurrencyScene
  let location: CurrencyScene.Location
  @State private var controller: LocalCurrencyController
  init(composition: AppComposition, scene: CurrencyScene, location: CurrencyScene.Location) {
    self.composition = composition; self.scene = scene; self.location = location
    _controller = State(initialValue: composition.makeLocationController())
  }
  var body: some View {
    LocationOnboardingEntry(
      flowID: location.id,
      addsResolvedCurrencyToApp: location.addsToApp
        && !composition.conversion.input().usesLocalCurrency
    )
    .environment(
      \.locationOnboardingDependencies,
      composition.location(controller: controller, scene: scene, id: location.id))
  }
}

/// Lives at the requesting widget modal level so a location sheet can stack above it.
private struct WidgetLocationPresenter: View {
  let composition: AppComposition
  let scene: CurrencyScene
  let content: AnyView
  @State private var presenterID = UUID()

  private var location: Binding<CurrencyScene.Location?> {
    Binding(
      get: { scene.locationPresented(by: presenterID) },
      set: { value in
        if value == nil, let location = scene.locationPresented(by: presenterID) {
          scene.finishLocation(id: location.id)
        }
      })
  }

  var body: some View {
    content
      .environment(
        \.widgetOnboardingDependencies,
        WidgetOnboardingDependencies { output in
          switch output {
          case .locationRequested:
            scene.requestLocation(addsToApp: false, presenterID: presenterID)
          case .closed:
            scene.sheet = nil
          }
        }
      )
      .sheet(item: location, onDismiss: composition.changed) { location in
        LocationHost(composition: composition, scene: scene, location: location).id(location.id)
      }
  }
}
