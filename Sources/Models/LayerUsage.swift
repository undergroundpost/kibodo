import Foundation
import SwiftData

/// Accumulated time spent on one layer of one keyboard. One row per
/// (keyboard, layerIndex) — at most ~8 rows per keyboard total, independent
/// of how many transitions the user makes.
@Model
final class LayerUsage {
    var id: UUID
    var layerIndex: Int
    var totalSeconds: Double = 0
    var keyboard: Keyboard?

    init(
        id: UUID = UUID(),
        layerIndex: Int,
        totalSeconds: Double = 0,
        keyboard: Keyboard? = nil
    ) {
        self.id = id
        self.layerIndex = layerIndex
        self.totalSeconds = totalSeconds
        self.keyboard = keyboard
    }
}
