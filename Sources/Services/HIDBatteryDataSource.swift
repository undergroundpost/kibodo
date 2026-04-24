import Foundation
import IOKit
import IOKit.hid

/// Reads per-peripheral battery levels, metadata, and layer state from any ZMK
/// dongle running the `zmk-battery-monitor-firmware` module. Matches USB HID
/// devices with vendor-defined usage page 0xFF00 / usage 0x01.
final class HIDBatteryDataSource: BatteryDataSource {
    let source = "hid"

    fileprivate static let usagePage = 0xFF00
    fileprivate static let usage = 0x01
    fileprivate static let batteryReportID: UInt8 = 0x01
    fileprivate static let metadataReportID: UInt8 = 0x02
    fileprivate static let layerReportID: UInt8 = 0x03
    fileprivate static let layerNameReportID: UInt8 = 0x04
    fileprivate static let percentUnknown: UInt8 = 0xFF
    fileprivate static let metadataReportSize = 32
    fileprivate static let metadataLabelOffset = 1
    fileprivate static let layerNameReportSize = 32
    fileprivate static let layerNameOffset = 1

    func events() -> AsyncStream<KeyboardEvent> {
        AsyncStream { continuation in
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

            let matching: [String: Any] = [
                kIOHIDDeviceUsagePageKey: Self.usagePage,
                kIOHIDDeviceUsageKey: Self.usage,
            ]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

            let context = HIDContext(continuation: continuation)
            let unmanaged = Unmanaged.passRetained(context)
            let opaque = unmanaged.toOpaque()

            IOHIDManagerRegisterInputReportCallback(manager, { ctx, _, sender, _, reportID, reportBuf, reportLen in
                guard let ctx, let sender else { return }
                let ctxRef = Unmanaged<HIDContext>.fromOpaque(ctx).takeUnretainedValue()
                let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
                let identity = HIDContext.extractKeyboardIdentity(from: device)

                let buffer = UnsafeBufferPointer(start: reportBuf, count: reportLen)
                let bytes = Array(buffer)

                switch UInt8(reportID) {
                case HIDBatteryDataSource.batteryReportID:
                    ctxRef.handleBatteryReport(bytes: bytes, identity: identity)
                case HIDBatteryDataSource.metadataReportID:
                    ctxRef.handleMetadataReport(bytes: bytes, identity: identity)
                case HIDBatteryDataSource.layerReportID:
                    ctxRef.handleLayerReport(bytes: bytes, identity: identity)
                case HIDBatteryDataSource.layerNameReportID:
                    ctxRef.handleLayerNameReport(bytes: bytes, identity: identity)
                default:
                    return
                }
            }, opaque)

            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if openResult != kIOReturnSuccess {
                continuation.finish()
                unmanaged.release()
                return
            }

            continuation.onTermination = { _ in
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                unmanaged.release()
            }
        }
    }
}

/// Identity of the dongle (keyboard) extracted from IOKit device properties.
private struct KeyboardIdentity {
    let externalID: String
    let productName: String
    let vendorID: Int?
    let productID: Int?
}

/// Per-session parsing state. Emits a KeyboardEvent whenever a report arrives.
private final class HIDContext {
    let continuation: AsyncStream<KeyboardEvent>.Continuation

    /// Labels keyed by (keyboardExternalID, slot).
    private var labels: [String: String] = [:]
    /// Last-known percent keyed by (keyboardExternalID, slot).
    private var lastPercent: [String: Int] = [:]

    init(continuation: AsyncStream<KeyboardEvent>.Continuation) {
        self.continuation = continuation
    }

    static func extractKeyboardIdentity(from device: IOHIDDevice) -> KeyboardIdentity {
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int

        let externalID: String
        if let serial, !serial.isEmpty {
            externalID = serial
        } else if let vendor, let productID {
            // Fallback when a device omits its serial: VID/PID.
            externalID = String(format: "vid%04x-pid%04x", vendor, productID)
        } else {
            externalID = "unknown-keyboard"
        }

        return KeyboardIdentity(
            externalID: externalID,
            productName: product ?? "ZMK Keyboard",
            vendorID: vendor,
            productID: productID
        )
    }

    func handleBatteryReport(bytes: [UInt8], identity: KeyboardIdentity) {
        let payload = Array(bytes.dropFirst())
        guard !payload.isEmpty else { return }
        let now = Date()
        for (index, byte) in payload.enumerated() {
            guard byte != HIDBatteryDataSource.percentUnknown else { continue }
            let percent = min(100, Int(byte))
            lastPercent[cacheKey(identity: identity, slot: index)] = percent
            emitBattery(identity: identity, slot: index, percent: percent, at: now)
        }
    }

    func handleMetadataReport(bytes: [UInt8], identity: KeyboardIdentity) {
        let payload = Array(bytes.dropFirst())
        guard payload.count >= HIDBatteryDataSource.metadataReportSize else { return }

        let slot = Int(payload[0])

        let labelStart = HIDBatteryDataSource.metadataLabelOffset
        let labelEnd = HIDBatteryDataSource.metadataReportSize
        let labelBytes = Array(payload[labelStart..<labelEnd])
        let nullIndex = labelBytes.firstIndex(of: 0) ?? labelBytes.count
        let label = String(bytes: labelBytes.prefix(nullIndex), encoding: .utf8) ?? ""

        let key = cacheKey(identity: identity, slot: slot)
        if !label.isEmpty {
            labels[key] = label
        }

        if let percent = lastPercent[key] {
            emitBattery(identity: identity, slot: slot, percent: percent, at: Date())
        }
    }

    func handleLayerReport(bytes: [UInt8], identity: KeyboardIdentity) {
        let payload = Array(bytes.dropFirst())
        guard let first = payload.first else { return }
        continuation.yield(.activeLayer(
            keyboardExternalID: identity.externalID,
            index: Int(first),
            timestamp: Date()
        ))
    }

    func handleLayerNameReport(bytes: [UInt8], identity: KeyboardIdentity) {
        let payload = Array(bytes.dropFirst())
        guard payload.count >= HIDBatteryDataSource.layerNameReportSize else { return }

        let layer = Int(payload[0])
        let labelStart = HIDBatteryDataSource.layerNameOffset
        let labelEnd = HIDBatteryDataSource.layerNameReportSize
        let labelBytes = Array(payload[labelStart..<labelEnd])
        let nullIndex = labelBytes.firstIndex(of: 0) ?? labelBytes.count
        let label = String(bytes: labelBytes.prefix(nullIndex), encoding: .utf8) ?? ""

        continuation.yield(.layerName(
            keyboardExternalID: identity.externalID,
            index: layer,
            label: label
        ))
    }

    private func emitBattery(identity: KeyboardIdentity, slot: Int, percent: Int, at timestamp: Date) {
        continuation.yield(.battery(BatteryReading(
            keyboardExternalID: identity.externalID,
            keyboardName: identity.productName,
            keyboardVendorID: identity.vendorID,
            keyboardProductID: identity.productID,
            slot: slot,
            deviceLabel: labels[cacheKey(identity: identity, slot: slot)] ?? "Peripheral \(slot)",
            percent: percent,
            isCharging: false,
            timestamp: timestamp,
            source: "hid"
        )))
    }

    private func cacheKey(identity: KeyboardIdentity, slot: Int) -> String {
        "\(identity.externalID)#\(slot)"
    }
}
