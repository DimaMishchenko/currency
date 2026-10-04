import SwiftUI

/// Places two persistent visual regions around a physical division or in a responsive pair.
public struct AdaptivePairLayout: Layout {
  private let division: CGRect?
  private let wide: Bool
  private let previewFraction: CGFloat?
  private let rightToLeft: Bool

  /// Accepts a division in the containing geometry's fixed, scene-local coordinates.
  /// A preview fraction reserves a stable compact stage; physical divisions take precedence.
  public init(
    division: CGRect?, wide: Bool, rightToLeft: Bool = false, previewFraction: CGFloat? = nil
  ) {
    self.previewFraction = previewFraction
    self.division = division
    self.wide = wide
    self.rightToLeft = rightToLeft
  }

  /// Uses the container's proposed size for both regions.
  public func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  /// Places the preview and explanation within their available regions.
  public func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard subviews.count == 2 else { return }
    let explanationWidth = regions(in: bounds.size, explanationHeight: 0).second.width
    let explanationHeight = subviews[1]
      .sizeThatFits(
        ProposedViewSize(width: explanationWidth, height: nil)
      )
      .height
    let regions = regions(in: bounds.size, explanationHeight: explanationHeight)
    for (view, frame) in zip(subviews, [regions.first, regions.second]) {
      view.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
  }

  func regions(in size: CGSize, explanationHeight: CGFloat) -> (first: CGRect, second: CGRect) {
    let fold = division?.intersection(CGRect(origin: .zero, size: size))
    if let fold, !fold.isNull, fold.height > fold.width,
      fold.minX > 0, fold.maxX < size.width
    {
      let left = CGRect(x: 0, y: 0, width: fold.minX, height: size.height)
      let right = CGRect(x: fold.maxX, y: 0, width: size.width - fold.maxX, height: size.height)
      return rightToLeft ? (right, left) : (left, right)
    }
    if let fold, !fold.isNull, fold.width > fold.height,
      fold.minY > 0, fold.maxY < size.height
    {
      return (
        CGRect(x: 0, y: 0, width: size.width, height: fold.minY),
        CGRect(x: 0, y: fold.maxY, width: size.width, height: size.height - fold.maxY)
      )
    }
    if wide {
      let width = size.width / 2
      let left = CGRect(x: 0, y: 0, width: width, height: size.height)
      let right = CGRect(x: width, y: 0, width: width, height: size.height)
      return rightToLeft ? (right, left) : (left, right)
    }
    let footerHeight =
      previewFraction.map { size.height * (1 - min(1, max(0, $0))) }
      ?? min(size.height * 0.6, max(0, explanationHeight))
    let previewHeight = max(0, size.height - footerHeight)
    return (
      CGRect(x: 0, y: 0, width: size.width, height: previewHeight),
      CGRect(x: 0, y: previewHeight, width: size.width, height: footerHeight)
    )
  }
}
