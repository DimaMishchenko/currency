import CurrencySupport
import SwiftUI
import WidgetKit

/// The calculator widget layout, with size-specific display paging and shared controls.
public struct CalculatorLayout: View {
  let entry: SuiteEntry
  let family: WidgetFamily
  let previewProgress: CGFloat?

  /// Creates the real calculator layout for a supported medium or large family.
  public init(entry: SuiteEntry, family: WidgetFamily, previewProgress: CGFloat? = nil) {
    self.entry = entry; self.family = family; self.previewProgress = previewProgress
  }

  private var codes: [String] {
    entry.input.visibleCodes(
      limit: family == .systemMedium ? 4 : 8, reservesLocal: entry.spec.synchronized)
  }

  private var displayEntry: SuiteEntry {
    var display = entry
    display.input = entry.input.displayedInput(
      limit: family == .systemMedium ? 4 : 8,
      reservesLocal: entry.spec.synchronized, snapshot: entry.snapshot)
    return display
  }

  /// The calculator tiles and keypad.
  public var body: some View {
    GeometryReader { geometry in
      if entry.spec.codes.isEmpty {
        Text(.WidgetPresentation.chooseCustomCurrencies)
          .font(AppStyle.font(.callout)).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        let medium = family == .systemMedium
        let columns = medium && codes.count <= 2 ? 1 : 2
        let rows = max(1, (codes.count + columns - 1) / columns)
        VStack(spacing: AppStyle.Space.small) {
          CalculatorArrangement(
            expansion: medium ? 0 : 1,
            largeTileHeight: max(56, geometry.size.height * (rows == 1 ? 0.26 : 0.43)),
            previewProgress: previewProgress
          ) {
            VStack(spacing: AppStyle.Space.xs) {
              ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: AppStyle.Space.xs) {
                  ForEach(Array(codes.dropFirst(row * columns).prefix(columns)), id: \.self) {
                    code in
                    CurrencyTile(
                      entry: displayEntry, code: code,
                      compact: medium ? codes.count > 2 : rows == 4,
                      stacked: medium || rows == 1,
                      showsCode: medium || rows != 4,
                      previewSpread: previewProgress.map {
                        CalculatorPreviewTransition(progress: $0).spread
                      })
                  }
                  if columns == 2 && row * columns + 1 >= codes.count {
                    Color.clear.frame(maxWidth: .infinity)
                      .accessibilityHidden(true).allowsHitTesting(false)
                  }
                }
              }
              if medium { WidgetFooter(entry: entry) }
            }
            WidgetKeypad(
              spec: entry.spec,
              activeCurrency: displayEntry.input.active != entry.input.active
                ? displayEntry.input.active : nil,
              hiddenCurrency: displayEntry.input.active != entry.input.active
                ? entry.input.active : nil
            )
            .disabled(
              !codes.contains(displayEntry.input.active)
                || displayEntry.input.active == WidgetSelection.localID)
          }
          if !medium { WidgetFooter(entry: entry) }
        }
      }
    }
    .animation(nil, value: entry.input)
    .modifier(WidgetSurface())
  }

}

/// Moves the keypad below the tiles before either group expands horizontally.
/// Endpoints retain the installed widget's medium and large sizing.
private struct CalculatorArrangement: Layout {
  var expansion: CGFloat
  let largeTileHeight: CGFloat
  var previewProgress: CGFloat?
  var animatableData: CGFloat {
    get { expansion }
    set { expansion = newValue }
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard subviews.count == 2 else { return }
    if let previewProgress {
      let transition = CalculatorPreviewTransition(progress: previewProgress)
      let gap = AppStyle.Space.small
      let mediumWidth = bounds.width * 0.46
      let targetTileHeight: CGFloat = 340 * 0.43
      let tileHeight = 140 + (targetTileHeight - 140) * transition.move
      let keypadHeight = 140 + (340 - targetTileHeight - gap - 140) * transition.move
      let tileWidth = mediumWidth + (bounds.width - mediumWidth) * transition.spread
      let keypadX = (mediumWidth + gap) * (1 - transition.spread)
      let keypadY = (targetTileHeight + gap) * transition.move
      subviews[0].place(at: bounds.origin, proposal: .init(width: tileWidth, height: tileHeight))
      subviews[1]
        .place(
          at: .init(x: bounds.minX + keypadX, y: bounds.minY + keypadY),
          proposal: .init(width: bounds.width - keypadX, height: keypadHeight))
      return
    }
    let p = min(1, max(0, expansion))
    let move = smooth(min(1, p / 0.48))
    let spread = smooth(max(0, (p - 0.48) / 0.52))
    let gap = AppStyle.Space.small
    let mediumWidth = bounds.width * 0.46
    let targetHeight = min(bounds.height, largeTileHeight)
    let tileWidth = mediumWidth + (bounds.width - mediumWidth) * spread
    let tileHeight = bounds.height + (targetHeight - bounds.height) * move
    let keypadX = (mediumWidth + gap) * (1 - spread)
    let keypadY = (targetHeight + gap) * move
    subviews[0]
      .place(at: bounds.origin, proposal: ProposedViewSize(width: tileWidth, height: tileHeight))
    subviews[1]
      .place(
        at: CGPoint(x: bounds.minX + keypadX, y: bounds.minY + keypadY),
        proposal: ProposedViewSize(
          width: max(0, bounds.width - keypadX), height: max(0, bounds.height - keypadY)))
  }
  private func smooth(_ value: CGFloat) -> CGFloat { value * value * (3 - 2 * value) }
}

/// One clock drives the app's four-currency calculator size demonstration.
/// Installed widgets use their family directly and do not consume this transition.
public struct CalculatorPreviewTransition {
  let move: CGFloat
  let spread: CGFloat
  /// Fixed-width widget canvas height for this animation frame.
  public var canvasHeight: CGFloat { 164 + 200 * move }
  /// Creates staged geometry: move vertically, then expand horizontally.
  public init(progress: CGFloat) {
    let p = min(1, max(0, progress))
    let m = min(1, p / 0.60)
    let s = max(0, (p - 0.60) / 0.40)
    move = m * m * (3 - 2 * m)
    spread = s * s * (3 - 2 * s)
  }
}
