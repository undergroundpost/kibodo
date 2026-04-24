import Foundation
import CoreGraphics

/// A physical-layout description for rendering a keyboard (or half of one) as
/// an icon. Coordinates are in key units (1.0 = one standard key width),
/// matching ZMK's `physical_layout` convention.
struct KeyboardPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let keys: [PresetKey]

    /// Bounding box of the laid-out keys, in key units.
    var bounds: CGRect {
        guard !keys.isEmpty else { return .zero }
        let minX = keys.map(\.x).min() ?? 0
        let minY = keys.map(\.y).min() ?? 0
        let maxX = keys.map { $0.x + $0.w }.max() ?? 1
        let maxY = keys.map { $0.y + $0.h }.max() ?? 1
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct PresetKey: Hashable {
    var x: Double
    var y: Double
    var w: Double = 1
    var h: Double = 1
    /// Rotation in degrees, around the key's top-left corner. 0 for most keys.
    var r: Double = 0
}
