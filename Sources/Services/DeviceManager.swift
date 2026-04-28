import Foundation
@preconcurrency import SwiftData
import SwiftUI
@preconcurrency import AppKit

@MainActor
final class DeviceManager {
    private let modelContext: ModelContext
    private var consumptionTasks: [String: Task<Void, Never>] = [:]
    private var suppressedIDs: [String: String] = [:]
    private var lastSystemWake: Date?
    /// Held outside actor isolation so `deinit` (which is nonisolated) can
    /// remove the observer without crossing actor boundaries. Only mutated on
    /// the main actor at init time, so the unsafe override is sound.
    nonisolated(unsafe) private var sleepWakeObserver: NSObjectProtocol?

    private static let heartbeatInterval: TimeInterval = 30 * 60
    /// Drops larger than this in a single reading are rejected as ADC glitches.
    /// Real ZMK peripherals don't lose 40% battery between heartbeats.
    private static let maxPlausibleDropPerReading: Int = 40
    /// If a reading arrives within this window after system wake, any preceding
    /// gap is treated as system-sleep rather than a disconnect.
    private static let systemWakeGraceSeconds: TimeInterval = 60
    /// Don't write `lastSeen` on @Model objects more often than this. Every
    /// write fires SwiftData change notifications that cascade into every
    /// `@Query`-observing view; coalescing tick-updates cuts background CPU
    /// dramatically while keeping disconnect-threshold detection accurate.
    private static let lastSeenMinInterval: TimeInterval = 15

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        sleepWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastSystemWake = Date()
            }
        }

        cleanupObviousOutliers()
        finalizePendingLayerCredits()
    }

    deinit {
        if let observer = sleepWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func add(_ dataSource: BatteryDataSource) {
        let sourceID = dataSource.source
        guard consumptionTasks[sourceID] == nil else { return }

        let task = Task { [weak self] in
            for await event in dataSource.events() {
                guard !Task.isCancelled else { break }
                switch event {
                case .battery(let reading):
                    self?.handle(reading)
                case .activeLayer(let kid, let index, let timestamp):
                    self?.handleActiveLayer(keyboardExternalID: kid, index: index, timestamp: timestamp)
                case .layerName(let kid, let index, let label):
                    self?.handleLayerName(keyboardExternalID: kid, index: index, label: label)
                }
            }
        }
        consumptionTasks[sourceID] = task
    }

    /// Stop consuming from a source. Preserves all data so a reconnect picks
    /// up where things left off. Clears delete-suppressions for that source.
    func disconnect(sourceID: String) {
        consumptionTasks[sourceID]?.cancel()
        consumptionTasks.removeValue(forKey: sourceID)
        suppressedIDs = suppressedIDs.filter { $0.value != sourceID }
    }

    /// Disconnect AND permanently delete every keyboard/device that came from
    /// the given source. Intended for destructive user actions (demo toggle off).
    func purgeAll(sourceID: String) {
        disconnect(sourceID: sourceID)

        let descriptor = FetchDescriptor<Device>(
            predicate: #Predicate { $0.source == sourceID }
        )
        guard let devices = try? modelContext.fetch(descriptor) else { return }

        var keyboards = Set<PersistentIdentifier>()
        for device in devices {
            if let kb = device.keyboard {
                keyboards.insert(kb.persistentModelID)
            }
            modelContext.delete(device)
        }

        for kbID in keyboards {
            if let kb = modelContext.model(for: kbID) as? Keyboard, kb.peripherals.isEmpty {
                modelContext.delete(kb)
            }
        }

        try? modelContext.save()
    }

    /// Permanently delete a single peripheral. Its keyboard is preserved even
    /// if it becomes empty (user may still want the keyboard entry visible).
    func delete(_ device: Device) {
        suppressedIDs[device.externalID] = device.source
        modelContext.delete(device)
        try? modelContext.save()
    }

    /// Permanently delete a keyboard and all its peripherals + history.
    func delete(_ keyboard: Keyboard) {
        for peripheral in keyboard.peripherals {
            suppressedIDs[peripheral.externalID] = peripheral.source
        }
        modelContext.delete(keyboard)
        try? modelContext.save()
    }

    private func handle(_ reading: BatteryReading) {
        let deviceExternalID = Self.deviceExternalID(for: reading)
        guard suppressedIDs[deviceExternalID] == nil else { return }

        let keyboard = findOrCreateKeyboard(reading: reading)
        updateKeyboardPresence(keyboard, at: reading.timestamp)

        let device = findOrCreateDevice(
            reading: reading,
            deviceExternalID: deviceExternalID,
            keyboard: keyboard
        )

        let previousPercent = latestSample(for: device)?.percent

        // ADC glitch guard. ZMK peripherals occasionally report an anomalous
        // value right after BLE re-establishes (e.g. post-sleep). If the drop
        // is implausibly large, accept that a reading arrived (bump lastSeen)
        // but don't persist the bad sample.
        if let prev = previousPercent, prev - reading.percent > Self.maxPlausibleDropPerReading {
            bumpLastSeen(for: device, to: reading.timestamp)
            return
        }

        let percentChanged = previousPercent != reading.percent
        var mutated = false

        if bumpLastSeen(for: device, to: reading.timestamp) { mutated = true }
        // Only update name when the data source actually knows one. nil means
        // "the firmware hasn't told me the label yet" — leave the existing
        // name in place (it's either the previously-known good name from the
        // DB, or the slot-based default created in findOrCreateDevice).
        if let label = reading.deviceLabel, device.name != label {
            device.name = label
            mutated = true
        }
        if percentChanged {
            device.lastValueChange = reading.timestamp
            mutated = true
        }

        if shouldPersist(reading: reading, for: device, percentChanged: percentChanged) {
            let sample = BatterySample(
                timestamp: reading.timestamp,
                percent: reading.percent,
                isCharging: reading.isCharging,
                source: reading.source,
                device: device
            )
            modelContext.insert(sample)
            mutated = true
        }

        if mutated {
            try? modelContext.save()
        }

        // Threshold notifications depend on the latest sample, not whether we
        // persisted this tick — always check.
        NotificationManager.shared.checkThresholds(for: device)
    }

    /// Updates `device.lastSeen` only if enough time has passed since the
    /// previous write. Returns true if the write actually happened — callers
    /// use this to decide whether a `save()` is warranted.
    @discardableResult
    private func bumpLastSeen(for device: Device, to timestamp: Date) -> Bool {
        guard timestamp.timeIntervalSince(device.lastSeen) >= Self.lastSeenMinInterval else {
            return false
        }
        device.lastSeen = timestamp
        return true
    }

    private func handleActiveLayer(keyboardExternalID: String, index: Int, timestamp: Date) {
        guard let keyboard = fetchKeyboard(externalID: keyboardExternalID) else { return }

        // Bootstrap on first event after startup: record state without
        // crediting (we don't know what happened while the app was quit).
        guard let startedAt = keyboard.lastLayerTransitionAt else {
            keyboard.activeLayerIndex = index
            keyboard.lastLayerTransitionAt = timestamp
            try? modelContext.save()
            return
        }

        guard keyboard.activeLayerIndex != index else { return }

        if let outgoing = keyboard.activeLayerIndex {
            let elapsed = timestamp.timeIntervalSince(startedAt)
            if elapsed > 0 {
                let row = findOrCreateLayerUsage(keyboard: keyboard, layerIndex: outgoing)
                row.totalSeconds += elapsed
            }
        }

        keyboard.activeLayerIndex = index
        keyboard.lastLayerTransitionAt = timestamp
        try? modelContext.save()
    }

    private func findOrCreateLayerUsage(keyboard: Keyboard, layerIndex: Int) -> LayerUsage {
        if let existing = keyboard.layerUsage.first(where: { $0.layerIndex == layerIndex }) {
            return existing
        }
        let row = LayerUsage(layerIndex: layerIndex, keyboard: keyboard)
        modelContext.insert(row)
        return row
    }

    private func handleLayerName(keyboardExternalID: String, index: Int, label: String) {
        guard let keyboard = fetchKeyboard(externalID: keyboardExternalID) else { return }
        guard index >= 0 else { return }
        var labels = keyboard.layerLabels
        if index >= labels.count {
            labels.append(contentsOf: repeatElement("", count: index - labels.count + 1))
        }
        guard labels[index] != label else { return }
        labels[index] = label
        keyboard.layerLabels = labels
        try? modelContext.save()
    }

    /// On app startup, credit any in-flight layer time up to the keyboard's
    /// lastSeen (no events arrive while the app is down, so we can't know
    /// what happened after that). Clear the transition timestamp so the next
    /// event bootstraps cleanly instead of crediting dead time.
    private func finalizePendingLayerCredits() {
        let descriptor = FetchDescriptor<Keyboard>()
        guard let keyboards = try? modelContext.fetch(descriptor), !keyboards.isEmpty else { return }
        for keyboard in keyboards {
            guard let startedAt = keyboard.lastLayerTransitionAt,
                  let idx = keyboard.activeLayerIndex else {
                keyboard.lastLayerTransitionAt = nil
                continue
            }
            let elapsed = keyboard.lastSeen.timeIntervalSince(startedAt)
            if elapsed > 0 {
                let row = findOrCreateLayerUsage(keyboard: keyboard, layerIndex: idx)
                row.totalSeconds += elapsed
            }
            keyboard.lastLayerTransitionAt = nil
        }
        try? modelContext.save()
    }

    private func fetchKeyboard(externalID: String) -> Keyboard? {
        let descriptor = FetchDescriptor<Keyboard>(
            predicate: #Predicate { $0.externalID == externalID }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func findOrCreateKeyboard(reading: BatteryReading) -> Keyboard {
        let kid = reading.keyboardExternalID
        let descriptor = FetchDescriptor<Keyboard>(
            predicate: #Predicate { $0.externalID == kid }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let keyboard = Keyboard(
            externalID: reading.keyboardExternalID,
            name: reading.keyboardName,
            vendorID: reading.keyboardVendorID,
            productID: reading.keyboardProductID,
            usbProductString: reading.keyboardName,
            firstSeen: reading.timestamp,
            lastSeen: reading.timestamp,
            totalConnectedSeconds: 0,
            currentSessionStart: reading.timestamp
        )
        modelContext.insert(keyboard)
        return keyboard
    }

    /// Updates `keyboard.lastSeen`, `totalConnectedSeconds`, and
    /// `currentSessionStart`. A gap larger than the disconnect threshold
    /// normally resets the session — unless the system just woke up, in which
    /// case the gap is attributed to system sleep and the session continues.
    private func updateKeyboardPresence(_ keyboard: Keyboard, at now: Date) {
        let thresholdSeconds = (UserDefaults.standard.object(forKey: "disconnectThresholdSeconds") as? Double) ?? 120
        let delta = now.timeIntervalSince(keyboard.lastSeen)

        let recentlyWoken = lastSystemWake
            .map { now.timeIntervalSince($0) < Self.systemWakeGraceSeconds }
            ?? false

        let shouldStartNewSession = keyboard.currentSessionStart == nil
            || (delta > thresholdSeconds && !recentlyWoken)

        if shouldStartNewSession {
            keyboard.currentSessionStart = now
            keyboard.lastSeen = now
            return
        }

        // Throttle lastSeen writes so high-frequency readings don't fire a
        // change notification on every tick. totalConnectedSeconds still
        // advances by the actual delta when we do write.
        if delta >= Self.lastSeenMinInterval {
            if delta > 0 {
                keyboard.totalConnectedSeconds += delta
            }
            keyboard.lastSeen = now
        }
    }

    /// Removes runs of spurious low-battery samples left over from firmware
    /// glitches (e.g. the peripheral notifying `0` during sleep). A run is a
    /// contiguous stretch of samples with percent < 5 on a single device.
    /// The run is deleted if:
    ///   - the sample immediately before is ≥ 30%, AND
    ///   - the sample immediately after is ≥ 30%, AND
    ///   - the run's total duration is < 24 hours
    ///
    /// That last check prevents nuking a legitimately-drained battery that
    /// stayed dead for days before being charged.
    private func cleanupObviousOutliers() {
        let deviceDescriptor = FetchDescriptor<Device>()
        guard let devices = try? modelContext.fetch(deviceDescriptor) else { return }

        let lowThreshold = 5
        let highThreshold = 30
        let maxRunSeconds: TimeInterval = 24 * 3600

        var toDelete: [BatterySample] = []

        for device in devices {
            let sorted = device.samples.sorted(by: { $0.timestamp < $1.timestamp })

            var i = 0
            while i < sorted.count {
                guard sorted[i].percent < lowThreshold else {
                    i += 1
                    continue
                }
                let runStart = i
                var runEnd = i
                while runEnd + 1 < sorted.count && sorted[runEnd + 1].percent < lowThreshold {
                    runEnd += 1
                }

                let beforeIsHigh = runStart > 0 && sorted[runStart - 1].percent >= highThreshold
                let afterIsHigh = runEnd < sorted.count - 1 && sorted[runEnd + 1].percent >= highThreshold
                let runDuration = sorted[runEnd].timestamp.timeIntervalSince(sorted[runStart].timestamp)

                if beforeIsHigh, afterIsHigh, runDuration < maxRunSeconds {
                    for j in runStart...runEnd {
                        toDelete.append(sorted[j])
                    }
                }
                i = runEnd + 1
            }
        }

        guard !toDelete.isEmpty else { return }
        for sample in toDelete {
            modelContext.delete(sample)
        }
        try? modelContext.save()
    }

    private func findOrCreateDevice(
        reading: BatteryReading,
        deviceExternalID: String,
        keyboard: Keyboard
    ) -> Device {
        let descriptor = FetchDescriptor<Device>(
            predicate: #Predicate { $0.externalID == deviceExternalID }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let device = Device(
            externalID: deviceExternalID,
            slot: reading.slot,
            // Default to a slot-based name when the firmware hasn't yet
            // advertised a side label. The next reading carrying a real
            // label will overwrite this (a real label is never "Peripheral N",
            // so the equality check in handle() will see a difference).
            name: reading.deviceLabel ?? "Peripheral \(reading.slot)",
            source: reading.source,
            firstSeen: reading.timestamp,
            lastSeen: reading.timestamp,
            lastValueChange: reading.timestamp
        )
        device.keyboard = keyboard
        modelContext.insert(device)
        return device
    }

    private func latestSample(for device: Device) -> BatterySample? {
        device.samples.max(by: { $0.timestamp < $1.timestamp })
    }

    private func shouldPersist(reading: BatteryReading, for device: Device, percentChanged: Bool) -> Bool {
        let latest = latestSample(for: device)
        guard let latest else { return true }
        if percentChanged { return true }
        if latest.isCharging != reading.isCharging { return true }
        if reading.timestamp.timeIntervalSince(latest.timestamp) >= Self.heartbeatInterval { return true }
        return false
    }

    private static func deviceExternalID(for reading: BatteryReading) -> String {
        "\(reading.keyboardExternalID)#peripheral-\(reading.slot)"
    }
}

private struct DeviceManagerKey: EnvironmentKey {
    static let defaultValue: DeviceManager? = nil
}

extension EnvironmentValues {
    var deviceManager: DeviceManager? {
        get { self[DeviceManagerKey.self] }
        set { self[DeviceManagerKey.self] = newValue }
    }
}
