import SwiftUI
import WidgetKit
import AppIntents
import RateCore

struct CurrencyEntry: TimelineEntry {
    let date: Date
    let input: InputState
    let book: RateBook
}
struct CurrencyTimeline: TimelineProvider {
    func placeholder(in context: Context) -> CurrencyEntry { CurrencyEntry(date: .now, input: InputState(), book: RateBook()) }
    func getSnapshot(in context: Context, completion: @escaping (CurrencyEntry) -> Void) {
        completion(CurrencyEntry(date: .now, input: SharedStore.input(), book: SharedStore.rates.load()))
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CurrencyEntry>) -> Void) {
        Task {
            var book = SharedStore.rates.load()
            let input = SharedStore.input()
            let recentlyTyped = Date().timeIntervalSince(input.editedAt ?? .distantPast) < 60
            if !recentlyTyped && Date().timeIntervalSince(book.checkedAt ?? .distantPast) >= 1800 {
                let refreshed = await RateService().refresh(previous: book)
                book = refreshed.book
                try? SharedStore.rates.save(book)
            }
            completion(Timeline(entries: [CurrencyEntry(date: .now, input: SharedStore.input(), book: book)], policy: .after(.now.addingTimeInterval(1800))))
        }
    }
}
struct CurrencyWidgetView: View {
    let entry: CurrencyEntry
    var board = false
    @Environment(\.widgetFamily) private var family
    private var limit: Int { family == .systemSmall ? 1 : board ? (family == .systemLarge ? 12 : 6) : (family == .systemLarge ? 8 : 3) }
    private var targets: [String] { Array(entry.input.destinations.prefix(limit)) }
    private var columns: Int { (board || family == .systemLarge) && targets.count > 3 ? 2 : 1 }
    private var keyHeight: CGFloat { targets.count > 6 ? 36 : 42 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(Currency.flag(entry.input.from)) \(entry.input.from)").font(.caption.weight(.semibold))
                Spacer()
                if family != .systemSmall {
                    Text(entry.input.amount).font(.system(.title3, design: .rounded, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            if family == .systemSmall {
                Text(entry.input.amount).font(.system(.title2, design: .rounded, weight: .light)).lineLimit(1).minimumScaleFactor(0.4)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), spacing: board ? 10 : 5) {
            ForEach(targets, id: \.self) { code in
                HStack {
                    Text("\(Currency.flag(code)) \(code)").font(.system(size: columns == 2 ? 10 : 12, weight: .medium))
                    Spacer(minLength: 4)
                    Text(Currency.format(entry.book.convert(entry.input.decimal, from: entry.input.from, to: code), code: code))
                        .font(.system(size: columns == 2 ? 14 : 19, weight: .medium, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4).contentTransition(.numericText())
                }.frame(minHeight: board && family == .systemLarge ? 28 : 22)
            }
            }
            Spacer(minLength: 0)
            HStack {
            Text(entry.book.quotes.isEmpty ? "Open app to load rates" : "Rates · " + (entry.book.quotes[targets.first ?? entry.input.from]?.published ?? "Unavailable"))
                .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if entry.input.destinations.count > limit { Text("+\(entry.input.destinations.count - limit)").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
            if family == .systemLarge && !board {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach([["1", "2", "3", "AC"], ["4", "5", "6", "⌫"], ["7", "8", "9", "⇅"], [".", "0", "00", "open"]], id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { key in
                                if key == "open" {
                                    Link(destination: URL(string: "currency://convert")!) { Image(systemName: "arrow.up.right").frame(maxWidth: .infinity).frame(height: keyHeight).background(.primary.opacity(0.055), in: .rect(cornerRadius: 10)) }
                                } else {
                                    Button(intent: KeyIntent(key)) { Text(key == "." ? Locale.current.decimalSeparator ?? "." : key).font(.system(size: key == "AC" ? 12 : 19, design: .rounded)).frame(maxWidth: .infinity).frame(height: keyHeight).background(.primary.opacity(0.055), in: .rect(cornerRadius: 10)).contentShape(Rectangle()) }
                                        .accessibilityLabel(key == "⌫" ? "Delete" : key == "AC" ? "Clear" : key == "⇅" ? "Swap" : key)
                                }
                            }
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(URL(string: "currency://convert"))
    }
}
struct CurrencyWidget: Widget {
    let kind = "CurrencyConverter"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurrencyTimeline()) { CurrencyWidgetView(entry: $0) }
            .configurationDisplayName("Converter")
            .description("One amount, your currencies. Large adds a full keypad and up to eight rates.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CurrencyBoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrencyBoard", provider: CurrencyTimeline()) { CurrencyWidgetView(entry: $0, board: true) }
            .configurationDisplayName("Currency board")
            .description("Six currencies in medium, twelve in large. Follows your currency order.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct QuickRateView: View {
    let entry: CurrencyEntry
    @Environment(\.widgetFamily) private var family
    private var target: String { entry.input.destinations.first ?? entry.input.from }
    private var amount: String { Currency.format(entry.book.convert(entry.input.decimal, from: entry.input.from, to: target), code: target) }
    var body: some View {
        Group {
            if family == .accessoryInline {
                Text("\(entry.input.amount) \(entry.input.from) = \(amount) \(target)")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(entry.input.amount) \(entry.input.from) → \(target)").font(.caption)
                    Text(amount).font(.system(.title2, design: .rounded, weight: .semibold)).minimumScaleFactor(0.4)
                    Text("Rates · " + (entry.book.quotes[target]?.published ?? "Open app")).font(.system(size: 9))
                }
            }
        }.lineLimit(1).containerBackground(for: .widget) { Color.clear }.widgetURL(URL(string: "currency://convert"))
    }
}
struct QuickRateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrencyQuickRate", provider: CurrencyTimeline()) { QuickRateView(entry: $0) }
            .configurationDisplayName("Quick rate").description("Your first conversion on the Lock Screen.")
            .supportedFamilies([.accessoryInline, .accessoryRectangular])
    }
}
@main struct CurrencyWidgets: WidgetBundle {
    var body: some Widget { CurrencyWidget(); CurrencyBoardWidget(); QuickRateWidget() }
}
