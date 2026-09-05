import ExchangeRates
import SwiftUI

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
    return images
  }()

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
