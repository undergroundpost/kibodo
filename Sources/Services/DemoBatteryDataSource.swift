import Foundation

final class DemoBatteryDataSource: BatteryDataSource {
    let source = "demo"

    private static let demoKeyboardExternalID = "demo-keyboard"
    private static let demoKeyboardName = "Demo Keyboard"

    private struct DemoPeripheral: Sendable {
        let slot: Int
        let label: String
        var percent: Double
        var isCharging: Bool
        let dischargeRate: Double
        let chargeRate: Double
    }

    private static let demoLayerLabels = ["BASE", "LOWER", "RAISE", "ADJUST"]

    func events() -> AsyncStream<KeyboardEvent> {
        AsyncStream { continuation in
            let task = Task {
                var peripherals = [
                    DemoPeripheral(
                        slot: 0,
                        label: "Demo Left",
                        percent: 87,
                        isCharging: false,
                        dischargeRate: 0.4,
                        chargeRate: 3.0
                    ),
                    DemoPeripheral(
                        slot: 1,
                        label: "Demo Right",
                        percent: 64,
                        isCharging: false,
                        dischargeRate: 0.12,
                        chargeRate: 3.0
                    ),
                ]

                for (idx, label) in Self.demoLayerLabels.enumerated() {
                    continuation.yield(.layerName(
                        keyboardExternalID: Self.demoKeyboardExternalID,
                        index: idx,
                        label: label
                    ))
                }

                var layerTick = 0
                while !Task.isCancelled {
                    let now = Date()
                    for peripheral in peripherals {
                        continuation.yield(.battery(BatteryReading(
                            keyboardExternalID: Self.demoKeyboardExternalID,
                            keyboardName: Self.demoKeyboardName,
                            keyboardVendorID: nil,
                            keyboardProductID: nil,
                            slot: peripheral.slot,
                            deviceLabel: peripheral.label,
                            percent: Int(peripheral.percent.rounded()),
                            isCharging: peripheral.isCharging,
                            timestamp: now,
                            source: "demo"
                        )))
                    }

                    // Rotate through demo layers so the stat cell has motion.
                    continuation.yield(.activeLayer(
                        keyboardExternalID: Self.demoKeyboardExternalID,
                        index: layerTick % Self.demoLayerLabels.count,
                        timestamp: now
                    ))
                    layerTick += 1

                    // Slow cadence keeps CPU quiet while the demo is on —
                    // a human viewing the UI doesn't need sub-10s updates,
                    // and each emission fires SwiftData + SwiftUI cascades.
                    try? await Task.sleep(for: .seconds(10))

                    for i in peripherals.indices {
                        if peripherals[i].isCharging {
                            peripherals[i].percent = min(100, peripherals[i].percent + peripherals[i].chargeRate)
                            if peripherals[i].percent >= 100 {
                                peripherals[i].isCharging = false
                            }
                        } else {
                            peripherals[i].percent = max(0, peripherals[i].percent - peripherals[i].dischargeRate)
                            if peripherals[i].percent <= 5 {
                                peripherals[i].isCharging = true
                            }
                        }
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
