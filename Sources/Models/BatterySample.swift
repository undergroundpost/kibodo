import Foundation
import SwiftData

@Model
final class BatterySample {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var percent: Int
    var isCharging: Bool
    var source: String
    var device: Device?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        percent: Int,
        isCharging: Bool = false,
        source: String,
        device: Device? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.percent = percent
        self.isCharging = isCharging
        self.source = source
        self.device = device
    }
}
