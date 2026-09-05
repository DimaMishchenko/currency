import SwiftUI

struct WidgetGuide: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(.Converter.widgetGuideHeadline)
            .font(.system(.largeTitle, design: .rounded, weight: .light))
            .padding(.vertical, 16)
          Text(
            .Converter.widgetGuideIntroduction
          )
        }
        Section(.Converter.homeScreenGuide) {
          Label {
            VStack(alignment: .leading, spacing: 6) {
              Text(.Converter.converter).font(.headline)
              Text(
                .Converter.converterWidgetGuide
              )
              .font(.subheadline).foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "keyboard")
          }
          Label {
            VStack(alignment: .leading, spacing: 6) {
              Text(.Converter.currencyBoard).font(.headline)
              Text(
                .Converter.boardWidgetGuide
              )
              .font(.subheadline).foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "square.grid.2x2")
          }
        }
        Section(.Converter.lockScreen) {
          Label(.Converter.quickRateGuide, systemImage: "lock")
          Text(.Converter.quickRateExplanation)
            .font(.subheadline).foregroundStyle(.secondary)
        }
        Section(.Converter.addWidget) {
          Text(
            .Converter.addWidgetInstructions
          )
          Text(.Converter.lockScreenInstructions)
        }
        Section {
          Text(
            .Converter.widgetRefreshExplanation
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      .navigationTitle(.Converter.widgets).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(.Converter.done) { dismiss() }
        }
      }
    }
  }
}
