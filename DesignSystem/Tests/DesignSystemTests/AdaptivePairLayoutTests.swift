import SwiftUI
import Testing

@testable import DesignSystem

@Suite struct AdaptivePairLayoutTests {
  @Test func bookUsesPhysicalDivisionWithReadingOrder() {
    let size = CGSize(width: 900, height: 700)
    let division = CGRect(x: 430, y: 0, width: 24, height: 700)
    let leftToRight = AdaptivePairLayout(division: division, wide: true)
      .regions(in: size, explanationHeight: 300)
    let rightToLeft = AdaptivePairLayout(division: division, wide: true, rightToLeft: true)
      .regions(in: size, explanationHeight: 300)
    #expect(leftToRight.first.maxX == division.minX)
    #expect(leftToRight.second.minX == division.maxX)
    #expect(rightToLeft.first == leftToRight.second)
    #expect(rightToLeft.second == leftToRight.first)
  }

  @Test func tabletopKeepsPreviewAboveInstructionsInBothReadingDirections() {
    let size = CGSize(width: 700, height: 900)
    let division = CGRect(x: 0, y: 420, width: 700, height: 20)
    for rightToLeft in [false, true] {
      let regions = AdaptivePairLayout(division: division, wide: true, rightToLeft: rightToLeft)
        .regions(in: size, explanationHeight: 300)
      #expect(regions.first.maxY == division.minY)
      #expect(regions.second.minY == division.maxY)
      #expect(regions.second.maxY == size.height)
    }
  }

  @Test func compactReservesScrollableInstructionSpaceForOversizedText() {
    let regions = AdaptivePairLayout(division: nil, wide: false)
      .regions(in: CGSize(width: 320, height: 500), explanationHeight: 900)
    #expect(regions.first == CGRect(x: 0, y: 0, width: 320, height: 200))
    #expect(regions.second == CGRect(x: 0, y: 200, width: 320, height: 300))
  }

  @Test func compactEmptyInstructionsGivePreviewAllAvailableHeight() {
    let regions = AdaptivePairLayout(division: nil, wide: false)
      .regions(in: CGSize(width: 390, height: 700), explanationHeight: 0)
    #expect(regions.first.height == 700)
    #expect(regions.second.height == 0)
  }

  @Test func offscreenDivisionFallsBackToWidePair() {
    let regions = AdaptivePairLayout(
      division: CGRect(x: 1200, y: 0, width: 20, height: 700), wide: true
    )
    .regions(in: CGSize(width: 1000, height: 700), explanationHeight: 300)
    #expect(regions.first.width == 500)
    #expect(regions.second.minX == 500)
  }
  @Test func compactStageRemainsStableWhenInstructionHeightChanges() {
    let layout = AdaptivePairLayout(division: nil, wide: false, previewFraction: 0.58)
    let size = CGSize(width: 390, height: 700)
    let short = layout.regions(in: size, explanationHeight: 120)
    let long = layout.regions(in: size, explanationHeight: 420)
    #expect(short.first == long.first)
    #expect(short.second == long.second)
    #expect(abs(short.first.height - 406) < 0.001)
    #expect(short.second.maxY == size.height)
  }

  @Test func fixedStagePreservesPhysicalDivision() {
    let division = CGRect(x: 320, y: 0, width: 20, height: 390)
    let layout = AdaptivePairLayout(division: division, wide: true, previewFraction: 0.58)
    let regions = layout.regions(in: CGSize(width: 678, height: 390), explanationHeight: 420)
    #expect(regions.first.maxX == division.minX)
    #expect(regions.second.minX == division.maxX)
    #expect(regions.first.height == 390)
  }

}
