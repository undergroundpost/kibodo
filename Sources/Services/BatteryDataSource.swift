import Foundation

struct BatteryReading: Sendable, Equatable {
    let keyboardExternalID: String
    let keyboardName: String
    let keyboardVendorID: Int?
    let keyboardProductID: Int?
    let slot: Int
    let deviceLabel: String
    let percent: Int
    let isCharging: Bool
    let timestamp: Date
    let source: String
}

/// A per-keyboard event from a data source. Layer variants apply to the whole
/// keyboard; battery applies to one peripheral. Layer index uses the same
/// resolution as ZMK's on-dongle display (highest active).
enum KeyboardEvent: Sendable {
    case battery(BatteryReading)
    case activeLayer(keyboardExternalID: String, index: Int, timestamp: Date)
    case layerName(keyboardExternalID: String, index: Int, label: String)
}

protocol BatteryDataSource: Sendable {
    var source: String { get }
    func events() -> AsyncStream<KeyboardEvent>
}
