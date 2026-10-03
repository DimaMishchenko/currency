import SwiftUI
import Testing

@testable import HomeUI

struct ConverterLayoutTests {
  @Test func tallUnfoldedWindowsStackWhilePhysicalDivisionsRemainAuthoritative() {
    let portrait = CGSize(width: 834, height: 1200)
    #expect(ConverterLayout.mode(size: portrait, division: nil, accessible: false).isStacked)
    #expect(
      !ConverterLayout.mode(
        size: CGSize(width: 1200, height: 834), division: nil, accessible: false
      )
      .isStacked)
    #expect(
      !ConverterLayout.mode(
        size: portrait, division: CGRect(x: 400, y: 0, width: 24, height: 1200),
        accessible: false
      )
      .isStacked)
  }

  @Test func offCenterBookKeepsBothPanelsOutsideThePhysicalDivisionInEitherDirection() {
    let size = CGSize(width: 1024, height: 740)
    let fold = CGRect(x: 390, y: 0, width: 24, height: size.height)
    let mode = ConverterLayout.mode(size: size, division: fold, accessible: false)
    for rightToLeft in [false, true] {
      let layout = ConverterLayout(mode: mode, rightToLeft: rightToLeft)
      let frames = layout.frames(in: size, sourceHeight: 150)
      for frame in [frames.source, frames.results, frames.dock] {
        #expect(!frame.intersects(fold))
        #expect(CGRect(origin: .zero, size: size).contains(frame))
      }
      #expect(frames.source.minX == frames.dock.minX)
      #expect(frames.source.width == frames.dock.width)
      #expect(frames.source.maxY <= frames.dock.minY)
      if rightToLeft {
        #expect(frames.source.minX == fold.maxX)
        #expect(frames.results.maxX == fold.minX)
      } else {
        #expect(frames.source.maxX == fold.minX)
        #expect(frames.results.minX == fold.maxX)
      }
    }
  }

  @Test func tabletopKeepsResultsAboveFoldAndControlsBelowIt() {
    let size = CGSize(width: 720, height: 760)
    let fold = CGRect(x: 0, y: 420, width: size.width, height: 22)
    let mode = ConverterLayout.mode(size: size, division: fold, accessible: true)
    for rightToLeft in [false, true] {
      let frames = ConverterLayout(mode: mode, rightToLeft: rightToLeft)
        .frames(in: size, sourceHeight: 180)
      #expect(frames.results.maxY == fold.minY)
      #expect(frames.source.minY == fold.maxY)
      #expect(frames.source.maxY <= frames.dock.minY)
      #expect(frames.dock.maxY == size.height)
      #expect(frames.dock.height > 0)
    }
  }

  @Test func shortWindowsRetainResultsAndScrollableControlSpace() {
    for size in [CGSize(width: 390, height: 220), CGSize(width: 850, height: 240)] {
      let mode = ConverterLayout.mode(size: size, division: nil, accessible: false)
      let frames = ConverterLayout(mode: mode).frames(in: size, sourceHeight: 400)
      #expect(frames.source.height > 0)
      #expect(frames.results.height > 0)
      #expect(frames.results.width > 0)
      #expect(!frames.source.intersects(frames.results))
      if !mode.isStacked {
        #expect(frames.dock.height > frames.source.height)
        #expect(!frames.dock.intersects(frames.results))
      }
    }
  }

  @Test func narrowAndAccessibleWindowsStackUntilTheyCanSupportTwoPanels() {
    #expect(
      ConverterLayout.mode(size: CGSize(width: 390, height: 800), division: nil, accessible: false)
        .isStacked)
    #expect(
      ConverterLayout.mode(size: CGSize(width: 900, height: 800), division: nil, accessible: true)
        .isStacked)
    #expect(
      !ConverterLayout.mode(size: CGSize(width: 1100, height: 800), division: nil, accessible: true)
        .isStacked)
  }

  @Test func nonSeparatingDivisionsDoNotProduceEmptyPanels() {
    let size = CGSize(width: 1024, height: 800)
    for fold in [
      CGRect(x: -20, y: 0, width: 20, height: size.height),
      CGRect(x: 1200, y: 0, width: 20, height: size.height),
      CGRect(x: 0, y: 0, width: size.width, height: 20)
    ] {
      let frames = ConverterLayout(
        mode: ConverterLayout.mode(size: size, division: fold, accessible: false)
      )
      .frames(in: size, sourceHeight: 150)
      #expect(frames.source.width > 0)
      #expect(frames.results.width > 0)
      #expect(frames.results.height > 0)
      #expect(CGRect(origin: .zero, size: size).contains(frames.dock))
    }
  }
}
