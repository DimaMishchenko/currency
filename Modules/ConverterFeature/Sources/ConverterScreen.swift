import CurrencySupport
import ExchangeRates
import SwiftUI
import WidgetKit

struct CurrencyDetailSelection: Identifiable { let id: String }

/// The converter feature, with rate-details navigation supplied by the host app.
public struct ConverterScreen<Details: View>: View {
  @Environment(\.locale) private var locale
  private let details: (String, String, RateSnapshot) -> Details

  /// Creates a converter using the shared store and a destination for currency details.
  /// - Parameters:
  ///   - store: Storage for converter input and rate snapshots; defaults to the App Group.
  ///   - service: Rate providers used by activation, periodic, and manual refreshes.
  ///   - details: Builds details for a currency code, reference code, and current snapshot.
  public init(
    store: CurrencyStore = .shared, service: RateService = RateService(),
    @ViewBuilder details: @escaping (String, String, RateSnapshot) -> Details
  ) {
    self.details = details
    _model = State(initialValue: ConverterModel(store: store, service: service))
  }

  @State private var model: ConverterModel
  @State private var editingAmount = false
  @State private var picker: PickerPurpose?
  @State private var showInfo = false
  @State private var showManage = false
  @State private var showWidgets = false
  @State private var detail: CurrencyDetailSelection?
  @State private var replaceOnNextDigit = true
  @State private var feedback = 0
  @Namespace private var currencyMotion
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
    CurrencyDisplay.inputAmount(model.input.amount, locale: locale)
  }

  /// The converter screen content.
  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 0) {
          header
          source.padding(.top, editingAmount ? AppStyle.Space.medium : AppStyle.Space.large)
            .padding(.bottom, editingAmount ? AppStyle.Space.medium : AppStyle.Space.large)
          adaptiveLayout {
            Text(.Converter.yourCurrenciesHeading)
              .font(AppStyle.font(.caption2, weight: .semibold)).tracking(2)
            Text(
              CurrencyDisplay.inputAmount(
                String(format: "%02d", model.input.destinations.count), locale: locale)
            )
            .font(.system(.caption2, design: .monospaced)).foregroundStyle(accent)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Button {
              showManage = true
            } label: {
              Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(.Converter.reorderAccessibility)
          }
          .foregroundStyle(.secondary)
          Divider()
          LazyVStack(spacing: 0) {
            ForEach(model.input.destinations, id: \.self) { code in
              destinationRow(code)
              Divider().padding(.leading, AppStyle.Space.spacious)
            }
          }
          Button {
            picker = .add
          } label: {
            HStack(spacing: AppStyle.Space.medium) {
              Image(systemName: "plus").font(AppStyle.font(.subheadline, weight: .medium))
                .frame(width: 36)
              Text(.Converter.addCurrency).font(AppStyle.font(.subheadline))
              Spacer()
            }
            .foregroundStyle(.secondary).frame(minHeight: 62).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          Button {
            showInfo = true
          } label: {
            HStack(spacing: AppStyle.Space.small) {
              Circle().fill(model.warning == nil ? accent : .orange).frame(width: 4, height: 4)
              Text(
                model.snapshot.quotes.isEmpty
                  ? .Converter.connectToDownload : .Converter.savedOffline)
              Image(systemName: "arrow.up.right").font(AppStyle.font(.caption2, weight: .medium))
            }
            .font(AppStyle.font(.caption2)).foregroundStyle(.secondary).frame(minHeight: 44)
          }
          .buttonStyle(.plain).padding(.top, AppStyle.Space.medium)
          if let warning = model.warning {
            Text(warning).font(AppStyle.font(.caption)).foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .padding(.bottom, AppStyle.Space.small)
          }
        }
        .padding(.horizontal, AppStyle.Space.large).padding(.top, AppStyle.Space.small)
        .frame(maxWidth: 580).frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      .background(Color(uiColor: .systemBackground).ignoresSafeArea())
      .safeAreaInset(edge: .bottom, spacing: 0) { inputDock }
      .toolbar(.hidden, for: .navigationBar)
      .sheet(item: $picker) { purpose in
        CurrencyChooser(
          purpose: purpose,
          selected: purpose == .source
            ? [model.input.source] : model.input.destinations + [model.input.source],
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
      }
      .sheet(isPresented: $showManage) {
        ManageCurrencies(model: model)
      }
      .sheet(isPresented: $showInfo) { rateInformation }
      .sheet(isPresented: $showWidgets) { WidgetGuide() }
      .sheet(item: $detail) { selection in
        details(selection.id, model.input.source, model.snapshot)
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
          Task { await model.refresh() }
        }
      }
      .onOpenURL { _ in model.reloadInput() }
      .sensoryFeedback(.selection, trigger: feedback)
    }
    .tint(accent)
  }

  private var adaptiveLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppStyle.Space.small))
      : AnyLayout(HStackLayout())
  }

  private var header: some View {
    adaptiveLayout {
      HStack(spacing: AppStyle.Space.small) {
        if !dynamicTypeSize.isAccessibilitySize {
          Image(systemName: "arrow.up.right").font(AppStyle.font(.subheadline, weight: .semibold))
            .foregroundStyle(accent)
        }
        Text(.Converter.appName)
          .font(AppStyle.font(.title3, weight: .semibold))
      }
      if !dynamicTypeSize.isAccessibilitySize { Spacer() }
      HStack {
        Button {
          showWidgets = true
        } label: {
          Image(systemName: "square.grid.2x2").frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain).glassEffect(.regular.interactive())
        .accessibilityLabel(.Converter.widgets)
        Menu {
          Button(.Converter.refreshRates, systemImage: "arrow.clockwise") {
            Task { await model.refresh(force: true) }
          }
          .disabled(model.refreshing)
          Button(.Converter.manageCurrencies, systemImage: "slider.horizontal.3") {
            showManage = true
          }
          Button(.Converter.aboutRates, systemImage: "info.circle") { showInfo = true }
        } label: {
          Image(systemName: "ellipsis").font(AppStyle.font(.headline))
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain).glassEffect(.regular.interactive())
        .accessibilityLabel(.Converter.options)
      }
    }
  }

  private var source: some View {
    VStack(alignment: .leading, spacing: AppStyle.Space.large) {
      adaptiveLayout {
        Button {
          picker = .source
        } label: {
          HStack(spacing: AppStyle.Space.small) {
            CurrencyIcon(model.input.source, size: 23)
              .matchedGeometryEffect(id: "flag-" + model.input.source, in: currencyMotion)
              .accessibilityHidden(true)
            Text(model.input.source).font(AppStyle.font(.subheadline, weight: .semibold))
              .matchedGeometryEffect(id: model.input.source, in: currencyMotion)
            Image(systemName: "chevron.down").font(AppStyle.font(.caption2, weight: .bold))
              .foregroundStyle(.secondary)
          }
          .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          .Converter.sourceAccessibility(CurrencyDisplay.name(model.input.source, locale: locale)))
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        Text(.Converter.baseAmountHeading).font(AppStyle.font(.caption2, weight: .medium))
          .tracking(2)
          .foregroundStyle(.secondary)
      }
      Button {
        replaceOnNextDigit = true
        withAnimation(motion) { editingAmount = true }
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: AppStyle.Space.small) {
          Text(amountLabel)
            .font(
              .system(
                size: editingAmount ? editingAmountSize : amountSize, weight: .light,
                design: .rounded)
            )
            .tracking(-3).lineLimit(1).minimumScaleFactor(0.25).contentTransition(.numericText())
          if editingAmount {
            Capsule().fill(accent).frame(width: 2, height: 48).transition(.opacity)
              .accessibilityHidden(true)
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(.Converter.editAmountAccessibility(model.input.source))
      .accessibilityValue(amountLabel)
      HStack {
        Text(CurrencyDisplay.name(model.input.source, locale: locale))
          .font(AppStyle.font(.subheadline))
          .foregroundStyle(.secondary)
        Spacer()
        if editingAmount {
          Text(.Converter.editing).font(AppStyle.font(.caption2)).foregroundStyle(accent)
            .transition(.opacity)
        }
      }
    }
  }

  private func destinationRow(_ code: String) -> some View {
    let value = model.snapshot.convert(model.input.decimal, from: model.input.source, to: code)
    return HStack(spacing: 0) {
      Button {
        guard value != nil else { return }
        feedback += 1
        withAnimation(motion) { model.updateInput { $0.useAsBase(code, snapshot: model.snapshot) } }
      } label: {
        HStack(spacing: AppStyle.Space.medium) {
          CurrencyIcon(code, size: 28).frame(width: 36)
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
            Text(CurrencyDisplay.format(value, code: code, locale: locale))
              .font(AppStyle.font(.title2, weight: .regular)).monospacedDigit()
              .lineLimit(1).minimumScaleFactor(0.45).contentTransition(.numericText())
              .layoutPriority(1)
          }
        }
        .frame(minHeight: 70).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(

        .Converter.conversionAccessibility(
          CurrencyDisplay.name(code, locale: locale),
          CurrencyDisplay.format(value, code: code, locale: locale))
      )
      .accessibilityHint(.Converter.makeBaseHint)
      .contextMenu {
        Button(.Converter.detailsAndHistory, systemImage: "chart.xyaxis.line") {
          detail = CurrencyDetailSelection(id: code)
        }
        Button(.Converter.useAsBase, systemImage: "arrow.up") {
          withAnimation(motion) {
            model.updateInput { $0.useAsBase(code, snapshot: model.snapshot) }
          }
        }
        .disabled(value == nil)
        Button(.Converter.copyAmount, systemImage: "doc.on.doc") {
          UIPasteboard.general.string = CurrencyDisplay.format(value, code: code, locale: locale)
        }
        .disabled(value == nil)
        Text(
          CurrencyDisplay.details(
            model.snapshot, from: model.input.source, to: code, locale: locale))
        Button(.Converter.remove, systemImage: "minus.circle", role: .destructive) {
          withAnimation(motion) {
            model.updateInput { $0.setDestinations($0.destinations.filter { $0 != code }) }
          }
        }
      }
      Button {
        detail = CurrencyDetailSelection(id: code)
      } label: {
        Image(systemName: "chart.xyaxis.line").font(AppStyle.font(.caption))
          .foregroundStyle(.secondary)
          .frame(width: 44, height: 60)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        .Converter.detailsAccessibility(CurrencyDisplay.name(code, locale: locale)))
    }
  }

  private var inputDock: some View {
    GlassEffectContainer(spacing: AppStyle.Space.section) {
      if editingAmount {
        VStack(spacing: AppStyle.Space.xs) {
          HStack {
            HStack(spacing: AppStyle.Space.small) {
              CurrencyIcon(model.input.source, size: 14)
              Text(verbatim: model.input.source)
            }
            .font(AppStyle.font(.caption).weight(.semibold))
            Spacer()
            Button(.Converter.clear) { key("AC") }.font(AppStyle.font(.caption))
              .frame(minWidth: 44, minHeight: 44)
            Button {
              withAnimation(motion) { editingAmount = false }
            } label: {
              Image(systemName: "checkmark").font(AppStyle.font(.headline))
                .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(.Converter.doneEntering)
          }
          .padding(.horizontal, AppStyle.Space.section)
          Grid(horizontalSpacing: AppStyle.Space.xs, verticalSpacing: AppStyle.Space.xxs) {
            ForEach(
              [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]], id: \.self
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
                        Text(CurrencyDisplay.inputAmount(item, locale: locale))
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
        }
        .glassEffect(
          .regular, in: .rect(corners: .concentric(minimum: .fixed(32)), isUniform: true)
        )
        .glassEffectID("amount-dock", in: keypadMotion)
        .glassEffectTransition(.matchedGeometry)
      } else {
        HStack(spacing: 0) {
          Button {
            replaceOnNextDigit = true
            withAnimation(motion) { editingAmount = true }
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
          }
          .buttonStyle(.plain)
          .accessibilityLabel(.Converter.enterAmount)
          Rectangle().fill(.primary.opacity(0.1)).frame(width: 1, height: 20)
          Button {
            picker = .add
          } label: {
            Image(systemName: "plus").font(AppStyle.font(.body, weight: .medium))
              .frame(minWidth: 48, minHeight: 48)
              .padding(.horizontal, AppStyle.Space.small)
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
    .padding(.bottom, editingAmount ? -AppStyle.Space.large : 0)
  }

  private func key(_ key: String) {
    feedback += 1
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
      model.updateInput {
        if replaceOnNextDigit && key != "⌫" { $0.press("AC") }
        $0.press(key)
      }
      replaceOnNextDigit = false
    }
  }

  private var rateInformation: some View {
    NavigationStack {
      List {
        Section {
          Text(
            .Converter.dailyRateExplanation
          )
          if model.snapshot.fetchedAt != .distantPast {
            LabeledContent(
              .Converter.lastChecked,
              value: model.snapshot.fetchedAt.formatted(
                .dateTime.day().month().year().hour().minute().locale(locale)))
          }
          Button(.Converter.refreshNow, systemImage: "arrow.clockwise") {
            Task { await model.refresh(force: true) }
          }
          .disabled(model.refreshing)
        }
        Section(.Converter.publicationDates) {
          ForEach([model.input.source] + model.input.destinations, id: \.self) { code in
            LabeledContent {
              VStack(alignment: .trailing, spacing: AppStyle.Space.xs) {
                Text(
                  model.snapshot.quotes[code]
                    .map { CurrencyDisplay.publicationDate($0.published, locale: locale) }
                    ?? String(localized: .Converter.notDownloaded))
                Text(
                  model.snapshot.quotes[code]
                    .map { RateMessages.providerDescription($0.source, locale: locale) }
                    ?? String(localized: .Converter.unavailable)
                )
                .font(AppStyle.font(.caption))
                .foregroundStyle(.secondary)
              }
            } label: {
              HStack(spacing: AppStyle.Space.small) {
                CurrencyIcon(code, size: 20)
                Text(verbatim: code)
              }
            }
          }
        }
        Section(.Converter.homeScreen) {
          Text(
            .Converter.widgetSharingExplanation
          )
        }
        Section(.Converter.sources) {
          Text(
            .Converter.providerExplanation
          )
          Link(destination: URL(string: "https://github.com/0xa3k5/web3icons")!) {
            Text(.Converter.cryptoIconAttribution)
          }
          Link(destination: URL(string: "https://github.com/spothq/cryptocurrency-icons")!) {
            Text(.Converter.dogecoinIconAttribution)
          }
        }
      }
      .navigationTitle(.Converter.aboutRates).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(.Converter.done) { showInfo = false }
        }
      }
    }
  }
}
