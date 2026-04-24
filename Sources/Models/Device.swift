import Foundation
import SwiftData

@Model
final class Device {
    @Attribute(.unique) var externalID: String
    var id: UUID
    var slot: Int
    /// Firmware-reported label (e.g. "Corne Left"). Gets overwritten on every
    /// reading so it stays in sync with whatever the dongle is advertising.
    var name: String
    /// User-chosen override. When non-nil, `displayName` and UI use this
    /// instead of `name`. Survives firmware label changes.
    var userName: String?
    var source: String
    var firstSeen: Date
    var lastSeen: Date
    var lastValueChange: Date

    var keyboard: Keyboard?

    @Relationship(deleteRule: .cascade, inverse: \BatterySample.device)
    var samples: [BatterySample] = []

    var displayName: String { userName ?? name }

    init(
        externalID: String,
        id: UUID = UUID(),
        slot: Int,
        name: String,
        userName: String? = nil,
        source: String,
        firstSeen: Date = .now,
        lastSeen: Date = .now,
        lastValueChange: Date = .now
    ) {
        self.externalID = externalID
        self.id = id
        self.slot = slot
        self.name = name
        self.userName = userName
        self.source = source
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastValueChange = lastValueChange
    }
}
