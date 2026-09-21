import Foundation
import SwiftUI

/// A device-independent sRGB colour value.
///
/// Google returns every calendar and event colour as a `#rrggbb` string, so the
/// app keeps colours in this value type: it is `Codable` (for the offline
/// cache), `Sendable`, and — unlike `SwiftUI.Color` — its components can be read
/// back, which the tests use to check every published Google colour parses and
/// mixes predictably.
struct RGBColor: Hashable, Sendable, Codable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red.clamped01
        self.green = green.clamped01
        self.blue = blue.clamped01
    }

    /// Parses `#rrggbb`, `rrggbb`, `#rgb` and `#rrggbbaa` (alpha ignored).
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.allSatisfy({ $0.isHexDigit }) else { return nil }

        switch text.count {
        case 3:
            text = text.map { "\($0)\($0)" }.joined()
        case 6:
            break
        case 8:
            text = String(text.prefix(6))
        default:
            return nil
        }

        guard let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    // MARK: - Contrast

    /// WCAG 2.1 relative luminance.
    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG 2.1 contrast ratio, 1.0 (identical) through 21.0 (black on white).
    func contrastRatio(to other: RGBColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func mixed(with other: RGBColor, amount: Double) -> RGBColor {
        let t = amount.clamped01
        return RGBColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    func lightened(by amount: Double) -> RGBColor { mixed(with: .white, amount: amount) }
    func darkened(by amount: Double) -> RGBColor { mixed(with: .black, amount: amount) }

    static let white = RGBColor(red: 1, green: 1, blue: 1)
    static let black = RGBColor(red: 0, green: 0, blue: 0)
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
