import CurrencySelectionUI
import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

struct CurrencyDetailSelection: Identifiable { let id: String }

/// The converter feature, with details, widgets, and settings supplied by the host app.
public struct ConverterScreen<Details: View, Widgets: View, Settings: View>: View {
  private static var destinationIconColumnWidth: CGFloat { 44 }
  private static var destinationTextInset: CGFloat {
    destinationIconColumnWidth + AppStyle.Space.medium
  }

  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.locale) private var locale
  @Environment(AppAppearance.self) private var appearance
  private let details: (String, String, RateSnapshot) -> Details
  private let widgets: () -> Widgets
  private let reconcileLocalCurrency: () -> Void
  private let configureLocalCurrency: () -> Void
  private let settings:
    (RateSnapshot, [String], Bool, LocalizedStringResource?, @escaping @MainActor () async -> Void)
      -> Settings
  private let inputRevision: Int

  /// Creates a converter using the shared store and a destination for currency details.
  /// - Parameters:
  ///   - store: Storage for converter input and rate snapshots; defaults to the App Group.
  ///   - service: Rate providers used by activation, periodic, and manual refreshes.
  ///   - inputRevision: Change after a host-owned destination edits saved converter input.
  ///   - details: Builds details for a currency code, reference code, and current snapshot.
  ///   - widgets: Builds widget discovery and installation guidance.
  ///   - reconcileLocalCurrency: Reconciles saved permission when the app becomes active.
  ///   - configureLocalCurrency: Presents the permission-based local-currency setup flow.
  ///   - settings: Builds settings from current rates, currency codes, refresh state, warning, and refresh action.
  public init(
    store: CurrencyStore = .shared, service: RateService = RateService(), inputRevision: Int = 0,
    @ViewBuilder details: @escaping (String, String, RateSnapshot) -> Details,
    @ViewBuilder widgets: @escaping () -> Widgets,
    reconcileLocalCurrency: @escaping () -> Void,
    configureLocalCurrency: @escaping () -> Void,
    @ViewBuilder settings:
      @escaping (
        RateSnapshot, [String], Bool, LocalizedStringResource?,
        @escaping @MainActor () async -> Void
      ) -> Settings
  ) {
    self.details = details
    self.widgets = widgets
    self.reconcileLocalCurrency = reconcileLocalCurrency
    self.configureLocalCurrency = configureLocalCurrency
    self.settings = settings
    self.inputRevision = inputRevision
    _model = State(initialValue: ConverterModel(store: store, service: service))
  }

  @State private var model: ConverterModel
  @State private var editingAmount = false
  @State private var listPosition = ScrollPosition(idType: String.self)
  @State private var picker: PickerPurpose?
  @State private var showsSettings = false
  @State private var showManage = false
  @State private var showsWidgets = false
  @State private var opensLocalCurrencyAfterPicker = false
  @State private var detail: CurrencyDetailSelection?
  @Namespace private var currencyMotion
  @Namespace private var detailsMotion
  @Namespace private var pickerMotion
  @Namespace private var keypadMotion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 68
  @ScaledMetric(relativeTo: .largeTitle) private var editingAmountSize = 48
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
        ToolbarItem(placement: .topBarLeading) { sourcePicker.tint(nil) }
        headerActions
      }
      .sheet(item: $picker, onDismiss: openRequestedLocalCurrency) { purpose in
        let locationStatus = model.store.widgetLocationStatus()
        let localCurrencyCode =
          locationStatus == .available && model.store.widgetLocation()?.isFresh() == true
          ? model.store.widgetLocation()?.currency : nil
        let chooser = CurrencyChooser(
          purpose: purpose,
          selected: purpose == .source
            ? [model.input.source] : model.input.destinations + [model.input.source],
          homeCurrencies: [model.input.source] + model.input.destinations,
          available: Set(model.snapshot.quotes.keys),
          showsLocalCurrency: purpose == .add,
          localCurrencyCode: localCurrencyCode,
          localCurrencySelected: model.input.usesLocalCurrency,
          setUpLocalCurrency: {
            opensLocalCurrencyAfterPicker = true
          }
        ) { code in
          withAnimation(motion) {
            if purpose == .source {
              model.updateInput { $0.changeSource(code) }
            } else {
              model.updateInput {
                if code == WidgetSelection.localID {
                  $0.setUsesLocalCurrency(true)
                } else {
                  $0.setDestinations($0.manualDestinations + [code])
                }
              }
            }
          }
        }
        chooser.navigationTransition(.zoom(sourceID: purpose.id, in: pickerMotion))
      }
      .sheet(isPresented: $showManage) {
        ManageCurrencies(model: model)
      }
      .navigationDestination(isPresented: $showsSettings) {
        settings(
          model.snapshot, [model.input.source] + model.input.destinations,
          model.refreshing, model.warning
        ) {
          await model.refresh(force: true)
        }
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
      .onChange(of: inputRevision) { _, _ in model.reloadInput(preservingEditor: true) }
    }
    .accessibilityAction(.escape) { dismissAmount() }
  }

  private func openRequestedLocalCurrency() {
    guard opensLocalCurrencyAfterPicker else { return }
    opensLocalCurrencyAfterPicker = false
    configureLocalCurrency()
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
            if model.input.usesLocalCurrency
              && (model.input.localCurrencyCode == nil || model.input.localCurrencyIsStale)
            {
              Button(action: configureLocalCurrency) {
                Label {
                  Text(
                    model.input.localCurrencyCode == nil
                      ? .Converter.localUnavailable
                      : .Converter.localLastKnown)
                } icon: {
                  Image(systemName: "location")
                }
                .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
              }
              .buttonStyle(.plain)
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

  @ToolbarContentBuilder
  private var headerActions: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      widgetsButton.tint(nil)
    }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
      optionsMenu.tint(nil)
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
      Group {
        Button(.Converter.manageCurrencies, systemImage: "slider.horizontal.3") {
          dismissAmount(feedback: false)
          AppHaptics.play(.action)
          showManage = true
        }
        Button(.Converter.settings, systemImage: "gearshape") {
          dismissAmount(feedback: false)
          AppHaptics.play(.action)
          showsSettings = true
        }
        .accessibilityIdentifier("converter.settings")
      }
      .tint(appearance.accent)
    } label: {
      Image(systemName: "ellipsis")
    }
    .accessibilityLabel(.Converter.options)
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
          .foregroundStyle(Color.primary)
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
              HStack(spacing: AppStyle.Space.xs) {
                Text(code).font(AppStyle.font(.body, weight: .medium))
                  .matchedGeometryEffect(id: code, in: currencyMotion)
                if model.input.usesLocalCurrency && model.input.localCurrencyCode == code {
                  Image(systemName: "location.fill")
                    .font(AppStyle.font(.caption2))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }
              }
              Text(
                model.input.usesLocalCurrency && model.input.localCurrencyCode == code
                  ? String(
                    localized: .Converter.localCurrencyName(
                      CurrencyDisplay.name(code, locale: locale)))
                  : CurrencyDisplay.name(code, locale: locale)
              )
              .font(AppStyle.font(.caption))
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
            if model.updateInput({ $0.removeDestination(code) }) {
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
          .frame(width: Self.destinationIconColumnWidth, height: 70, alignment: .trailing)
          // Plain buttons otherwise hit-test only the small symbol, not its padded frame.
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        .Converter.detailsAccessibility(CurrencyDisplay.name(code, locale: locale))
      )
      .accessibilityIdentifier("converter.chart.\(code)")
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
          Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 20)
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

}
