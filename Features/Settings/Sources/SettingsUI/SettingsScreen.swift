import DesignSystem
import ExchangeRates
import ExchangeRatesUI
import MessageUI
import Settings
import SwiftUI
import UIKit

struct SettingsScreen: View {
  @Bindable var model: SettingsModel
  private var snapshot: RateSnapshot { model.rates.snapshot }
  private var codes: [String] { model.rates.codes }
  private var isRefreshing: Bool { model.isRefreshing }
  private var warning: LocalizedStringResource? {
    model.issue == .refreshFailed
      ? .Settings.refreshFailed : RateMessages.refresh(model.rates.warning)
  }
  private func manageLocation() { model.manageLocation() }
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openURL) private var openURL
  @State private var replayFailed = false
  @State private var showsFeedbackOptions = false
  @State private var pendingFeedbackEmail = false
  @State private var showsFeedbackComposer = false
  @State private var showsMailUnavailable = false
  @State private var pendingMailFailure = false
  @State private var mailSendFailed = false
  @State private var creatorCoinSpinStartedAt: Date?
  @State private var creatorCoinCurrency = CreatorCoinCurrency.usd
  @State private var creatorCoinLastCurrency: CreatorCoinCurrency?
  @State private var creatorCoinIsFlipping = false
  @State private var creatorCoinShowsReducedMotionSymbol = false
  @State private var creatorCoinSpinID = 0

  var body: some View {
    List {
      appearanceControls
      metalUnitControl
      languageControl
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
      aboutRates
      if model.allowsReplay {
        Section {
          Button(.Settings.replayOnboarding, systemImage: "sparkles.rectangle.stack") {
            restartOnboarding()
          }
          .accessibilityIdentifier("settings.replayOnboarding")
        } header: {
          Text(.Settings.gettingStarted)
        }
      }
      feedbackControls
      creatorFooter
      Section {
        EmptyView()
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
    .alert(.Settings.feedback, isPresented: $showsFeedbackOptions) {
      Button(.Settings.contactEmail) {
        pendingFeedbackEmail = true
        showsFeedbackOptions = false
      }
      .accessibilityIdentifier("settings.feedback.email")
      Button(.Settings.contactX) {
        if let url = URL(string: "https://x.com/dimasike_") { openURL(url) }
      }
      .accessibilityIdentifier("settings.feedback.x")
      Button(.Settings.close, role: .cancel) {}
    }
    .onChange(of: showsFeedbackOptions) { _, presented in
      if !presented && pendingFeedbackEmail {
        pendingFeedbackEmail = false
        sendFeedbackEmail()
      }
    }
    .sheet(isPresented: $showsFeedbackComposer, onDismiss: feedbackComposerDismissed) {
      FeedbackMailComposer { failed in
        pendingMailFailure = failed
        showsFeedbackComposer = false
      }
    }
    .alert(
      mailSendFailed ? .Settings.mailSendFailed : .Settings.mailUnavailable,
      isPresented: $showsMailUnavailable
    ) {
      Button(.Settings.copyEmail) {
        UIPasteboard.general.string = "dimasike.dev@gmail.com"
      }
      Button(.Settings.close, role: .cancel) {}
    } message: {
      Text(verbatim: "dimasike.dev@gmail.com")
    }
  }

  private var feedbackControls: some View {
    Section {
      Button {
        showsFeedbackOptions = true
      } label: {
        Label {
          Text(.Settings.feedback).foregroundStyle(Color.primary)
        } icon: {
          Image(systemName: "bubble.left").foregroundStyle(.tint)
        }
      }
      .accessibilityIdentifier("settings.feedback")
    } footer: {
      Text(.Settings.feedbackExplanation)
    }
  }

  private func sendFeedbackEmail() {
    mailSendFailed = false
    pendingMailFailure = false
    if MFMailComposeViewController.canSendMail() {
      showsFeedbackComposer = true
    } else if let url = URL(string: "mailto:dimasike.dev@gmail.com") {
      openURL(url) { accepted in
        if !accepted { showsMailUnavailable = true }
      }
    }
  }

  private func feedbackComposerDismissed() {
    if pendingMailFailure {
      pendingMailFailure = false
      mailSendFailed = true
      showsMailUnavailable = true
    }
  }

  private var creatorFooter: some View {
    Section {
      VStack(spacing: AppStyle.Space.medium) {
        creatorCoin
        Text(.Settings.madeByDimasike)
          .font(AppStyle.font(.headline))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        if creatorLinksAreVertical {
          VStack(spacing: AppStyle.Space.small) { creatorLinks }
        } else {
          HStack(spacing: AppStyle.Space.small) { creatorLinks }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, AppStyle.Space.small)
      .listRowInsets(.horizontal, 0)
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("settings.creator")
    }
  }

  private var creatorCoin: some View {
    Button(action: flipCreatorCoin) {
      TimelineView(.animation(paused: !creatorCoinIsFlipping || reduceMotion)) { context in
        let rotation = creatorCoinRotation(at: context.date)
        ZStack {
          Image("CreatorPortrait", bundle: .module)
            .resizable()
            .scaledToFill()
            .frame(width: 88, height: 88)
            .clipShape(Circle())
            .modifier(CreatorCoinFace(rotation: reduceMotion ? 0 : rotation))
            .opacity(reduceMotion && creatorCoinShowsReducedMotionSymbol ? 0 : 1)
          Circle()
            .fill(Color(uiColor: .tertiarySystemFill))
            .overlay {
              Image(systemName: creatorCoinCurrency.symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.tint)
            }
            .frame(width: 88, height: 88)
            .modifier(CreatorCoinFace(rotation: reduceMotion ? 0 : rotation - 180))
            .opacity(reduceMotion && !creatorCoinShowsReducedMotionSymbol ? 0 : 1)
        }
        .frame(width: 88, height: 88)
        .contentShape(Circle())
      }
    }
    .buttonStyle(CreatorCoinButtonStyle())
    .allowsHitTesting(!creatorCoinIsFlipping)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(.Settings.flipCreatorCoin)
    .accessibilityValue(Text(.Settings.creatorCoinPortrait))
    .accessibilityIdentifier("settings.creator.coin")
    .task(id: creatorCoinIsFlipping) {
      guard creatorCoinIsFlipping else { return }
      let spinID = creatorCoinSpinID
      let reduced = reduceMotion
      do {
        try await Task.sleep(for: .milliseconds(reduced ? 600 : 1000))
      } catch {
        if spinID == creatorCoinSpinID { resetCreatorCoin() }
        return
      }
      guard spinID == creatorCoinSpinID else { return }
      guard reduced else {
        resetCreatorCoin()
        return
      }
      withAnimation(.easeInOut(duration: 0.15), completionCriteria: .logicallyComplete) {
        creatorCoinShowsReducedMotionSymbol = false
      } completion: {
        guard spinID == creatorCoinSpinID else { return }
        creatorCoinIsFlipping = false
      }
    }
    .onDisappear(perform: resetCreatorCoin)
  }

  private func flipCreatorCoin() {
    guard !creatorCoinIsFlipping else { return }
    creatorCoinSpinID += 1
    let candidates = CreatorCoinCurrency.allCases.filter { $0 != creatorCoinLastCurrency }
    if let currency = candidates.randomElement() {
      creatorCoinCurrency = currency
      creatorCoinLastCurrency = currency
    }
    creatorCoinSpinStartedAt = Date()
    creatorCoinIsFlipping = true
    if reduceMotion {
      withAnimation(.easeInOut(duration: 0.15)) {
        creatorCoinShowsReducedMotionSymbol = true
      }
    }
  }

  private func creatorCoinRotation(at date: Date) -> Double {
    guard let start = creatorCoinSpinStartedAt else { return 0 }
    let progress = min(1, max(0, date.timeIntervalSince(start)))
    return 180 * (1 - cos(progress * .pi))
  }

  private func resetCreatorCoin() {
    creatorCoinSpinID += 1
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      creatorCoinSpinStartedAt = nil
      creatorCoinShowsReducedMotionSymbol = false
      creatorCoinIsFlipping = false
    }
  }

  private var creatorLinks: some View {
    Group {
      Button(action: sendFeedbackEmail) {
        creatorContactLabel(.Settings.contactEmail, symbol: "envelope")
      }
      .accessibilityIdentifier("settings.contact.email")
      if let url = URL(string: "https://dimasike.com") {
        Link(destination: url) {
          creatorContactLabel(.Settings.contactWebsite, symbol: "globe")
        }
        .accessibilityIdentifier("settings.contact.website")
      }
      if let url = URL(string: "https://x.com/dimasike_") {
        Link(destination: url) {
          creatorContactLabel(.Settings.contactX, asset: "XLogo")
        }
        .accessibilityIdentifier("settings.contact.x")
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(.tint)
  }

  private var creatorLinksAreVertical: Bool { dynamicTypeSize >= .xxLarge }

  private func creatorContactLabel(
    _ title: LocalizedStringResource, symbol: String? = nil, asset: String? = nil
  ) -> some View {
    HStack(spacing: 6) {
      if let symbol {
        Image(systemName: symbol)
          .accessibilityHidden(true)
      }
      if let asset {
        Image(asset, bundle: .module)
          .resizable()
          .scaledToFit()
          .frame(width: 14, height: 14)
          .accessibilityHidden(true)
      }
      Text(title)
        .lineLimit(creatorLinksAreVertical ? nil : 1)
        .minimumScaleFactor(0.8)
    }
    .font(AppStyle.font(.subheadline))
    .multilineTextAlignment(.center)
    .padding(.horizontal, 8)
    .padding(.vertical, creatorLinksAreVertical ? 8 : 0)
    .frame(maxWidth: .infinity, minHeight: 44)
    .frame(height: creatorLinksAreVertical ? nil : 44)
    .glassEffect(.regular.interactive(), in: Capsule())
  }

  private var metalUnitControl: some View {
    Section {
      Picker(
        selection: Binding(
          get: { model.preferences.metalUnit },
          set: { model.setMetalUnit($0) }
        )
      ) {
        ForEach(MetalUnit.allCases, id: \.self) { unit in
          Text(unit.title).tag(unit)
            .accessibilityIdentifier("settings.metalUnit.\(unit.rawValue)")
        }
      } label: {
        Label(.Settings.metalUnit, systemImage: "scalemass")
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("settings.metalUnit")
      if model.issue == .preferenceSaveFailed {
        Text(.Settings.preferenceSaveFailed).foregroundStyle(.secondary)
      }
    } header: {
      Text(.Settings.preciousMetals)
    } footer: {
      Text(.Settings.metalUnitExplanation)
    }
  }

  private var languageControl: some View {
    Section {
      Button {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      } label: {
        Label(.Settings.language, systemImage: "globe")
      }
      .accessibilityIdentifier("settings.language")
    } footer: {
      Text(.Settings.languageSettingsExplanation)
    }
  }

  private var aboutRates: some View {
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
  }

  private var appearanceControls: some View {
    Section(.Settings.appearance) {
      themeControl
      accentControl
    }
  }

  private var themeControl: some View {
    Picker(
      selection: Binding(
        get: { model.preferences.theme },
        set: { value in model.setTheme(value) }
      )
    ) {
      ForEach(SettingsTheme.allCases) { theme in
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
  }

  private var accentControl: some View {
    Menu {
      Picker(
        .Settings.accentColor,
        selection: Binding(
          get: { model.preferences.accent },
          set: { value in model.setAccent(value) }
        )
      ) {
        ForEach(SettingsAccent.allCases) { accent in
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
      settingsValueRow {
        Label {
          Text(.Settings.accentColor).foregroundStyle(Color.primary)
        } icon: {
          Image(systemName: "paintpalette").foregroundStyle(.tint)
        }
      } value: {
        HStack(spacing: AppStyle.Space.small) {
          Circle().fill(model.preferences.accent.color).frame(width: 18, height: 18)
          Text(model.preferences.accent.title)
          Image(systemName: "chevron.up.chevron.down")
            .font(AppStyle.font(.caption, weight: .semibold))
            .accessibilityHidden(true)
        }
        .foregroundStyle(.tint)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(.Settings.accentColor)
    .accessibilityIdentifier("settings.accent")
    .accessibilityValue(Text(model.preferences.accent.title))
    .id(model.preferences.accent)
    .onChange(of: model.preferences.accent) { _, _ in AppHaptics.play(.selection) }
  }

  private func restartOnboarding() {
    if model.replay() {
      AppHaptics.play(.transition)
    } else {
      replayFailed = true
      AppHaptics.play(.error)
    }
  }

  private func settingsValueRow<Title: View, Value: View>(
    @ViewBuilder title: () -> Title,
    @ViewBuilder value: () -> Value
  ) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
          title().fixedSize(horizontal: false, vertical: true)
          value().fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
      } else {
        HStack(spacing: AppStyle.Space.medium) {
          title()
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
          Spacer(minLength: 0)
          value()
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .labelStyle(.titleAndIcon)
  }

  private func timestamp(_ date: Date) -> String {
    date.formatted(.dateTime.day().month().year().hour().minute().locale(locale))
  }

  private func timestampRow(_ title: LocalizedStringResource, date: Date?) -> some View {
    settingsValueRow {
      Text(title)
    } value: {
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
          model.refresh()
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
          quoteRow(code)

        }
      }
    }
    .navigationTitle(.Settings.rates)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func quoteRow(_ code: String) -> some View {
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

  @ViewBuilder private var acknowledgements: some View {
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
    Section(.Settings.testing) {
      sourceCredit(
        "e2e", description: .Settings.testingCredit,
        website: "https://github.com/tester-army/e2e",
        license: "Apache 2.0",
        licenseURL: "https://github.com/tester-army/e2e/blob/main/LICENSE")
    }
  }
}

private extension SettingsTheme {
  var title: LocalizedStringResource {
    switch self {
    case .system: .Settings.appearanceSystem
    case .light: .Settings.appearanceLight
    case .dark: .Settings.appearanceDark
    }
  }
}

private struct CreatorCoinButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
  }
}

private struct CreatorCoinFace: ViewModifier {
  var rotation: Double

  func body(content: Content) -> some View {
    content
      .opacity(cos(rotation * .pi / 180) > 0 ? 1 : 0)
      .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
  }
}

private enum CreatorCoinCurrency: String, CaseIterable {
  case usd = "USD"
  case eur = "EUR"
  case gbp = "GBP"
  case jpy = "JPY"
  case inr = "INR"
  case btc = "BTC"

  var symbol: String {
    switch self {
    case .usd: "dollarsign"
    case .eur: "eurosign"
    case .gbp: "sterlingsign"
    case .jpy: "yensign"
    case .inr: "indianrupeesign"
    case .btc: "bitcoinsign"
    }
  }
}

private extension SettingsAccent {
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

private extension SettingsAccent {
  var color: Color { AppAppearance.Accent(rawValue: rawValue)?.color ?? .primary }
}

private extension MetalUnit {
  var title: LocalizedStringResource {
    switch self {
    case .troyOunce: .Settings.troyOunces
    case .gram: .Settings.grams
    case .kilogram: .Settings.kilograms
    }
  }
}
