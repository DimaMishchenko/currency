import SwiftUI

struct ConverterLayout: Layout {
  enum Mode: Equatable {
    case stacked
    case columns(CGRect, CGRect)
    case tabletop(CGRect, CGRect)

    var isStacked: Bool {
      if case .stacked = self { return true }
      return false
    }
  }

  struct Frames {
    let source: CGRect
    let results: CGRect
    let dock: CGRect
  }

  var mode: Mode
  var rightToLeft = false

  static func mode(size: CGSize, division: CGRect?, accessible: Bool) -> Mode {
    let bounds = CGRect(origin: .zero, size: size)
    if let division {
      let fold = division.intersection(bounds)
      if !fold.isNull {
        if fold.height > fold.width, fold.minX > 0, fold.maxX < size.width {
          return .columns(
            CGRect(x: 0, y: 0, width: fold.minX, height: size.height),
            CGRect(x: fold.maxX, y: 0, width: size.width - fold.maxX, height: size.height))
        }
        if fold.width > fold.height, fold.minY > 0, fold.maxY < size.height {
          return .tabletop(
            CGRect(x: 0, y: fold.maxY, width: size.width, height: size.height - fold.maxY),
            CGRect(x: 0, y: 0, width: size.width, height: fold.minY))
        }
      }
    }
    guard size.width >= (accessible ? 1000 : (size.height < 440 ? 540 : 700)),
      size.height <= size.width * 1.2
    else {
      return .stacked
    }
    let gutter: CGFloat = 32
    let width = (size.width - gutter) / 2
    let height = size.height
    let top: CGFloat = 0
    return .columns(
      CGRect(x: 0, y: top, width: width, height: height),
      CGRect(x: width + gutter, y: top, width: width, height: height))
  }

  func regions(in size: CGSize) -> (controls: CGRect, results: CGRect?) {
    switch mode {
    case .stacked:
      return (CGRect(origin: .zero, size: size), nil)
    case .columns(let left, let right):
      return rightToLeft ? (right, left) : (left, right)
    case .tabletop(let bottom, let top):
      return (bottom, top)
    }
  }

  func frames(in size: CGSize, sourceHeight: CGFloat) -> Frames {
    let (controls, results) = regions(in: size)
    if let results {
      let height = min(max(0, sourceHeight), controls.height * 0.4)
      let source = CGRect(
        x: controls.minX, y: controls.minY, width: controls.width, height: height)
      let dockHeight = max(0, controls.height - height)
      return Frames(
        source: source, results: results,
        dock: CGRect(
          x: controls.minX, y: controls.maxY - dockHeight,
          width: controls.width, height: dockHeight))
    }
    let height = min(max(0, sourceHeight), controls.height * 0.4)
    return Frames(
      source: CGRect(x: 0, y: 0, width: size.width, height: height),
      results: CGRect(x: 0, y: height, width: size.width, height: max(0, size.height - height)),
      dock: .zero)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard subviews.count == 3 else { return }
    let controls = regions(in: bounds.size).controls
    let measurement = ProposedViewSize(width: controls.width, height: nil)
    let frames = frames(
      in: bounds.size, sourceHeight: subviews[0].sizeThatFits(measurement).height)
    for (view, frame) in zip(subviews, [frames.source, frames.results, frames.dock]) {
      view.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
  }
}
