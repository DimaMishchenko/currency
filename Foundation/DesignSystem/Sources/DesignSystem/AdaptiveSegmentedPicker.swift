import SwiftUI

/// A native segmented picker that uses a menu when its labels need more space.
public struct AdaptiveSegmentedPicker<Selection: Hashable>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding private var selection: Selection
  private let label: Text
  private let choices: [Selection]
  private let optionTitle: (Selection) -> Text
  private let fullTitle: (Selection) -> Text

  /// Creates a picker with compact segment labels and optional full menu and accessibility labels.
  public init(
    _ label: LocalizedStringResource,
    choices: [Selection],
    selection: Binding<Selection>,
    optionTitle: @escaping (Selection) -> Text,
    fullTitle: ((Selection) -> Text)? = nil
  ) {
    self.label = Text(label)
    self.choices = choices
    _selection = selection
    self.optionTitle = optionTitle
    self.fullTitle = fullTitle ?? optionTitle
  }

  /// Displays segments when every label fits, or an accessible menu with full option labels.
  public var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      menu
    } else {
      ViewThatFits(in: .horizontal) {
        ZStack {
          sizingProxy.hidden().accessibilityHidden(true)
          Picker(selection: $selection) {
            ForEach(choices, id: \.self) { choice in
              optionTitle(choice).accessibilityLabel(fullTitle(choice)).tag(choice)
            }
          } label: {
            label
          }
          .pickerStyle(.segmented)
        }
        menu
      }
    }
  }

  private var sizingProxy: some View {
    HStack(spacing: 0) {
      ForEach(choices, id: \.self) { _ in
        ZStack {
          ForEach(choices, id: \.self) { choice in
            optionTitle(choice)
              .font(.footnote.weight(.medium))
              .fixedSize()
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private var menu: some View {
    Menu {
      Picker(selection: $selection) {
        ForEach(choices, id: \.self) { choice in
          fullTitle(choice).tag(choice)
        }
      } label: {
        label
      }
    } label: {
      HStack {
        fullTitle(selection)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        Image(systemName: "chevron.up.chevron.down")
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.bordered)
    .accessibilityLabel(label)
    .accessibilityValue(fullTitle(selection))
  }
}
