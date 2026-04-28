import Foundation

struct BatteryReading: Sendable, Equatable {
    let keyboardExternalID: String
    let keyboardName: String
    let keyboardVendorID: Int?
    let keyboardProductID: Int?
    let slot: Int
    /// nil when the data source doesn't yet know a per-peripheral label
    /// (e.g. firmware hasn't yet read the BLE side label). The manager
    /// supplies a default at device-creation time and otherwise leaves
    /// the existing name in place — never an opportunity to clobber a
    /// known-good name with a placeholder.
    let deviceLabel: String?
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
