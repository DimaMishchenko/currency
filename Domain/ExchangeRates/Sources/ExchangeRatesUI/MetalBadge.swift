import SwiftUI

/// Original app artwork. A static satin finish keeps small badges legible in widgets.
struct MetalBadge: View {
  let metal: Metal
  let size: CGFloat

  var body: some View {
    Text(verbatim: metal.symbol)
      .font(.system(size: size * 0.43, weight: .semibold, design: .rounded))
      .foregroundStyle(metal.ink)
      .frame(width: size, height: size)
      .background {
        Circle()
          .fill(metal.color)
          .overlay {
            Circle()
              .fill(
                LinearGradient(
                  stops: [
                    .init(color: .white.opacity(0.08), location: 0),
                    .init(color: .white.opacity(0.48), location: 0.30),
                    .init(color: .white.opacity(0.12), location: 0.48),
                    .init(color: .clear, location: 0.62),
                    .init(color: .black.opacity(0.12), location: 1)
                  ], startPoint: .topLeading, endPoint: .bottomTrailing))
          }
          .overlay {
            Circle()
              .strokeBorder(
                LinearGradient(
                  colors: [.white.opacity(0.65), .black.opacity(0.14)],
                  startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.5)
          }
      }
  }
}

enum Metal: String {
  case gold = "XAU", silver = "XAG", platinum = "XPT", palladium = "XPD"

  var symbol: String {
    switch self {
    case .gold: "Au"
    case .silver: "Ag"
    case .platinum: "Pt"
    case .palladium: "Pd"
    }
  }

  var color: Color {
    switch self {
    case .gold: Color(red: 0.855, green: 0.741, blue: 0.439)
    case .silver: Color(red: 0.831, green: 0.847, blue: 0.867)
    case .platinum: Color(red: 0.761, green: 0.835, blue: 0.824)
    case .palladium: Color(red: 0.776, green: 0.761, blue: 0.851)
    }
  }

  var ink: Color {
    switch self {
    case .gold: Color(red: 0.286, green: 0.216, blue: 0.063)
    case .silver: Color(red: 0.224, green: 0.255, blue: 0.294)
    case .platinum: Color(red: 0.188, green: 0.298, blue: 0.282)
    case .palladium: Color(red: 0.286, green: 0.255, blue: 0.369)
    }
  }
}
