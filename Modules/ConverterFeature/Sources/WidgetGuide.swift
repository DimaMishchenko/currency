import CurrencySupport
import SwiftUI

struct WidgetGuide: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss
  @State private var location = WidgetLocationController()
  var body: some View {
    NavigationStack {
      List {
        Section(.Converter.localComparisonTitle) {
          Text(
            .Converter.localComparisonGuide
          )
          Text(location.status).font(AppStyle.font(.caption)).foregroundStyle(.secondary)
          Button(location.isUpdating ? .Converter.localUpdating : .Converter.localUpdate) {
            location.update()
          }
          .disabled(location.isUpdating)
          if location.permissionDenied {
            Button(.Converter.openLocationSettings) {
              openURL(URL(string: UIApplication.openSettingsURLString)!)
            }
          }
          Button(.Converter.localRemove) { location.clear() }
          Text(
            .Converter.localPrivacy
          )
          .font(AppStyle.font(.caption)).foregroundStyle(.secondary)
        }
        Section {
          Text(.Converter.widgetGuideHeadline)
            .font(AppStyle.font(.largeTitle, weight: .light))
            .padding(.vertical, AppStyle.Space.large)
          Text(
            .Converter.widgetGuideIntroduction
          )
        }
        Section(.Converter.homeScreenGuide) {
          guide(
            .Converter.multiWidgetTitle,
            .Converter.multiWidgetGuide,
            icon: "square.grid.2x2")
          guide(
            .Converter.pairWidgetTitle,
            .Converter.pairWidgetGuide,
            icon: "keyboard")
          guide(
            .Converter.cashWidgetTitle,
            .Converter.cashWidgetGuide,
            icon: "banknote")
          guide(
            .Converter.pocketWidgetTitle, .Converter.pocketWidgetGuide, icon: "creditcard")
          guide(
            .Converter.mentalWidgetTitle, .Converter.mentalWidgetGuide, icon: "brain")
          guide(
            .Converter.currencyBoard,
            .Converter.newBoardWidgetGuide,
            icon: "list.bullet")
        }
        Section(.Converter.widgetSettingsTitle) {
          Text(.Converter.editWidgetGuide)
          Text(
            .Converter.widgetIndependenceGuide
          )
          Text(
            .Converter.widgetEntryGuide
          )
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
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { location.reconcileAuthorization() }
      }
      .navigationTitle(.Converter.widgets).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(.Converter.close, systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
        }
      }
    }
  }

  private func guide(
    _ title: LocalizedStringResource, _ detail: LocalizedStringResource, icon: String
  ) -> some View {
    Label {
      VStack(alignment: .leading, spacing: AppStyle.Space.small) {
        Text(title).font(AppStyle.font(.headline))
        Text(detail).font(AppStyle.font(.subheadline)).foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: icon)
    }
  }
}
