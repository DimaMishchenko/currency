import SwiftUI
import WidgetKit
import RateCore

@main
struct CurrencyApp: App {
    var body: some Scene { WindowGroup { ConverterView() } }
}

@MainActor @Observable
final class ConverterModel {
    var input = SharedStore.input()
    var book = SharedStore.rates.load()
    var refreshing = false
    var warning: String?
    private let service = RateService()
    private var widgetReload: Task<Void, Never>?
    func persist() {
        do {
            try SharedStore.save(input)
            widgetReload?.cancel()
            widgetReload = Task {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        catch { warning = "Your selection couldn’t be saved." }
    }
    func refresh(force: Bool = false) async {
        guard !refreshing, force || Date().timeIntervalSince(book.checkedAt ?? .distantPast) >= 1800 else { return }
        refreshing = true
        defer { refreshing = false }
        let result = await service.refresh(previous: book, force: force)
        book = result.book; warning = result.warning
        do { try SharedStore.rates.save(book); WidgetCenter.shared.reloadAllTimelines() }
        catch { warning = "Rates updated, but couldn’t be saved for offline use." }
    }
}

struct ConverterView: View {
    @State private var model = ConverterModel()
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
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 68
    private var canvas: Color { colorScheme == .dark ? Color(red: 0.065, green: 0.073, blue: 0.063) : Color(red: 0.97, green: 0.965, blue: 0.947) }
    private var accent: Color { colorScheme == .dark ? Color(red: 0.79, green: 0.91, blue: 0.56) : Color(red: 0.3, green: 0.39, blue: 0.13) }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86) }
    private var amountLabel: String { model.input.amount.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".") }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    source.padding(.top, editingAmount ? 12 : 22).padding(.bottom, editingAmount ? 12 : 20)
                    HStack {
                        Text("YOUR CURRENCIES").font(.system(size: 10, weight: .semibold)).tracking(1.8)
                        Text(String(format: "%02d", model.input.destinations.count)).font(.system(size: 10, design: .monospaced)).foregroundStyle(accent)
                        Spacer()
                        Button { showManage = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                            .accessibilityLabel("Reorder or remove currencies")
                    }.foregroundStyle(.secondary)
                    Divider()
                    LazyVStack(spacing: 0) {
                        ForEach(model.input.destinations, id: \.self) { code in
                            destinationRow(code)
                            Divider().padding(.leading, 51)
                        }
                    }
                    Button { picker = .add } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus").font(.system(size: 14, weight: .medium)).frame(width: 38)
                            Text("Add currency").font(.subheadline)
                            Spacer()
                        }.foregroundStyle(.secondary).frame(minHeight: 62).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { showInfo = true } label: {
                        HStack(spacing: 6) {
                            Circle().fill(model.warning == nil ? accent : .orange).frame(width: 4, height: 4)
                            Text(model.book.quotes.isEmpty ? "Connect to download rates" : "Saved rates · available offline")
                            Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .medium))
                        }.font(.caption2).foregroundStyle(.secondary).frame(minHeight: 44)
                    }.buttonStyle(.plain).padding(.top, 12)
                    if let warning = model.warning { Text(warning).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.bottom, 10) }
                }.padding(.horizontal, 26).padding(.top, 8).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { inputDock }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $picker) { purpose in
                CurrencyChooser(purpose: purpose, selected: purpose == .source ? [model.input.from] : model.input.destinations + [model.input.from], available: Set(model.book.quotes.keys)) { code in
                    withAnimation(motion) {
                        if purpose == .source { model.input.changeSource(code) }
                        else { model.input.setDestinations(model.input.destinations + [code]) }
                    }
                }
            }
            .sheet(isPresented: $showManage) {
                ManageCurrencies(input: Binding(get: { model.input }, set: { model.input = $0 }))
            }
            .sheet(isPresented: $showInfo) { rateInformation }
            .sheet(isPresented: $showWidgets) { WidgetGuide() }
            .sheet(item: $detail) { selection in CurrencyDetailView(code: selection.id, reference: model.input.from, book: model.book) }
            .task {
                while !Task.isCancelled {
                    if scenePhase == .active { await model.refresh() }
                    do { try await Task.sleep(for: .seconds(60)) } catch { break }
                }
            }
            .onChange(of: model.input) { _, _ in model.persist() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.input = SharedStore.input(); Task { await model.refresh() } }
            }
            .onOpenURL { _ in model.input = SharedStore.input() }
            .sensoryFeedback(.selection, trigger: feedback)
        }.tint(accent)
    }
    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                Text("Currency").font(.system(.title3, design: .rounded, weight: .semibold))
            }
            Spacer()
            Button { showWidgets = true } label: {
                Image(systemName: "square.grid.2x2").frame(width: 44, height: 44)
            }.buttonStyle(.plain).glassEffect(.regular.interactive()).accessibilityLabel("Widgets")
            Menu {
                Button("Refresh rates", systemImage: "arrow.clockwise") { Task { await model.refresh(force: true) } }.disabled(model.refreshing)
                Button("Manage currencies", systemImage: "slider.horizontal.3") { showManage = true }
                Button("About these rates", systemImage: "info.circle") { showInfo = true }
            } label: {
                Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44)
            }.buttonStyle(.plain).glassEffect(.regular.interactive()).accessibilityLabel("Options")
        }
    }
    private var source: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Button { picker = .source } label: {
                    HStack(spacing: 9) {
                        Text(Currency.flag(model.input.from)).font(.system(size: 23)).matchedGeometryEffect(id: "flag-" + model.input.from, in: currencyMotion).accessibilityHidden(true)
                        Text(model.input.from).font(.system(.subheadline, weight: .semibold)).matchedGeometryEffect(id: model.input.from, in: currencyMotion)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("Source currency, \(Currency.name(model.input.from))")
                Spacer()
                Text("BASE AMOUNT").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
            }
            Button {
                replaceOnNextDigit = true
                withAnimation(motion) { editingAmount = true }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(amountLabel).font(.system(size: min(amountSize, editingAmount ? 56 : 110), weight: .light, design: .rounded)).tracking(-3).lineLimit(1).minimumScaleFactor(0.25).contentTransition(.numericText())
                    if editingAmount { Capsule().fill(accent).frame(width: 2, height: 48).transition(.opacity).accessibilityHidden(true) }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Edit amount in \(model.input.from)").accessibilityValue(amountLabel)
            HStack {
                Text(Currency.name(model.input.from)).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if editingAmount { Text("Editing").font(.caption2).foregroundStyle(accent).transition(.opacity) }
            }
        }
    }
    private func destinationRow(_ code: String) -> some View {
        let value = model.book.convert(model.input.decimal, from: model.input.from, to: code)
        return HStack(spacing: 0) {
        Button {
            guard value != nil else { return }
            feedback += 1
            withAnimation(motion) { model.input.useAsBase(code, book: model.book) }
        } label: {
            HStack(spacing: 13) {
                Text(Currency.flag(code)).font(.system(size: 28)).frame(width: 38).matchedGeometryEffect(id: "flag-" + code, in: currencyMotion).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(code).font(.system(.body, weight: .medium)).matchedGeometryEffect(id: code, in: currencyMotion)
                    Text(Currency.name(code)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Text(Currency.format(value, code: code)).font(.system(.title2, design: .rounded, weight: .regular)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.45).contentTransition(.numericText()).layoutPriority(1)
            }.frame(minHeight: 70).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(Currency.name(code)), \(Currency.format(value, code: code))")
            .accessibilityHint("Make this the base currency")
            .contextMenu {
                Button("Details & history", systemImage: "chart.xyaxis.line") { detail = CurrencyDetailSelection(id: code) }
                Button("Use as base", systemImage: "arrow.up") { withAnimation(motion) { model.input.useAsBase(code, book: model.book) } }.disabled(value == nil)
                Button("Copy amount", systemImage: "doc.on.doc") { UIPasteboard.general.string = Currency.format(value, code: code) }.disabled(value == nil)
                Text(model.book.details(from: model.input.from, to: code))
                Button("Remove", systemImage: "minus.circle", role: .destructive) { withAnimation(motion) { model.input.setDestinations(model.input.destinations.filter { $0 != code }) } }
            }
        Button { detail = CurrencyDetailSelection(id: code) } label: {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 44, height: 60)
        }.buttonStyle(.plain).accessibilityLabel("\(Currency.name(code)) details and history")
        }
    }
    private var inputDock: some View {
        GlassEffectContainer(spacing: 30) {
            if editingAmount {
                VStack(spacing: 4) {
                    HStack {
                        Text("\(Currency.flag(model.input.from))  \(model.input.from)").font(.caption.weight(.semibold))
                        Spacer()
                        Button("Clear") { key("AC") }.font(.caption).frame(minWidth: 44, minHeight: 44)
                        Button { withAnimation(motion) { editingAmount = false } } label: { Image(systemName: "checkmark").font(.headline).frame(width: 44, height: 44) }.accessibilityLabel("Done entering amount")
                    }.padding(.horizontal, 24)
                    Grid(horizontalSpacing: 4, verticalSpacing: 2) {
                        ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]], id: \.self) { row in
                            GridRow {
                                ForEach(row, id: \.self) { item in
                                    Button { key(item) } label: {
                                        Group {
                                            if item == "⌫" { Image(systemName: "delete.left").font(.system(size: 22, weight: .light)) }
                                            else { Text(item == "." ? Locale.current.decimalSeparator ?? "." : item).font(.system(size: 26, weight: .regular, design: .rounded)) }
                                        }.frame(maxWidth: .infinity).frame(height: 50).contentShape(Rectangle())
                                    }.buttonStyle(KeyPressStyle()).accessibilityLabel(item == "⌫" ? "Delete digit" : item == "." ? "Decimal separator" : item)
                                }
                            }
                        }
                    }.padding(.horizontal, 14).padding(.bottom, 22)
                }
                .glassEffect(.regular, in: .rect(corners: .concentric(minimum: .fixed(32)), isUniform: true))
                .glassEffectID("amount-dock", in: keypadMotion)
                .glassEffectTransition(.matchedGeometry)
            } else {
                HStack(spacing: 0) {
                    Button {
                        replaceOnNextDigit = true
                        withAnimation(motion) { editingAmount = true }
                    } label: {
                        Label("Enter amount", systemImage: "keyboard").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).frame(height: 52)
                    }.buttonStyle(.plain)
                    Rectangle().fill(.primary.opacity(0.1)).frame(width: 1, height: 20)
                    Button { picker = .add } label: { Image(systemName: "plus").font(.system(size: 17, weight: .medium)).frame(width: 60, height: 52) }.buttonStyle(.plain).accessibilityLabel("Add currency")
                }.frame(maxWidth: 260).glassEffect(.regular.interactive())
                    .glassEffectID("amount-dock", in: keypadMotion)
                    .glassEffectTransition(.matchedGeometry)
            }
        }.padding(.horizontal, 8).padding(.top, 8).padding(.bottom, editingAmount ? 0 : 10)
            .frame(maxWidth: 540).frame(maxWidth: .infinity)
            .padding(.bottom, editingAmount ? -22 : 0)
    }
    private func key(_ key: String) {
        feedback += 1
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            if replaceOnNextDigit && key != "⌫" { model.input.press("AC") }
            replaceOnNextDigit = false
            model.input.press(key)
        }
    }
    private var rateInformation: some View {
        NavigationStack {
            List {
                Section {
                    Text("Daily reference rates, saved on your device. Every conversion uses the latest downloaded rates; bank fees aren’t included.")
                    if model.book.fetchedAt != .distantPast { LabeledContent("Last checked", value: model.book.fetchedAt.formatted(date: .abbreviated, time: .shortened)) }
                    Button("Refresh now", systemImage: "arrow.clockwise") { Task { await model.refresh(force: true) } }.disabled(model.refreshing)
                }
                Section("Publication dates") {
                    ForEach([model.input.from] + model.input.destinations, id: \.self) { code in
                        LabeledContent("\(Currency.flag(code)) \(code)") {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(model.book.quotes[code]?.published ?? "Not downloaded")
                                Text(model.book.quotes[code]?.source ?? "Unavailable").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Home screen") { Text("Widgets share this amount and currency list. The large widget includes a keypad. iOS controls widget input processing and refresh timing.") }
                Section("Sources") { Text("Frankfurter v2 for daily fiat rates, with direct ECB fallback. Fawaz supplies daily crypto and backup rates. Coinbase public market data is checked every 30 minutes while active, falling back to daily crypto rates if unavailable. iOS schedules widget refreshes. No accounts or API keys.") }
            }.navigationTitle("About these rates").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInfo = false } } }
        }
    }
}

private struct KeyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.primary.opacity(configuration.isPressed ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum PickerPurpose: String, Identifiable { case source, add; var id: String { rawValue } }
struct CurrencyChooser: View {
    let purpose: PickerPurpose
    let selected: [String]
    let available: Set<String>
    var choose: (String) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach([false, true], id: \.self) { crypto in
                    Section(crypto ? "Crypto" : "Currencies") {
                        ForEach(Currency.codes.filter { Currency.crypto.contains($0) == crypto && (search.isEmpty || "\($0) \(Currency.name($0))".localizedCaseInsensitiveContains(search)) }, id: \.self) { code in
                            Button { choose(code); dismiss() } label: {
                                HStack(spacing: 14) {
                                    Text(Currency.flag(code)).font(.title2).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(code).font(.headline)
                                        Text(Currency.name(code)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selected.contains(code) { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                                    else if !available.contains(code) { Text("Unavailable").font(.caption2).foregroundStyle(.secondary) }
                                }.padding(.vertical, 4)
                            }.foregroundStyle(.primary).disabled(selected.contains(code))
                        }
                    }
                }
            }.searchable(text: $search).navigationTitle(purpose == .source ? "Base currency" : "Add currency").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct ManageCurrencies: View {
    @Binding var input: InputState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(input.destinations, id: \.self) { code in
                        Label { Text(code).font(.body.weight(.medium)) } icon: { Text(Currency.flag(code)) }
                    }
                    .onDelete { offsets in var list = input.destinations; list.remove(atOffsets: offsets); input.setDestinations(list) }
                    .onMove { source, destination in var list = input.destinations; list.move(fromOffsets: source, toOffset: destination); input.setDestinations(list) }
                } footer: { Text("Drag to reorder. Your widgets follow the same order.") }
            }.environment(\.editMode, .constant(.active)).navigationTitle("Your currencies").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
