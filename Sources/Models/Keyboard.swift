import Foundation
import SwiftData

@Model
final class Keyboard {
    @Attribute(.unique) var externalID: String
    var id: UUID
    var name: String
    var vendorID: Int?
    var productID: Int?
    var usbProductString: String?
    var firstSeen: Date
    var lastSeen: Date

    /// Cumulative connected time across all sessions, in seconds.
    var totalConnectedSeconds: Double = 0
    /// Start of the current session. Resets when a reading arrives after a
    /// gap longer than the disconnect threshold.
    var currentSessionStart: Date?

    /// Highest active layer reported by the dongle. nil if we haven't heard
    /// yet (firmware without layer reporting, or first reading pending).
    var activeLayerIndex: Int?
    /// Layer names indexed by layer number. Missing entries are empty strings;
    /// the array grows as labels arrive. Unlabeled layers stay empty and the
    /// UI falls back to "Layer N".
    var layerLabels: [String] = []
    /// Moment the current layer became active. Used to credit elapsed time to
    /// the outgoing layer on the next transition. Cleared on app startup so
    /// the credit bootstraps cleanly after a shutdown/crash.
    var lastLayerTransitionAt: Date?

    /// User-chosen physical-layout id. nil = auto-detect by name;
    /// "none" = explicitly disabled (no icon rendered); otherwise the id of a
    /// layout in `KeyboardPresetCatalog.allLayouts`.
    var layoutID: String?

    @Relationship(deleteRule: .cascade, inverse: \Device.keyboard)
    var peripherals: [Device] = []

    @Relationship(deleteRule: .cascade, inverse: \LayerUsage.keyboard)
    var layerUsage: [LayerUsage] = []

    init(
        externalID: String,
        id: UUID = UUID(),
        name: String,
        vendorID: Int? = nil,
        productID: Int? = nil,
        usbProductString: String? = nil,
        firstSeen: Date = .now,
        lastSeen: Date = .now,
        totalConnectedSeconds: Double = 0,
        currentSessionStart: Date? = nil,
        activeLayerIndex: Int? = nil,
        layerLabels: [String] = []
    ) {
        self.externalID = externalID
        self.id = id
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.usbProductString = usbProductString
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.totalConnectedSeconds = totalConnectedSeconds
        self.currentSessionStart = currentSessionStart
        self.activeLayerIndex = activeLayerIndex
        self.layerLabels = layerLabels
    }

    /// Human-readable name for the active layer, or nil when unknown.
    /// Falls back to "Layer N" when the layer exists but has no label set.
    var activeLayerDisplayName: String? {
        guard let idx = activeLayerIndex else { return nil }
        if idx < layerLabels.count {
            let label = layerLabels[idx]
            if !label.isEmpty { return label }
        }
        return "Layer \(idx)"
    }
}
