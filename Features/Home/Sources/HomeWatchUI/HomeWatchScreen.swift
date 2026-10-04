import Conversion
import ExchangeRates
import ExchangeRatesUI
import Home
import SwiftUI

/// Watch converter presentation using an explicitly supplied shared feature model.
public struct HomeWatchScreen: View {
  @Bindable private var model: HomeModel
  private let output: (HomeOutput) -> Void
  @State private var amount = ""
  @State private var editingAmount = false
  @State private var choosingSource = false
  @State private var addingCurrency = false
  @State private var refreshRequested = false
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// Supplies the flow model and semantic navigation receiver.
  public init(model: HomeModel, output: @escaping (HomeOutput) -> Void) {
    self.model = model
    self.output = output
  }

  /// Keeps confirmed converter input visible when rates cannot be refreshed.
  public var body: some View {
    List {
      Section {
        Button {
          amount = model.input.amount
          editingAmount = true
        } label: {
          VStack(alignment: .leading) {
            Text(.Watch.amountLabel).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: amountLabel(model.input.decimal, code: model.input.source))
              .font(.system(.title2, design: .rounded, weight: .medium)).monospacedDigit()
              .contentTransition(reduceMotion ? .identity : .numericText())
              .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.input.amount)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityLabel(Text(.Watch.editAmount))
        .accessibilityValue(Text(verbatim: sourceAccessibilityAmount))
        .accessibilityIdentifier("watch.home.amount")
        Button {
          choosingSource = true
        } label: {
          HStack(spacing: 8) {
            CurrencyIcon(model.input.source, size: 24)
            Text(verbatim: model.input.source).font(.system(.headline, design: .rounded))
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
          }
        }
        .accessibilityLabel(Text(.Watch.sourceCurrency))
        .accessibilityValue(Text(verbatim: model.input.source))
        .accessibilityIdentifier("watch.home.source")
        GlassEffectContainer(spacing: 6) {
          HStack(spacing: 6) {
            ForEach([1, 10, 100], id: \.self) { value in
              Button {
                _ = model.commitAmount(String(value))
              } label: {
                Text(verbatim: String(value))
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.glass)
              .accessibilityIdentifier("watch.home.preset.\(value)")
            }
          }
        }
        .listRowBackground(Color.clear)
      }
      Section {
        ForEach(model.input.destinationRows) { destination in
          Button {
            output(
              .detailsRequested(
                .init(
                  selectionID: destination.id, code: destination.code,
                  reference: model.input.source, snapshot: model.snapshot)))
          } label: {
            HStack(alignment: .top, spacing: 8) {
              CurrencyIcon(destination.code, size: 24).padding(.top, 2)
              VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: destination.code).font(.system(.headline, design: .rounded))
                if !dynamicTypeSize.isAccessibilitySize {
                  Text(verbatim: CurrencyDisplay.name(destination.code, locale: locale))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if let value = model.row(destination.code, selectionID: destination.id).amount {
                  Text(verbatim: amountLabel(value, code: destination.code))
                    .font(.system(.body, design: .rounded, weight: .medium)).monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: value)
                } else {
                  Text(.Watch.rateUnavailable).foregroundStyle(.secondary)
                }
                if destination.isLocal && model.input.localCurrencyIsStale {
                  Text(.Watch.savedLocation).font(.caption2).foregroundStyle(.secondary)
                }
              }
            }
            .fixedSize(horizontal: false, vertical: true)
          }
          .accessibilityIdentifier("watch.home.destination.\(destination.id)")
          .swipeActions(edge: .trailing) {
            Button(.Watch.removeCurrency, role: .destructive) {
              model.removeDestinations([destination.id])
            }
          }
          .swipeActions(edge: .leading) {
            Button(.Watch.useAsBase) { model.useAsBase(destination.code) }
              .disabled(model.row(destination.code).amount == nil)
          }
        }
        Button(.Watch.addCurrency, systemImage: "plus") { addingCurrency = true }
          .accessibilityIdentifier("watch.home.add")
        if let first = model.input.destinations.first {
          Button(.Watch.swapCurrencies, systemImage: "arrow.up.arrow.down") {
            model.useAsBase(first)
          }
          .disabled(model.row(first).amount == nil)
          .accessibilityIdentifier("watch.home.swap")
        }
      } header: {
        Text(.Watch.myCurrencies)
      }
      Section {
        if model.snapshot.quotes.isEmpty {
          Text(.Watch.noRates)
        } else {
          Text(.Watch.savedRates)
          Text(model.snapshot.fetchedAt, format: .dateTime.month().day().hour().minute())
            .font(.caption2).foregroundStyle(.secondary)
        }
        if let warning = model.warning { Text(message(warning)).font(.caption2) }
        if model.refreshing {
          ProgressView().accessibilityLabel(Text(.Watch.refreshing))
        }
        Button(.Watch.refreshRates, systemImage: "arrow.clockwise") { refreshRequested = true }
          .disabled(model.refreshing || refreshRequested)
          .accessibilityIdentifier("watch.home.refresh")
      }
    }
    .font(.system(.body, design: .rounded))
    .navigationTitle(Text(.Watch.converterTitle))
    .sheet(isPresented: $editingAmount) {
      WatchAmountEntry(amount: amount, save: { model.commitAmount($0) })
    }
    .sheet(isPresented: $choosingSource) {
      WatchCurrencyPicker(excluded: [], selected: model.input.source) {
        model.changeSource($0)
      }
    }
    .sheet(isPresented: $addingCurrency) {
      WatchCurrencyPicker(
        excluded: Set([model.input.source] + model.input.manualDestinations), selected: nil
      ) { model.addDestination($0) }
    }
    .task { await model.observeChanges() }
    .task(id: refreshRequested) {
      guard refreshRequested else { return }
      _ = await model.refresh(force: true)
      refreshRequested = false
    }
  }

  private var sourceAccessibilityAmount: String {
    if CurrencyCatalog.metals.contains(model.input.source) {
      return amountLabel(model.input.decimal, code: model.input.source)
    }
    return "\(model.input.amount) \(model.input.source)"
  }

  private func amountLabel(_ value: Decimal, code: String) -> String {
    let amount = formatted(value, code: code)
    if CurrencyCatalog.metals.contains(code) {
      var resource = LocalizedStringResource.Watch.metalAmount(amount, code)
      resource.locale = locale
      return String(localized: resource)
    }
    return amount
  }

  private func formatted(_ value: Decimal, code: String) -> String {
    let digits = CurrencyPrecision.fractionDigits(code)
    var minorUnit: Decimal = 1
    for _ in 0..<digits { minorUnit /= 10 }
    if value > 0 && value < minorUnit {
      return value.formatted(.number.precision(.significantDigits(3...6)).locale(locale))
    }
    return value.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
  }

  private func message(_ issue: HomeIssue) -> LocalizedStringResource {
    switch issue {
    case .selectionSaveFailed: .Watch.saveFailed
    case .rateSaveFailed: .Watch.rateSaveFailed
    case .rateWarning(.dailyRatesUnavailable): .Watch.offlineRates
    case .rateWarning(.partialCryptoFallback): .Watch.cryptoFallback
    }
  }
}

private struct WatchAmountEntry: View {
  let save: (String) -> Bool
  @State private var draft: ConverterState
  @State private var replacing = true
  @State private var failed = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(amount: String, save: @escaping (String) -> Bool) {
    var input = ConverterState()
    input.setAmount(amount)
    _draft = State(initialValue: input)
    self.save = save
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        VStack(spacing: 6) {
          Text(
            verbatim: draft.amount.replacingOccurrences(
              of: ".", with: locale.decimalSeparator ?? ".")
          )
          .font(.system(.title2, design: .rounded, weight: .medium)).monospacedDigit()
          .foregroundStyle(replacing ? Color.accentColor : Color.primary)
          .lineLimit(1).minimumScaleFactor(0.35)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .frame(height: 26)
          .contentTransition(reduceMotion ? .identity : .numericText())
          .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: draft.amount)
          .accessibilityLabel(Text(.Watch.amountLabel))
          .accessibilityIdentifier("watch.home.amountField")
          GlassEffectContainer(spacing: 4) {
            Grid(horizontalSpacing: 6, verticalSpacing: 4) {
              ForEach(0..<4) { row in
                GridRow {
                  ForEach(0..<3) { column in
                    let key = keys[row][column]
                    Button {
                      press(key)
                    } label: {
                      Group {
                        if key == "⌫" {
                          Image(systemName: "delete.left")
                        } else {
                          Text(verbatim: key == "." ? locale.decimalSeparator ?? "." : key)
                        }
                      }
                      .font(.system(.title3, design: .rounded, weight: .medium))
                      .frame(maxWidth: .infinity)
                      .frame(height: max(20, (geometry.size.height - 44) / 4))
                      .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityLabel(keyLabel(key))
                    .accessibilityIdentifier("watch.home.key.\(key)")
                  }
                }
              }
            }
          }
        }
        .padding(.horizontal, 4)
      }
      .navigationTitle(Text(.Watch.amountLabel))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            if save(draft.amount) { dismiss() } else { failed = true }
          } label: {
            Image(systemName: "checkmark")
          }
          .accessibilityLabel(Text(.Watch.done))
          .accessibilityIdentifier("watch.home.amountDone")
        }
      }
      .alert(Text(.Watch.saveFailed), isPresented: $failed) {
        Button(.Watch.done, role: .cancel) {}
      }
    }
  }

  private let keys = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]

  private func press(_ key: String) {
    if replacing && key != "⌫" { draft.press("AC") }
    replacing = false
    draft.press(key)
  }

  private func keyLabel(_ key: String) -> Text {
    switch key {
    case "⌫": Text(.Watch.deleteDigit)
    case ".": Text(.Watch.decimalSeparator)
    default: Text(verbatim: key)
    }
  }
}

private struct WatchCurrencyPicker: View {
  let excluded: Set<String>
  let selected: String?
  let save: (String) -> Bool
  @State private var search = ""
  @State private var failed = false
  @Environment(\.locale) private var locale
  @Environment(\.dismiss) private var dismiss

  private var codes: [String] {
    if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return CurrencyCatalog.codes.filter { !excluded.contains($0) }.sorted()
    }
    return CurrencyCatalog.search(
      search, allowedCodes: Set(CurrencyCatalog.codes).subtracting(excluded),
      locale: locale, name: name)
  }

  var body: some View {
    NavigationStack {
      List {
        if failed { Text(.Watch.saveFailed) }
        ForEach(codes, id: \.self) { code in
          Button {
            if save(code) { dismiss() } else { failed = true }
          } label: {
            HStack(spacing: 8) {
              CurrencyIcon(code, size: 24)
              VStack(alignment: .leading, spacing: 3) {
                HStack {
                  Text(verbatim: code).font(.system(.headline, design: .rounded))
                  if selected == code { Image(systemName: "checkmark") }
                }
                Text(verbatim: name(code)).font(.caption2).foregroundStyle(.secondary)
              }
            }
          }
          .accessibilityIdentifier("watch.home.currency.\(code)")
        }
      }
      .searchable(text: $search)
      .navigationTitle(Text(.Watch.currenciesTitle))
    }
  }

  private func name(_ code: String) -> String {
    CurrencyCatalog.assetName(code) ?? locale.localizedString(forCurrencyCode: code) ?? code
  }
}
