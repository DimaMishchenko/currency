import CurrencySupport
import ExchangeRates
import SwiftUI
import UIKit

/// App preferences, rate provenance, and setup entry points.
public struct SettingsScreen: View {
  private let snapshot: RateSnapshot
  private let codes: [String]
  private let isRefreshing: Bool
  private let warning: LocalizedStringResource?
  private let refresh: @MainActor () async -> Void
  private let manageLocation: () -> Void
  private let replayOnboarding: (() throws -> Void)?

  /// Creates settings from host-owned rate state and actions, without owning a rate service.
  /// - Parameters:
  ///   - snapshot: Latest rates and their retrieval/provenance timestamps.
  ///   - codes: Ordered currency codes whose quote information should be displayed.
  ///   - isRefreshing: Whether the host already has a refresh in flight.
  ///   - warning: Current localized rate or persistence warning, if any.
  ///   - refresh: Requests a manual refresh from the host's existing rate service.
  ///   - manageLocation: Opens first-time location setup or system permission settings.
  ///   - replayOnboarding: Restarts setup after saving its progress; nil hides the entry.
  public init(
    snapshot: RateSnapshot, codes: [String], isRefreshing: Bool,
    warning: LocalizedStringResource? = nil,
    refresh: @escaping @MainActor () async -> Void,
    manageLocation: @escaping () -> Void,
    replayOnboarding: (() throws -> Void)? = nil
  ) {
    self.snapshot = snapshot
    self.codes = codes
    self.isRefreshing = isRefreshing
    self.warning = warning
    self.refresh = refresh
    self.manageLocation = manageLocation
    self.replayOnboarding = replayOnboarding
  }
  @Environment(AppAppearance.self) private var appearance
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var replayFailed = false

  /// Presents app preferences, rate information, credits, and setup replay.
  public var body: some View {
    List {
      appearanceControls
      Section {
        Button(action: manageLocation) {
          Label(.Settings.locationSettings, systemImage: "location")
        }
        .accessibilityIdentifier("settings.location")
      } header: {
        Text(.Settings.location)
      } footer: {
        Text(.Settings.locationSettingsExplanation)
      }
      Section(.Settings.aboutRates) {
        NavigationLink {
          rateInformation
        } label: {
          Label {
            Text(.Settings.rates).foregroundStyle(Color.primary)
          } icon: {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.tint)
          }
        }
        NavigationLink {
          List { sourceInformation }
            .navigationTitle(.Settings.sources)
            .navigationBarTitleDisplayMode(.inline)
        } label: {
          Label {
            Text(.Settings.sources).foregroundStyle(Color.primary)
          } icon: {
            Image(systemName: "network").foregroundStyle(.tint)
          }
        }
        NavigationLink {
          List { acknowledgements }
            .navigationTitle(.Settings.acknowledgements)
            .navigationBarTitleDisplayMode(.inline)
        } label: {
          Label {
            Text(.Settings.acknowledgements).foregroundStyle(Color.primary)
          } icon: {
            Image(systemName: "heart").foregroundStyle(.tint)
          }
        }
      }
      if replayOnboarding != nil {
        Section {
          Button(.Settings.replayOnboarding, systemImage: "sparkles.rectangle.stack") {
            restartOnboarding()
          }
          .accessibilityIdentifier("settings.replayOnboarding")
        } header: {
          Text(.Settings.gettingStarted)
        }
      }
      Section {
        HStack {
          Label(.Settings.sendFeedback, systemImage: "bubble.left.and.bubble.right")
          Spacer(minLength: AppStyle.Space.medium)
          Text(.Settings.comingSoon)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.feedback")
      } footer: {
        Text(
          .Settings.appVersion(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
              ?? "—",
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
        )
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("settings.version")
      }
    }
    .navigationTitle(.Settings.settings)
    .navigationBarTitleDisplayMode(.large)
    .alert(.Settings.replayFailed, isPresented: $replayFailed) {
      Button(.Settings.retryReplay) { restartOnboarding() }
      Button(.Settings.close, role: .cancel) {}
    }
  }

  private var appearanceControls: some View {
    @Bindable var appearance = appearance
    return Section(.Settings.appearance) {
      Picker(selection: $appearance.theme) {
        ForEach(AppAppearance.Theme.allCases) { theme in
          Text(theme.title).tag(theme)
        }
      } label: {
        Label {
          Text(.Settings.theme).foregroundStyle(Color.primary)
        } icon: {
          Image(systemName: "circle.lefthalf.filled").foregroundStyle(.tint)
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("settings.theme")
      adaptiveLayout {
        Label {
          Text(.Settings.accentColor).foregroundStyle(Color.primary)
        } icon: {
          Image(systemName: "paintpalette").foregroundStyle(.tint)
        }
        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: AppStyle.Space.medium) }
        Menu {
          Picker(.Settings.accentColor, selection: $appearance.accentSelection) {
            ForEach(AppAppearance.Accent.allCases) { accent in
              Label {
                Text(accent.title)
              } icon: {
                if let symbol = UIImage(systemName: "circle.fill") {
                  Image(
                    uiImage: symbol.withTintColor(
                      UIColor(accent.color), renderingMode: .alwaysOriginal)
                  )
                  .renderingMode(.original)
                }
              }
              .tag(accent)
            }
          }
          .pickerStyle(.inline)
        } label: {
          HStack(spacing: AppStyle.Space.small) {
            Circle().fill(appearance.accent).frame(width: 18, height: 18)
            Text(appearance.accentSelection.title)
            Image(systemName: "chevron.up.chevron.down")
              .font(AppStyle.font(.caption, weight: .semibold))
          }
          .foregroundStyle(.tint)
          .contentShape(Rectangle())
        }
        .accessibilityLabel(.Settings.accentColor)
        .accessibilityIdentifier("settings.accent")
        .accessibilityValue(Text(appearance.accentSelection.title))
        .onChange(of: appearance.accentSelection) { _, _ in AppHaptics.play(.selection) }
      }
    }
  }

  private func restartOnboarding() {
    do { try replayOnboarding?(); AppHaptics.play(.transition) } catch {
      replayFailed = true
      AppHaptics.play(.error)
    }
  }

  private var adaptiveLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppStyle.Space.xs))
      : AnyLayout(HStackLayout(spacing: AppStyle.Space.small))
  }

  private func timestamp(_ date: Date) -> String {
    date.formatted(.dateTime.day().month().year().hour().minute().locale(locale))
  }

  private func timestampRow(_ title: LocalizedStringResource, date: Date?) -> some View {
    adaptiveLayout {
      Text(title)
      if !dynamicTypeSize.isAccessibilitySize { Spacer() }
      Text(date.map(timestamp) ?? String(localized: .Settings.unavailable))
        .foregroundStyle(.secondary)
    }
  }

  private func sourceCredit(
    _ name: String, description: LocalizedStringResource, website: String,
    license: String? = nil, licenseURL: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.small) {
      if let website = URL(string: website) {
        Link(destination: website) {
          HStack {
            Text(verbatim: name).font(AppStyle.font(.headline)).foregroundStyle(Color.primary)
            Spacer()
            Image(systemName: "arrow.up.right").font(AppStyle.font(.caption))
          }
        }
      }
      Text(description).font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
      if let license, let licenseURL, let url = URL(string: licenseURL) {
        Link(destination: url) {
          Label(license, systemImage: "doc.text")
            .font(AppStyle.font(.caption, weight: .medium))
        }
      }
    }
    .padding(.vertical, AppStyle.Space.small)
  }

  private var rateInformation: some View {
    List {
      Section {
        timestampRow(
          .Settings.ratesRetrieved,
          date: snapshot.fetchedAt == .distantPast ? nil : snapshot.fetchedAt)
        timestampRow(.Settings.lastChecked, date: snapshot.checkedAt)
        Button(.Settings.refreshNow, systemImage: "arrow.clockwise") {
          Task { await refresh() }
        }
        .disabled(isRefreshing)
        if let warning {
          Text(warning).font(AppStyle.font(.caption)).foregroundStyle(.secondary)
        }
      } header: {
        Text(.Settings.rates)
      } footer: {
        Text(.Settings.dailyRateExplanation)
      }
      Section(.Settings.quoteInformation) {
        ForEach(codes, id: \.self) { code in
          HStack(alignment: .top, spacing: AppStyle.Space.medium) {
            CurrencyIcon(code, size: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
              Text(verbatim: code).font(AppStyle.font(.body, weight: .medium))
              if let rate = snapshot.quotes[code] {
                Text(RateMessages.providerDescription(rate.source, locale: locale))
                  .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
                Group {
                  if let observed = rate.observedAt {
                    Text(.Settings.observedAt(timestamp(observed)))
                  } else if let retrieved = rate.retrievedAt {
                    Text(.Settings.quoteRetrieved(timestamp(retrieved)))
                  } else {
                    Text(
                      .Settings.publishedAt(
                        CurrencyDisplay.publicationDate(rate.published, locale: locale)))
                  }
                }
                .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
              } else {
                Text(.Settings.notDownloaded)
                  .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
              }
            }
          }
          .padding(.vertical, AppStyle.Space.xs)
          .accessibilityElement(children: .combine)

        }
      }
    }
    .navigationTitle(.Settings.rates)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var sourceInformation: some View {
    Section(.Settings.sources) {
      sourceCredit(
        "Frankfurter", description: .Settings.frankfurterCredit,
        website: "https://frankfurter.dev/")
      sourceCredit(
        "European Central Bank", description: .Settings.ecbCredit,
        website:
          "https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html"
      )
      sourceCredit(
        "Fawaz Exchange API", description: .Settings.fawazCredit,
        website: "https://github.com/fawazahmed0/exchange-api")
      sourceCredit(
        "Coinbase", description: .Settings.coinbaseCredit,
        website: "https://docs.cdp.coinbase.com/coinbase-app/track-apis/exchange-rates")
    }
  }

  private var acknowledgements: some View {
    Section(.Settings.artwork) {
      sourceCredit(
        "Web3 Icons", description: .Settings.web3Credit,
        website: "https://github.com/0xa3k5/web3icons",
        license: "MIT",
        licenseURL:
          "https://github.com/0xa3k5/web3icons/blob/64e21e68cc6eaa36ff9d0a135ca2c809a759ccd6/LICENCE"
      )
      sourceCredit(
        "Cryptocurrency Icons", description: .Settings.dogeCredit,
        website: "https://github.com/spothq/cryptocurrency-icons",
        license: "CC0 1.0",
        licenseURL:
          "https://github.com/spothq/cryptocurrency-icons/blob/1a63530be6e374711a8554f31b17e4cb92c25fa5/LICENSE.md"
      )
    }
  }
}

private extension AppAppearance.Theme {
  var title: LocalizedStringResource {
    switch self {
    case .system: .Settings.appearanceSystem
    case .light: .Settings.appearanceLight
    case .dark: .Settings.appearanceDark
    }
  }
}

private extension AppAppearance.Accent {
  var title: LocalizedStringResource {
    switch self {
    case .primary: .Settings.appearancePrimary
    case .blue: .Settings.appearanceBlue
    case .indigo: .Settings.appearanceIndigo
    case .purple: .Settings.appearancePurple
    case .pink: .Settings.appearancePink
    case .red: .Settings.appearanceRed
    case .orange: .Settings.appearanceOrange
    case .green: .Settings.appearanceGreen
    case .teal: .Settings.appearanceTeal
    }
  }
}
