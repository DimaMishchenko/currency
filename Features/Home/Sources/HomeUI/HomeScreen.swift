import Conversion
import CurrencySelectionUI
import DesignSystem
import ExchangeRates
import ExchangeRatesUI
import Home
import SwiftUI

struct HomeScreen: View {
  private static var destinationIconColumnWidth: CGFloat { 44 }
  private static var destinationTextInset: CGFloat {
    destinationIconColumnWidth + AppStyle.Space.medium
  }
  let model: HomeModel
  let detailsMotion: Namespace.ID
  let widgetsMotion: Namespace.ID
  let onOutput: (HomeOutput) -> Void
  private var configureLocalCurrency: () -> Void { { onOutput(.locationRequested) } }
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.locale) private var locale
  @Environment(AppAppearance.self) private var appearance
  @State private var refreshRequest: UUID?
  @State private var editingAmount = false
  @State private var listPosition = ScrollPosition(idType: String.self)
  @State private var picker: PickerPurpose?
  @State private var showManage = false
  @State private var opensLocalCurrencyAfterPicker = false
  @Namespace private var currencyMotion
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
    if editingAmount && model.editingSelectionID == model.input.source {
      CurrencyDisplay.inputAmount(model.editingText, locale: locale)
    } else {
      CurrencyDisplay.format(model.input.decimal, code: model.input.source, locale: locale)
    }
  }

  /// The converter screen content.
  public var body: some View {
    Group {
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
        let localCurrencyCode = model.availableLocalCurrency
        let chooser = CurrencyChooser(
          purpose: purpose,
          selected: purpose == .source
            ? [model.input.source] : model.input.manualDestinations + [model.input.source],
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
              model.updateWithFeedback { $0.changeSource(code) }
            } else {
              model.updateWithFeedback {
                if code == CurrencySelection.localID {
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
      .onChange(of: model.editor == nil) { _, empty in
        if empty { editingAmount = false }
      }
    }
    .task(id: refreshRequest) { if refreshRequest != nil { await refresh() } }
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
          // Keep the first row mounted while UIKit collapses the pull-to-refresh inset.
          VStack(spacing: 0) {
            ForEach(model.input.destinationRows) { row in
              VStack(spacing: 0) {
                destinationRow(row)
                Divider().padding(.leading, Self.destinationTextInset)
              }
              .id(row.id)
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
                await refresh()
              }
            }
          }
        }
        .accessibilityAction(named: Text(.Converter.refreshRates)) {
          if !model.refreshing { refreshRequest = UUID() }
        }
        .scrollBounceBehavior(.always)
        .scrollPosition($listPosition)
        .padding(.horizontal, AppStyle.Space.large)
        .task(id: "\(editingAmount)-\(model.editingSelectionID ?? "")-\(viewport.size)") {
          // Wait for the keypad's layout transaction before resolving the row's scroll position.
          do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
          guard editingAmount, model.editingSelectionID != model.input.source else { return }
          if model.editingSelectionID == model.input.destinationRows.last?.id {
            listPosition.scrollTo(edge: .bottom)
          } else {
            listPosition.scrollTo(id: model.editingSelectionID, anchor: .center)
          }
        }
      }
      if let warning = model.warningText {
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
      onOutput(.widgetsRequested)
    } label: {
      Image(systemName: "square.grid.2x2")
    }
    .accessibilityLabel(.Converter.widgets)
    .accessibilityIdentifier("converter.widgets")
    .matchedTransitionSource(id: "widgets", in: widgetsMotion)
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
          onOutput(.settingsRequested)
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
                weight: editingAmount && model.editingSelectionID == model.input.source
                  ? .semibold : .regular)
              : .system(
                size: editingAmount ? editingAmountSize : amountSize,
                weight: editingAmount && model.editingSelectionID == model.input.source
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
    .contextMenu {
      Button(.Converter.detailsAndHistory, systemImage: "chart.xyaxis.line") {
        showDetails(code: model.input.source, selectionID: model.input.source)
      }
    }
    .matchedTransitionSource(id: model.input.source, in: detailsMotion)
  }

  private func destinationRow(_ row: ConverterState.Destination) -> some View {
    let code = row.code
    let value = model.snapshot.convert(model.input.decimal, from: model.input.source, to: code)
    return Button {
      if value == nil {
        showDetails(code: code, selectionID: row.id)
      } else {
        beginEditing(code, selectionID: row.id)
      }
    } label: {
      HStack(spacing: AppStyle.Space.medium) {
        CurrencyIcon(code, size: 28)
          .frame(width: Self.destinationIconColumnWidth, alignment: .leading)
          .matchedGeometryEffect(id: "flag-" + row.id, in: currencyMotion)
          .accessibilityHidden(true)
        let rowLayout =
          dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppStyle.Space.small))
          : AnyLayout(HStackLayout(spacing: AppStyle.Space.medium))
        rowLayout {
          VStack(alignment: .leading, spacing: AppStyle.Space.xs) {
            HStack(spacing: AppStyle.Space.xs) {
              Text(code).font(AppStyle.font(.body, weight: .medium))
                .matchedGeometryEffect(id: row.id, in: currencyMotion)
              if row.isLocal {
                Image(systemName: "location.fill")
                  .font(AppStyle.font(.caption2))
                  .foregroundStyle(.secondary)
                  .accessibilityHidden(true)
              }
            }
            Text(
              row.isLocal
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
            editingAmount && model.editingSelectionID == row.id
              ? CurrencyDisplay.inputAmount(model.editingText, locale: locale)
              : CurrencyDisplay.format(value, code: code, locale: locale)
          )
          .font(
            AppStyle.font(
              .title2,
              weight: editingAmount && model.editingSelectionID == row.id ? .semibold : .regular)
          )
          .monospacedDigit()
          .lineLimit(1).minimumScaleFactor(0.45).contentTransition(.numericText())
          .layoutPriority(1)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).contentShape(Rectangle())
      .matchedTransitionSource(id: row.id, in: detailsMotion)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(

      .Converter.conversionAccessibility(
        row.isLocal
          ? String(
            localized: .Converter.localCurrencyName(
              CurrencyDisplay.name(code, locale: locale)))
          : CurrencyDisplay.name(code, locale: locale),
        CurrencyDisplay.format(value, code: code, locale: locale))
    )
    .accessibilityHint(value == nil ? .Converter.detailsAndHistory : .Converter.editAmountHint)
    .accessibilityAddTraits(
      editingAmount && model.editingSelectionID == row.id ? .isSelected : []
    )
    .contextMenu {
      Button(.Converter.detailsAndHistory, systemImage: "chart.xyaxis.line") {
        showDetails(code: code, selectionID: row.id)
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
          if model.updateWithFeedback({ $0.removeDestination(row.id) }) {
            AppHaptics.play(.delete)
          }
        }
      }
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
            HStack(spacing: 0) {
              Button {
                showDetails(
                  code: model.editingCode,
                  selectionID: model.editingSelectionID ?? model.input.source)
              } label: {
                Group {
                  if verticalSizeClass == .compact {
                    Image(systemName: "chart.xyaxis.line")
                  } else if dynamicTypeSize.isAccessibilitySize {
                    Text(.Converter.history)
                      .lineLimit(1)
                      .minimumScaleFactor(0.7)
                  } else {
                    Label(.Converter.history, systemImage: "chart.xyaxis.line")
                  }
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityLabel(
                .Converter.detailsAccessibility(
                  CurrencyDisplay.name(model.editingCode, locale: locale))
              )
              .accessibilityIdentifier("converter.history")
              HStack(spacing: AppStyle.Space.small) {
                if !dynamicTypeSize.isAccessibilitySize {
                  CurrencyIcon(model.editingCode, size: 14).accessibilityHidden(true)
                }
                Text(verbatim: model.editingCode)
              }
              .frame(maxWidth: .infinity)
              .lineLimit(1)
              .accessibilityElement(children: .ignore)
              .accessibilityLabel(
                .Converter.editingCurrencyAmount(
                  CurrencyDisplay.name(model.editingCode, locale: locale))
              )
              Button {
                dismissAmount()
              } label: {
                Image(systemName: "checkmark")
                  .frame(width: 44, height: 44)
                  .contentShape(Rectangle())
              }
              .frame(maxWidth: .infinity, alignment: .trailing)
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

  private func beginEditing(_ code: String, selectionID: String? = nil) {
    model.beginEditing(code, selectionID: selectionID)
    guard model.editor != nil else { return }
    AppHaptics.play(.action)
    withAnimation(motion) { editingAmount = true }
  }

  private func showDetails(code: String, selectionID: String) {
    AppHaptics.play(.action)
    dismissAmount(feedback: false)
    onOutput(
      .detailsRequested(
        HomeDetailsRequest(
          selectionID: selectionID, code: code, reference: model.input.source,
          snapshot: model.snapshot)))
  }

  private func key(_ key: String) {
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
      if model.press(key) {
        AppHaptics.play(key == "⌫" ? .delete : .selection)
      } else if model.warning == .selectionSaveFailed {
        AppHaptics.play(.error)
      }
    }
  }

  private func refresh() async {
    guard !model.refreshing else { return }
    AppHaptics.play(.action)
    let result = await model.refresh(force: true)
    guard !Task.isCancelled else { return }
    switch result {
    case .refreshed: AppHaptics.play(.success)
    case .warning: AppHaptics.play(.warning)
    case .failed: AppHaptics.play(.error)
    case .cancelled, .ignored: break
    }
  }

}
