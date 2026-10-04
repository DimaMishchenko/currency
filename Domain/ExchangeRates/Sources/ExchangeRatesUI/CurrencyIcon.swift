import ExchangeRates
import SwiftUI

#if os(iOS)
  import CoreText
  import ImageIO
  import Synchronization
  import UIKit
  import UniformTypeIdentifiers
#endif

/// A bundled crypto badge, original metal badge, or native fiat flag emoji.
/// DOGE: https://github.com/spothq/cryptocurrency-icons (CC0; CryptocurrencyIcons-LICENSE.txt).
/// Other crypto artwork: https://github.com/0xa3k5/web3icons (MIT; see Web3Icons-LICENSE.txt).
public struct CurrencyIcon: View {
  #if os(iOS)
    /// PNG artwork at most 72 pixels wide or tall for system-owned pickers and widgets.
    nonisolated public static func pickerImageData(_ code: String) -> Data? {
      imageData(code, side: 72)
    }

    /// PNG artwork at most 216 pixels wide or tall for system search thumbnails.
    nonisolated public static func thumbnailImageData(_ code: String) -> Data? {
      imageData(code, side: 216)
    }

    nonisolated private static let imageCache: Mutex<NSCache<NSString, NSData>> = {
      let cache = NSCache<NSString, NSData>()
      cache.totalCostLimit = 2 * 1024 * 1024
      cache.countLimit = 256
      return Mutex(cache)
    }()

    nonisolated private static func imageData(_ code: String, side: Int) -> Data? {
      guard let currency = CurrencyCode(rawValue: code) else { return nil }
      return imageCache.withLock { cache in
        let key = "\(code):\(side)" as NSString
        if let data = cache.object(forKey: key) { return data as Data }
        let data = autoreleasepool {
          if currency.isCryptocurrency {
            return assetImage("Crypto" + code, side: side)
          } else if currency.isMetal {
            return assetImage("Metal" + code, side: side)
          } else {
            return flagImage(CurrencyDisplay.flag(code), side: side)
          }
        }
        if let data { cache.setObject(data as NSData, forKey: key, cost: data.count) }
        return data
      }
    }

    nonisolated private static func assetImage(_ name: String, side: Int) -> Data? {
      guard
        let data = UIImage(named: name, in: Bundle.module, compatibleWith: nil)?.pngData(),
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceCreateThumbnailWithTransform: true
          ] as CFDictionary)
      else { return nil }
      return pngData(image)
    }

    nonisolated private static func flagImage(_ flag: String, side: Int) -> Data? {
      guard
        let context = CGContext(
          data: nil, width: side, height: side, bitsPerComponent: 8,
          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      let font = CTFontCreateWithName("AppleColorEmoji" as CFString, CGFloat(side) * 13 / 18, nil)
      let string = NSAttributedString(
        string: flag,
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
      let line = CTLineCreateWithAttributedString(string)
      let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
      context.textPosition = CGPoint(
        x: (CGFloat(side) - bounds.width) / 2 - bounds.minX,
        y: (CGFloat(side) - bounds.height) / 2 - bounds.minY)
      CTLineDraw(line, context)
      guard let image = context.makeImage() else { return nil }
      return pngData(image)
    }

    nonisolated private static func pngData(_ image: CGImage) -> Data? {
      let data = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          data, UTType.png.identifier as CFString, 1, nil)
      else { return nil }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { return nil }
      return data as Data
    }

  #endif

  private let code: String
  private let size: CGFloat

  /// Creates a currency badge with the requested point size.
  public init(_ code: String, size: CGFloat = 22) {
    self.code = code
    self.size = size
  }

  /// Decorative currency artwork; the owning control supplies its accessible name.
  public var body: some View {
    Group {
      if CurrencyCatalog.crypto.contains(code) {
        Image("Crypto" + code, bundle: Bundle.module)
          .resizable()
          .scaledToFit()
          .frame(width: size, height: size)
          .clipShape(Circle())
      } else if let metal = Metal(rawValue: code) {
        MetalBadge(metal: metal, size: size)
      } else {
        Text(CurrencyDisplay.flag(code)).font(.system(size: size))
      }
    }
    .accessibilityHidden(true)
  }
}
