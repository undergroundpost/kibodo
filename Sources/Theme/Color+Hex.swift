import SwiftUI
import AppKit

extension Color {
    /// Convenience initializer from `#rrggbb` / `rrggbb`. Silently uses black
    /// for malformed input rather than crashing.
    init(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// `#RRGGBB` representation, resolved through sRGB. Falls back to black if
    /// the color can't be bridged (e.g. a non-concrete dynamic color).
    var hexString: String {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
