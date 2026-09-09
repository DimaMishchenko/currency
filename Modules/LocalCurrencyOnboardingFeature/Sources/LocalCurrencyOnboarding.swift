import CurrencySelectionUI
import CurrencySupport
import MapKit
import SwiftUI
import WidgetKit

/// On-demand country lookup, permission recovery, and manual currency selection.
public struct LocalCurrencyOnboardingScreen: View {
  /// Creates the local-currency onboarding flow without requesting permission.
  public init() {}
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var location = WidgetLocationController()
  @State private var manualPicker = false
  @State private var manage = false
  @State private var manualCode: String?
  @State private var manualSaved = false
  @State private var manualError = false
  private var ready: Bool {
    manualCode == nil && location.phase == .ready && location.resolved != nil
  }
  /// The permission explanation and location result.
  public var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 24) {
            illustration.frame(
              height: textSize.isAccessibilitySize
                ? 156 : min(256, max(156, geometry.size.height - 300))
            )
            .clipShape(.rect(cornerRadius: 32))
            .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: ready)
            VStack(spacing: 12) {
              Text(title).font(AppStyle.font(.largeTitle, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
              Text(detail).font(AppStyle.font(.body)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            if location.isUpdating {
              ProgressView(
                location.phase == .requestingPermission
                  ? String(localized: .LocalCurrency.localAwaitingPermission)
                  : String(localized: .LocalCurrency.localFindingProgress)
              )
              .font(AppStyle.font(.subheadline)).frame(minHeight: 44)
            }

            if manualError {
              Text(.LocalCurrency.localManualSaveFailed).font(AppStyle.font(.caption))
                .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
              if manualCode == nil {
                Label(.LocalCurrency.localPrivacySummary, systemImage: "location")
                  .font(AppStyle.font(.subheadline))
                Text(.LocalCurrency.localPrivacyDetail)
                  .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
              } else {
                Label(.LocalCurrency.localManualPrivacy, systemImage: "location.slash")
                  .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
              }
            }
            .multilineTextAlignment(.center)
            if textSize.isAccessibilitySize { actions }
          }
          .padding(24)
        }
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if !textSize.isAccessibilitySize { actions }
      }
      .navigationTitle(.LocalCurrency.guideLocalCurrency).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.LocalCurrency.close, systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
        }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { location.reconcileAuthorization() }
      }
      .onDisappear { location.cancel() }
      .confirmationDialog(.LocalCurrency.guideLocalCurrency, isPresented: $manage) {
        Button(.LocalCurrency.localUpdateAction) { location.update() }
        Button(.LocalCurrency.localChooseManually) { manualPicker = true }
        Button(.LocalCurrency.localClearAction, role: .destructive) { location.clear() }
      }
      .sheet(isPresented: $manualPicker) {
        CurrencyChooser(
          purpose: .add, selected: [], homeCurrencies: [],
          available: Set(CurrencyStore.shared.loadRates().quotes.keys)
        ) {
          manualCode = $0; manualSaved = false; manualError = false
        }
      }
    }
  }
  private var actions: some View {
    VStack(spacing: 8) {
      if ready || manualSaved {
        primary(String(localized: .LocalCurrency.done)) { dismiss() }
      } else if manualCode != nil {
        primary(String(localized: .LocalCurrency.localUseInApp)) { saveManualCurrency() }
      } else if location.permissionDenied || location.servicesDisabled {
        primary(String(localized: .LocalCurrency.openLocationSettings)) {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
      } else if !location.permissionRestricted {
        primary(
          location.phase == .unavailable
            ? String(localized: .LocalCurrency.localRetry)
            : String(localized: .LocalCurrency.localUseLocation)
        ) {
          location.update()
        }
        .disabled(location.isUpdating)
      }
      if ready {
        Button(.LocalCurrency.localChangeAction) { manage = true }
          .font(AppStyle.font(.subheadline)).frame(minHeight: 44)
      } else {
        Button(.LocalCurrency.localChooseManually) {
          location.cancel(); manualPicker = true
        }
        .font(AppStyle.font(.subheadline)).frame(minHeight: 44)
      }
    }
    .padding(.horizontal, textSize.isAccessibilitySize ? 0 : 24).padding(.vertical, 12)
    .background(Color(uiColor: .systemGroupedBackground))
  }
  private var title: String {
    if let manualCode { return CurrencyDisplay.name(manualCode) }
    if ready, let resolved = location.resolved { return CurrencyDisplay.name(resolved.currency) }
    if location.isUpdating { return String(localized: .LocalCurrency.localFindingTitle) }
    if location.phase == .unavailable {
      return String(localized: .LocalCurrency.localRecoveryTitle)
    }
    return String(localized: .LocalCurrency.localIntroTitle)
  }
  private var detail: String {
    if manualCode != nil {
      return String(
        localized: manualSaved
          ? .LocalCurrency.localManualSaved : .LocalCurrency.localManualInstructions)
    }
    if ready, let code = location.resolved?.currency {
      return String(localized: .LocalCurrency.localReadyCurrency(code))
    }
    if location.phase == .unavailable { return String(localized: location.status) }
    if location.isUpdating { return String(localized: .LocalCurrency.localFindingDetail) }
    return String(localized: .LocalCurrency.localIntroDetail)
  }
  @ViewBuilder private var illustration: some View {
    if ready, let region = location.region, let resolved = location.resolved {
      Map(initialPosition: .region(region), interactionModes: []) {}
        .mapStyle(
          .standard(
            elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false
          )
        )
        .overlay {
          HStack(spacing: 12) {
            CurrencyIcon(resolved.currency, size: 40)
            VStack(alignment: .leading, spacing: 4) {
              Text(resolved.currency).font(AppStyle.font(.title, weight: .semibold))
              Text(
                Locale.current.localizedString(forRegionCode: resolved.country) ?? resolved.country
              )
              .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
            }
          }
          .padding(.horizontal, 24).padding(.vertical, 20)
          .background(.regularMaterial, in: .rect(cornerRadius: 28))
          .overlay(alignment: .topTrailing) {
            Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
              .foregroundStyle(Color(uiColor: .systemBackground), Color.primary)
              .font(.title2).offset(x: 8, y: -8)
          }
          .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
          .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          .LocalCurrency.localRegionMap(
            Locale.current.localizedString(forRegionCode: resolved.country) ?? resolved.country)
        )
        .transition(.opacity)
    } else {
      CurrencyOrbit(
        active: location.isUpdating, code: manualCode ?? (ready ? location.resolved?.currency : nil)
      )
    }
  }
  private func saveManualCurrency() {
    guard let manualCode else { return }
    do {
      try CurrencyStore.shared.updateInput { input in
        if input.source != manualCode { input.setDestinations(input.destinations + [manualCode]) }
      }
      WidgetCenter.shared.reloadAllTimelines()
      manualSaved = true
      manualError = false
    } catch { manualError = true }
  }
  private func primary(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(AppStyle.font(.headline)).frame(maxWidth: .infinity).padding(.vertical, 8)
    }
    .foregroundStyle(Color(uiColor: .systemBackground))
    .buttonStyle(.borderedProminent).controlSize(.large)
  }
}

private struct CurrencyOrbit: View {
  let active: Bool
  let code: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var phaseOrigin = Date.now
  @State private var phaseOffset: TimeInterval = 0
  @State private var speed: Double = 1 / 18
  private var running: Bool { !reduceMotion && scenePhase == .active }
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 60, paused: !running)) { context in
      let phase =
        reduceMotion
        ? 0 : phaseOffset + (running ? context.date.timeIntervalSince(phaseOrigin) * speed : 0)
      GeometryReader { geometry in
        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let radius = min(geometry.size.width, geometry.size.height) * 0.36
        let scale = min(1, geometry.size.height / 256)
        ZStack {
          Circle().strokeBorder(.primary.opacity(0.05), lineWidth: 1)
            .frame(width: radius * 2.5, height: radius * 2.5)
          Circle().strokeBorder(.primary.opacity(0.10), lineWidth: 1)
            .frame(width: radius * 2, height: radius * 2)
          Circle().fill(.background).frame(width: 88 * scale, height: 88 * scale)
            .shadow(color: .black.opacity(0.05), radius: 16, y: 8)
            .overlay {
              if let code {
                Text(code).font(.system(size: 22 * scale, weight: .medium, design: .rounded))
              } else {
                Image(systemName: "location").font(.system(size: 32 * scale, weight: .light))
              }
            }
          ForEach(Array(["€", "$", "£", "¥", "₩", "₹"].enumerated()), id: \.offset) {
            index, symbol in
            let angle = Double(index) * .pi / 3 + phase
            Text(symbol).font(.system(size: 24 * scale, weight: .light, design: .rounded))
              .frame(width: 48 * scale, height: 48 * scale).background(.background, in: .circle)
              .overlay { Circle().strokeBorder(.primary.opacity(0.06), lineWidth: 1) }
              .offset(x: cos(angle) * radius, y: sin(angle) * radius)
          }
        }
        .position(center)
      }
    }
    .accessibilityHidden(true)
    .onChange(of: active) { _, value in
      if running { phaseOffset += Date.now.timeIntervalSince(phaseOrigin) * speed }
      phaseOrigin = .now
      speed = value ? 1 / 6 : 1 / 18
    }
    .onChange(of: running) { wasRunning, _ in
      if wasRunning { phaseOffset += Date.now.timeIntervalSince(phaseOrigin) * speed }
      phaseOrigin = .now
    }
  }
}
