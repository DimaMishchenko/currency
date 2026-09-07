import CoreText
import ExchangeRates
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A bundled crypto badge, original metal badge, or native fiat flag emoji.
/// DOGE: https://github.com/spothq/cryptocurrency-icons (CC0; CryptocurrencyIcons-LICENSE.txt).
/// Other crypto artwork: https://github.com/0xa3k5/web3icons (MIT; see Web3Icons-LICENSE.txt).
public struct CurrencyIcon: View {
  /// The same bundled artwork for system-owned currency pickers.
  nonisolated public static func pickerImageData(_ code: String) -> Data? { pickerImages[code] }

  nonisolated private static let pickerImages: [String: Data] = {
    let bundle = Bundle(for: IconBundle.self)
    var images: [String: Data] = [:]
    for code in CurrencyCatalog.crypto {
      images[code] = UIImage(named: "Crypto" + code, in: bundle, compatibleWith: nil)?.pngData()
    }
    for code in ["XAU", "XAG", "XPT", "XPD"] {
      images[code] = UIImage(named: "Metal" + code, in: bundle, compatibleWith: nil)?.pngData()
    }
    for code in CurrencyCatalog.codes where images[code] == nil {
      images[code] = flagImage(CurrencyDisplay.flag(code))
    }
    return images
  }()

  /// Core Text and a private bitmap context avoid UI/main-actor rendering in entity queries.
  nonisolated private static func flagImage(_ flag: String) -> Data? {
    let side = 72
    guard
      let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 52, nil)
    let string = NSAttributedString(
      string: flag,
      attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font
      ])
    let line = CTLineCreateWithAttributedString(string)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.textPosition = CGPoint(
      x: (72 - bounds.width) / 2 - bounds.minX,
      y: (72 - bounds.height) / 2 - bounds.minY)
    CTLineDraw(line, context)
    guard let image = context.makeImage() else { return nil }
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }

  private let code: String
  private let size: CGFloat

  public init(_ code: String, size: CGFloat = 22) {
    self.code = code
    self.size = size
  }

  public var body: some View {
    Group {
      if CurrencyCatalog.crypto.contains(code) {
        Image("Crypto" + code, bundle: Bundle(for: IconBundle.self))
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

private final class IconBundle {}
