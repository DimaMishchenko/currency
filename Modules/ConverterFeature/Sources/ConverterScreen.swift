import CurrencySelectionUI
import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

struct CurrencyDetailSelection: Identifiable { let id: String }

/// The converter feature, with details and onboarding destinations supplied by the host app.
public struct ConverterScreen<Details: View, Widgets: View>: View {
  private static var destinationIconColumnWidth: CGFloat { 44 }
  private static var destinationTextInset: CGFloat {
    destinationIconColumnWidth + AppStyle.Space.medium
  }

  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.locale) private var locale
  private let details: (String, String, RateSnapshot) -> Details
  private let widgets: () -> Widgets
  private let reconcileLocalCurrency: () -> Void
  private let replayOnboarding: (() throws -> Void)?
  private let inputRevision: Int

  /// Creates a converter using the shared store and a destination for currency details.
  /// - Parameters:
  ///   - store: Storage for converter input and rate snapshots; defaults to the App Group.
  ///   - service: Rate providers used by activation, periodic, and manual refreshes.
  ///   - inputRevision: Change after a host-owned destination edits saved converter input.
  ///   - details: Builds details for a currency code, reference code, and current snapshot.
  ///   - widgets: Builds widget discovery and installation guidance.
  ///   - reconcileLocalCurrency: Reconciles saved permission when the app becomes active.
  ///   - replayOnboarding: Restarts app setup after its progress record has been saved.
  public init(
    store: CurrencyStore = .shared, service: RateService = RateService(), inputRevision: Int = 0,
    @ViewBuilder details: @escaping (String, String, RateSnapshot) -> Details,
    @ViewBuilder widgets: @escaping () -> Widgets,
    reconcileLocalCurrency: @escaping () -> Void,
    replayOnboarding: (() throws -> Void)? = nil
  ) {
    self.details = details
    self.widgets = widgets
    self.reconcileLocalCurrency = reconcileLocalCurrency
    self.replayOnboarding = replayOnboarding
    self.inputRevision = inputRevision
    _model = State(initialValue: ConverterModel(store: store, service: service))
  }

  @State private var model: ConverterModel
  @State private var editingAmount = false
  @State private var listPosition = ScrollPosition(idType: String.self)
  @State private var picker: PickerPurpose?
  @State private var showInfo = false
  @State private var replayFailed = false
  @State private var showManage = false
  @State private var showsWidgets = false
  @State private var detail: CurrencyDetailSelection?
  @Namespace private var currencyMotion
  @Namespace private var detailsMotion
  @Namespace private var pickerMotion
  @Namespace private var keypadMotion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(AppAppearance.self) private var appearance
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 68
  @ScaledMetric(relativeTo: .largeTitle) private var editingAmountSize = 48
  private var accent: Color { appearance.accent }
  private var motion: Animation? {
    reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
  }

  private var amountLabel: String {
    if editingAmount && model.editingCode == model.input.source {
      CurrencyDisplay.inputAmount(model.editingText, locale: locale)
    } else {
      CurrencyDisplay.format(model.input.decimal, code: model.input.source, locale: locale)
    }
  }

  /// The converter screen content.
  public var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        if verticalSizeClass == .compact {
          HStack(spacing: AppStyle.Space.large) {
            VStack(spacing: AppStyle.Space.small) {
              source.padding(.horizontal, AppStyle.Space.large)

              Spacer(minLength: 0)
              inputDock
            }
            .frame(width: geometry.size.width * 0.48)
            currencyList
          }
          .padding(.top, AppStyle.Space.small)
        } else {
          VStack(spacing: 0) {
            source
              .padding(.horizontal, AppStyle.Space.large)
              .padding(.vertical, AppStyle.Space.large)
              .frame(maxWidth: 580)
            currencyList
            inputDock
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
      }
      .background { outsideDismissal.accessibilityHidden(true) }
      .background(Color(uiColor: .systemBackground).ignoresSafeArea())
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { sourcePicker }
        headerActions
      }
      .sheet(item: $picker) { purpose in
        let chooser = CurrencyChooser(
          purpose: purpose,
          selected: purpose == .source
            ? [model.input.source] : model.input.destinations + [model.input.source],
          homeCurrencies: [model.input.source] + model.input.destinations,
          available: Set(model.snapshot.quotes.keys)
        ) { code in
          withAnimation(motion) {
            if purpose == .source {
              model.updateInput { $0.changeSource(code) }
            } else {
              model.updateInput { $0.setDestinations($0.destinations + [code]) }
            }
          }
        }
        chooser.navigationTransition(.zoom(sourceID: purpose.id, in: pickerMotion))
      }
      .sheet(isPresented: $showManage) {
        ManageCurrencies(model: model)
      }
      .sheet(isPresented: $showInfo) { rateInformation }
      .alert(.Converter.replayFailed, isPresented: $replayFailed) {
        Button(.Converter.retryReplay) { restartOnboarding() }
        Button(.Converter.close, role: .cancel) {}
      }
      .sheet(isPresented: $showsWidgets, onDismiss: { model.reloadInput() }) { widgets() }
      .sheet(item: $detail) { selection in
        if reduceMotion {
          details(selection.id, model.input.source, model.snapshot)
        } else {
          details(selection.id, model.input.source, model.snapshot)
            .navigationTransition(.zoom(sourceID: selection.id, in: detailsMotion))
        }
      }
      .task {
        while !Task.isCancelled {
          if scenePhase == .active { await model.refresh() }
          do { try await Task.sleep(for: .seconds(60)) } catch { break }
        }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active {
          model.reloadInput()
          reconcileLocalCurrency()
          Task { await model.refresh() }
        }
      }
      .onChange(of: model.editor == nil) { _, empty in
        if empty { editingAmount = false }
      }
      .onOpenURL { _ in model.reloadInput() }
      .onChange(of: inputRevision) { _, _ in model.reloadInput() }
    }
    .accessibilityAction(.escape) { dismissAmount() }
    .tint(accent)
  }

  @ViewBuilder
  private var outsideDismissal: some View {
    if editingAmount {
      Color.clear.contentShape(Rectangle())
        .onTapGesture { dismissAmount() }
        .accessibilityElement()
        .accessibilityLabel(.Converter.doneEntering)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { dismissAmount() }
    }
  }

  private var currencyList: some View {
    VStack(spacing: 0) {
      GeometryReader { viewport in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.input.destinations, id: \.self) { code in
              VStack(spacing: 0) {
                destinationRow(code)
                Divider().padding(.leading, Self.destinationTextInset)
              }
              .id(code)
            }
          }
          .scrollTargetLayout()
          .frame(maxWidth: 580).frame(maxWidth: .infinity)
          .background {
            if !editingAmount {
              CurrencyRefreshAttachment(refreshing: model.manuallyRefreshing, enabled: true) {
                await model.refresh(force: true)
              }
            }
          }
        }
        .accessibilityAction(named: Text(.Converter.refreshRates)) {
          Task { await model.refresh(force: true) }
        }
        .scrollBounceBehavior(.always)
        .scrollPosition($listPosition)
        .padding(.horizontal, AppStyle.Space.large)
        .task(id: "\(editingAmount)-\(model.editingCode)-\(viewport.size)") {
          // Wait for the keypad's layout transaction before resolving the row's scroll position.
          do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
          guard editingAmount, model.editingCode != model.input.source else { return }
          if model.editingCode == model.input.destinations.last {
            listPosition.scrollTo(edge: .bottom)
          } else {
            listPosition.scrollTo(id: model.editingCode, anchor: .center)
          }
        }
      }
      if let warning = model.warning {
        Text(warning).font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          .multilineTextAlignment(.center).padding(.horizontal, AppStyle.Space.large)
      }
    }
  }

  private var adaptiveLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppStyle.Space.small))
      : AnyLayout(HStackLayout())
  }

  @ToolbarContentBuilder
  private var headerActions: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      widgetsButton
    }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
      optionsMenu
    }
  }

  private var widgetsButton: some View {
    Button {
      dismissAmount(feedback: false)
      AppHaptics.play(.action)
      showsWidgets = true
    } label: {
      Image(systemName: "square.grid.2x2")
    }
    .accessibilityLabel(.Converter.widgets)
    .accessibilityIdentifier("converter.widgets")
  }

  private var optionsMenu: some View {
    Menu {
      Button(.Converter.refreshRates, systemImage: "arrow.clockwise") {
        Task { await model.refresh(force: true) }
      }
      .disabled(model.refreshing)
      Button(.Converter.manageCurrencies, systemImage: "slider.horizontal.3") {
        dismissAmount(feedback: false)
        AppHaptics.play(.action)
        showManage = true
      }
      Button(.Converter.aboutRates, systemImage: "info.circle") {
        dismissAmount(feedback: false)
        AppHaptics.play(.action)
        showInfo = true
      }
      if replayOnboarding != nil {
        Button(.Converter.replayOnboarding, systemImage: "arrow.counterclockwise") {
          restartOnboarding()
        }
        .accessibilityIdentifier("converter.replayOnboarding")
      }
    } label: {
      Image(systemName: "ellipsis")
    }
    .accessibilityLabel(.Converter.options)
  }

  private func restartOnboarding() {
    do { try replayOnboarding?(); AppHaptics.play(.transition) } catch {
      replayFailed = true
      AppHaptics.play(.error)
    }
  }

  @ViewBuilder
  private var source: some View {
    if verticalSizeClass == .compact {
      amountEntry
    } else {
      VStack(alignment: .leading, spacing: AppStyle.Space.large) {
        amountEntry
        HStack {
          Text(CurrencyDisplay.name(model.input.source, locale: locale))
            .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
          Spacer()
        }
      }
    }
  }

  private var sourcePicker: some View {
    Button {
      AppHaptics.play(.action)
      dismissAmount(feedback: false)
      picker = .source
    } label: {
      HStack(spacing: AppStyle.Space.small) {
        CurrencyIcon(model.input.source, size: 23)
          .accessibilityHidden(true)
        Text(model.input.source).font(AppStyle.font(.subheadline, weight: .semibold))
          .lineLimit(1)
        Image(systemName: "chevron.down").font(AppStyle.font(.caption2, weight: .bold))
          .foregroundStyle(.secondary)
      }
      .frame(minWidth: 100, minHeight: 44).contentShape(Rectangle())
      .fixedSize(horizontal: true, vertical: false)
    }
    .buttonStyle(.plain)
    .matchedTransitionSource(id: PickerPurpose.source.id, in: pickerMotion)
    .accessibilityLabel(
      .Converter.sourceAccessibility(CurrencyDisplay.name(model.input.source, locale: locale)))
  }

  private var amountEntry: some View {
    Button {
      beginEditing(model.input.source)
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: AppStyle.Space.small) {
        Text(amountLabel)
          .font(
            verticalSizeClass == .compact
              ? AppStyle.font(
                .title2,
                weight: editingAmount && model.editingCode == model.input.source
                  ? .semibold : .regular)
              : .system(
                size: editingAmount ? editingAmountSize : amountSize,
                weight: editingAmount && model.editingCode == model.input.source
                  ? .semibold : .regular, design: .rounded)
          )
          .tracking(-3).lineLimit(1).minimumScaleFactor(0.25).contentTransition(.numericText())
        Text(verbatim: model.input.source)
          .font(
            AppStyle.font(
              verticalSizeClass == .compact ? .caption : .title3, weight: .medium)
          )
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
          .fixedSize()
          .accessibilityHidden(true)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(.Converter.editAmountAccessibility(model.input.source))
    .accessibilityValue(amountLabel)
  }

  private func destinationRow(_ code: String) -> some View {
    let value = model.snapshot.convert(model.input.decimal, from: model.input.source, to: code)
    return HStack(spacing: 0) {
      Button {
        guard value != nil else { return }
        beginEditing(code)
      } label: {
        HStack(spacing: AppStyle.Space.medium) {
          CurrencyIcon(code, size: 28)
            .frame(width: Self.destinationIconColumnWidth, alignment: .leading)
            .matchedGeometryEffect(id: "flag-" + code, in: currencyMotion).accessibilityHidden(true)
          let rowLayout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppStyle.Space.small))
            : AnyLayout(HStackLayout(spacing: AppStyle.Space.medium))
          rowLayout {
            VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
              Text(code).font(AppStyle.font(.body, weight: .medium))
                .matchedGeometryEffect(id: code, in: currencyMotion)
              Text(CurrencyDisplay.name(code, locale: locale)).font(AppStyle.font(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: AppStyle.Space.medium) }
            Text(
              editingAmount && model.editingCode == code
                ? CurrencyDisplay.inputAmount(model.editingText, locale: locale)
                : CurrencyDisplay.format(value, code: code, locale: locale)
            )
            .font(
              AppStyle.font(
                .title2, weight: editingAmount && model.editingCode == code ? .semibold : .regular)
            )
            .monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.45).contentTransition(.numericText())
            .layoutPriority(1)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).contentShape(Rectangle())
        .matchedTransitionSource(id: code, in: detailsMotion)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(

        .Converter.conversionAccessibility(
          CurrencyDisplay.name(code, locale: locale),
          CurrencyDisplay.format(value, code: code, locale: locale))
      )
      .accessibilityHint(.Converter.editAmountHint)
      .accessibilityAddTraits(editingAmount && model.editingCode == code ? .isSelected : [])
      .contextMenu {
        Button(.Converter.detailsAndHistory, systemImage: "chart.xyaxis.line") {
          AppHaptics.play(.action)
          detail = CurrencyDetailSelection(id: code)
        }
        Button(.Converter.copyAmount, systemImage: "doc.on.doc") {
          UIPasteboard.general.string = CurrencyDisplay.format(value, code: code, locale: locale)
          AppHaptics.play(.success)
        }
        .disabled(value == nil)
        Text(
          CurrencyDisplay.details(
            model.snapshot, from: model.input.source, to: code, locale: locale))
        Button(.Converter.remove, systemImage: "minus.circle", role: .destructive) {
          withAnimation(motion) {
            if model.updateInput({ $0.setDestinations($0.destinations.filter { $0 != code }) }) {
              AppHaptics.play(.delete)
            }
          }
        }
      }
      Button {
        AppHaptics.play(.action)
        detail = CurrencyDetailSelection(id: code)
      } label: {
        Image(systemName: "chart.xyaxis.line").font(AppStyle.font(.callout))
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
          .foregroundStyle(.secondary)
          .frame(width: Self.destinationIconColumnWidth, height: 60, alignment: .trailing)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        .Converter.detailsAccessibility(CurrencyDisplay.name(code, locale: locale)))
    }
  }

  private var keyRows: [[String]] {
    verticalSizeClass == .compact
      ? [["1", "2", "3", "⌫"], ["4", "5", "6", "."], ["7", "8", "9", "0"]]
      : [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]
  }

  private var inputDock: some View {
    GlassEffectContainer(spacing: AppStyle.Space.section) {
      if editingAmount {
        VStack(spacing: AppStyle.Space.xs) {
          Group {
            HStack(spacing: AppStyle.Space.small) {
              CurrencyIcon(model.editingCode, size: 14).accessibilityHidden(true)
              Text(verbatim: model.editingCode)
              Spacer()
              Button {
                dismissAmount()
              } label: {
                Image(systemName: "checkmark").frame(width: 44, height: 44)
              }
              .accessibilityLabel(.Converter.doneEntering)
            }
            .padding(.horizontal, AppStyle.Space.large)
            .font(AppStyle.font(.caption, weight: .semibold))
            .accessibilityElement(children: .contain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppStyle.Space.small)
          }
          Grid(horizontalSpacing: AppStyle.Space.xs, verticalSpacing: AppStyle.Space.xxs) {
            ForEach(
              keyRows, id: \.self
            ) { row in
              GridRow {
                ForEach(row, id: \.self) { item in
                  Button {
                    key(item)
                  } label: {
                    Group {
                      if item == "⌫" {
                        Image(systemName: "delete.left")
                          .font(AppStyle.font(.title2, weight: .light))
                      } else {
                        Text(CurrencyDisplay.keypadLabel(item, locale: locale))
                          .font(AppStyle.font(.title2))
                      }
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 48).contentShape(Rectangle())
                  }
                  .buttonStyle(KeyPressStyle())
                  .accessibilityLabel(
                    item == "⌫"
                      ? Text(.Converter.deleteDigit)
                      : item == "."
                        ? Text(.Converter.decimalSeparator) : Text(verbatim: item))
                }
              }
            }
          }
          .padding(.horizontal, AppStyle.Space.large).padding(.bottom, AppStyle.Space.large)
          .padding(.top, verticalSizeClass == .compact ? AppStyle.Space.small : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { /* Keep taps in the keypad's header and gaps inside the pad. */  }
        .glassEffect(
          .regular, in: .rect(corners: .concentric(minimum: .fixed(32)), isUniform: true)
        )
        .glassEffectID("amount-dock", in: keypadMotion)
        .glassEffectTransition(.matchedGeometry)

      } else {
        HStack(spacing: 0) {
          Button {
            beginEditing(model.input.source)
          } label: {
            Group {
              if dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "keyboard")
              } else {
                Label(.Converter.enterAmount, systemImage: "keyboard")
              }
            }
            .font(AppStyle.font(.subheadline).weight(.medium))
            .frame(maxWidth: .infinity).frame(minHeight: 48)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(.Converter.enterAmount)
          Rectangle().fill(.primary.opacity(0.1)).frame(width: 1, height: 20)
          Button {
            AppHaptics.play(.action)
            picker = .add
          } label: {
            Image(systemName: "plus").font(AppStyle.font(.body, weight: .medium))
              .frame(minWidth: 48, minHeight: 48)
              .padding(.horizontal, AppStyle.Space.small)
              .contentShape(Rectangle())
              .matchedTransitionSource(id: PickerPurpose.add.id, in: pickerMotion)
          }
          .buttonStyle(.plain).accessibilityLabel(.Converter.addCurrency)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 260)
        .glassEffect(.regular.interactive())
        .glassEffectID("amount-dock", in: keypadMotion)
        .glassEffectTransition(.matchedGeometry)
      }
    }
    .padding(.horizontal, AppStyle.Space.small).padding(.top, AppStyle.Space.small)
    .padding(.bottom, editingAmount ? 0 : AppStyle.Space.small)
    .frame(maxWidth: 540).frame(maxWidth: .infinity)
    .background {
      if editingAmount {
        Color.clear.contentShape(Rectangle()).onTapGesture { dismissAmount() }
      }
    }

  }

  private func dismissAmount(feedback: Bool = true) {
    guard editingAmount else { return }
    if feedback { AppHaptics.play(.action) }
    withAnimation(motion) {
      editingAmount = false; model.endEditing()
    }
  }

  private func beginEditing(_ code: String) {
    model.beginEditing(code)
    guard model.editor != nil else { return }
    AppHaptics.play(.action)
    withAnimation(motion) { editingAmount = true }
  }

  private func key(_ key: String) {
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
      if model.press(key) {
        AppHaptics.play(key == "⌫" ? .delete : .selection)
      }
    }
  }

  private func timestamp(_ date: Date) -> String {
    date.formatted(.dateTime.day().month().year().hour().minute().locale(locale))
  }

  private func timestampRow(_ title: LocalizedStringResource, date: Date?) -> some View {
    adaptiveLayout {
      Text(title)
      if !dynamicTypeSize.isAccessibilitySize { Spacer() }
      Text(date.map(timestamp) ?? String(localized: .Converter.unavailable))
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
            Text(verbatim: name).font(AppStyle.font(.headline))
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
    NavigationStack {
      List {
        Section {
          timestampRow(
            .Converter.ratesRetrieved,
            date: model.snapshot.fetchedAt == .distantPast ? nil : model.snapshot.fetchedAt)
          timestampRow(.Converter.lastChecked, date: model.snapshot.checkedAt)
          Button(.Converter.refreshNow, systemImage: "arrow.clockwise") {
            Task { await model.refresh(force: true) }
          }
          .disabled(model.refreshing)
          if let warning = model.warning {
            Text(warning).font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          }
        } header: {
          Text(.Converter.rates)
        } footer: {
          Text(.Converter.dailyRateExplanation)
        }
        Section(.Converter.quoteInformation) {
          ForEach([model.input.source] + model.input.destinations, id: \.self) { code in
            adaptiveLayout {
              HStack(spacing: AppStyle.Space.small) {
                CurrencyIcon(code, size: 20).accessibilityHidden(true)
                Text(verbatim: code)
              }
              if !dynamicTypeSize.isAccessibilitySize { Spacer() }
              VStack(
                alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing,
                spacing: AppStyle.Space.xs
              ) {
                if let rate = model.snapshot.quotes[code] {
                  if let observed = rate.observedAt {
                    Text(.Converter.observedAt(timestamp(observed)))
                  } else if let retrieved = rate.retrievedAt {
                    Text(.Converter.quoteRetrieved(timestamp(retrieved)))
                  } else {
                    Text(
                      .Converter.publishedAt(
                        CurrencyDisplay.publicationDate(rate.published, locale: locale)))
                  }
                  Text(RateMessages.providerDescription(rate.source, locale: locale))
                    .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
                } else {
                  Text(.Converter.notDownloaded)
                  Text(.Converter.unavailable)
                    .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
                }
              }
            }

          }
        }
        Section(.Converter.sources) {
          sourceCredit(
            "Frankfurter", description: .Converter.frankfurterCredit,
            website: "https://frankfurter.dev/")
          sourceCredit(
            "European Central Bank", description: .Converter.ecbCredit,
            website:
              "https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html"
          )
          sourceCredit(
            "Fawaz Exchange API", description: .Converter.fawazCredit,
            website: "https://github.com/fawazahmed0/exchange-api")
          sourceCredit(
            "Coinbase", description: .Converter.coinbaseCredit,
            website: "https://docs.cdp.coinbase.com/coinbase-app/track-apis/exchange-rates")
        }
        Section(.Converter.artwork) {
          sourceCredit(
            "Web3 Icons", description: .Converter.web3Credit,
            website: "https://github.com/0xa3k5/web3icons",
            license: "MIT",
            licenseURL:
              "https://github.com/0xa3k5/web3icons/blob/64e21e68cc6eaa36ff9d0a135ca2c809a759ccd6/LICENCE"
          )
          sourceCredit(
            "Cryptocurrency Icons", description: .Converter.dogeCredit,
            website: "https://github.com/spothq/cryptocurrency-icons",
            license: "CC0 1.0",
            licenseURL:
              "https://github.com/spothq/cryptocurrency-icons/blob/1a63530be6e374711a8554f31b17e4cb92c25fa5/LICENSE.md"
          )
        }
      }
      .navigationTitle(.Converter.aboutRates).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.Converter.close, systemImage: "xmark") { showInfo = false }
            .labelStyle(.iconOnly)
        }
      }
    }
  }
}
