import CurrencySupport
import SwiftUI

struct WidgetGuide: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(.Converter.widgetGuideHeadline)
            .font(AppStyle.font(.largeTitle, weight: .light))
            .padding(.vertical, AppStyle.Space.large)
          Text(
            .Converter.widgetGuideIntroduction
          )
        }
        Section(.Converter.homeScreenGuide) {
          Label {
            VStack(alignment: .leading, spacing: AppStyle.Space.small) {
              Text(.Converter.converter).font(AppStyle.font(.headline))
              Text(
                .Converter.converterWidgetGuide
              )
              .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "keyboard")
          }
          Label {
            VStack(alignment: .leading, spacing: AppStyle.Space.small) {
              Text(.Converter.currencyBoard).font(AppStyle.font(.headline))
              Text(
                .Converter.boardWidgetGuide
              )
              .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "square.grid.2x2")
          }
        }
        Section(.Converter.lockScreen) {
          Label(.Converter.quickRateGuide, systemImage: "lock")
          Text(.Converter.quickRateExplanation)
            .font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
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
          .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
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
