import SwiftUI

struct WidgetGuide: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Your currencies, one glance away.")
            .font(.system(.largeTitle, design: .rounded, weight: .light))
            .padding(.vertical, 16)
          Text(
            "Every widget follows your amount and currency order. Put your most-used currencies first."
          )
        }
        Section("Home Screen") {
          Label {
            VStack(alignment: .leading, spacing: 6) {
              Text("Converter").font(.headline)
              Text(
                "A quiet pair in small, three rates in medium. Large fits up to eight rates and a complete numeric keypad."
              )
              .font(.subheadline).foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "keyboard")
          }
          Label {
            VStack(alignment: .leading, spacing: 6) {
              Text("Currency board").font(.headline)
              Text(
                "More currencies, more space. Up to six in medium or twelve in large, with a layout that follows your list."
              )
              .font(.subheadline).foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "square.grid.2x2")
          }
        }
        Section("Lock Screen") {
          Label("Quick rate · inline or rectangular", systemImage: "lock")
          Text("Your first currency, always easy to find. Tap to open the converter.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        Section("Add a widget") {
          Text(
            "Touch and hold your Home Screen, choose Edit → Add Widget, then search for Currency. Swipe to choose a size."
          )
          Text("For Lock Screen widgets, touch and hold your Lock Screen and choose Customize.")
        }
        Section {
          Text(
            "Fiat rates are daily. Crypto checks Coinbase every 30 minutes, with daily fallback. Rates are cached offline. iOS controls widget refresh timing; keypad updates may take a moment."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Widgets").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}
