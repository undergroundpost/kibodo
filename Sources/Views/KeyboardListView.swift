import SwiftUI
import SwiftData

struct KeyboardListView: View {
    @Query(sort: \Keyboard.name) private var keyboards: [Keyboard]
    @Binding var selectedKeyboard: Keyboard?
    @Environment(\.deviceManager) private var deviceManager
    @AppStorage("disconnectThresholdSeconds") private var disconnectThresholdSeconds: Double = 120

    @State private var keyboardToDelete: Keyboard?
    @State private var keyboardToRename: Keyboard?
    @State private var renameText: String = ""

    @ViewBuilder
    private func keyboardIdentificationItems(for keyboard: Keyboard) -> some View {
        ForEach(KeyboardPresetCatalog.allLayouts) { layout in
            identificationButton(keyboard: keyboard, targetID: layout.id, title: layout.name)
        }
        Divider()
        identificationButton(keyboard: keyboard, targetID: nil, title: "Auto-detect")
        identificationButton(
            keyboard: keyboard,
            targetID: KeyboardLayoutSentinel.none,
            title: "None"
        )
    }

    @ViewBuilder
    private func identificationButton(
        keyboard: Keyboard,
        targetID: String?,
        title: String
    ) -> some View {
        Button {
            keyboard.layoutID = targetID
        } label: {
            if keyboard.layoutID == targetID {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    var body: some View {
        List(selection: $selectedKeyboard) {
            if keyboards.isEmpty {
                EmptySidebarState()
            } else {
                ForEach(keyboards) { keyboard in
                    KeyboardRow(keyboard: keyboard, thresholdSeconds: disconnectThresholdSeconds)
                        .tag(keyboard)
                        .contextMenu {
                            Button {
                                renameText = keyboard.name
                                keyboardToRename = keyboard
                            } label: {
                                Label("Rename…", systemImage: "pencil")
                            }
                            Menu("Keyboard identification") {
                                keyboardIdentificationItems(for: keyboard)
                            }
                            Divider()
                            Button(role: .destructive) {
                                keyboardToDelete = keyboard
                            } label: {
                                Label("Delete Keyboard…", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Keyboards")
        .frame(minWidth: 260)
        .confirmationDialog(
            keyboardToDelete.map { "Delete \($0.name)?" } ?? "Delete Keyboard?",
            isPresented: Binding(
                get: { keyboardToDelete != nil },
                set: { if !$0 { keyboardToDelete = nil } }
            ),
            presenting: keyboardToDelete
        ) { keyboard in
            Button("Delete", role: .destructive) {
                if selectedKeyboard?.externalID == keyboard.externalID {
                    selectedKeyboard = nil
                }
                deviceManager?.delete(keyboard)
                keyboardToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                keyboardToDelete = nil
            }
        } message: { keyboard in
            let sampleCount = keyboard.peripherals.reduce(0) { $0 + $1.samples.count }
            let p = keyboard.peripherals.count
            Text("This will permanently remove “\(keyboard.name)”, its \(p) peripheral\(p == 1 ? "" : "s"), and \(sampleCount) battery sample\(sampleCount == 1 ? "" : "s"). This cannot be undone.")
        }
        .alert("Rename keyboard",
               isPresented: Binding(
                get: { keyboardToRename != nil },
                set: { if !$0 { keyboardToRename = nil } }
               ),
               presenting: keyboardToRename) { keyboard in
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    keyboard.name = trimmed
                }
                keyboardToRename = nil
            }
            Button("Cancel", role: .cancel) {
                keyboardToRename = nil
            }
        }
    }
}

private struct EmptySidebarState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No keyboards")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Plug in your ZMK dongle. You can also enable the demo keyboard in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct KeyboardRow: View {
    let keyboard: Keyboard
    let thresholdSeconds: Double

    private var sortedPeripherals: [Device] {
        keyboard.peripherals.sorted(by: { $0.slot < $1.slot })
    }

    private var isOnline: Bool {
        Date().timeIntervalSince(keyboard.lastSeen) < thresholdSeconds
    }

    private var subtitle: String {
        if !isOnline {
            return "Disconnected"
        }
        let parts = sortedPeripherals.compactMap { device -> String? in
            guard let sample = device.samples.max(by: { $0.timestamp < $1.timestamp }) else {
                return nil
            }
            return "\(sample.percent)%"
        }
        if parts.isEmpty { return "Disconnected" }
        return parts.joined(separator: " · ")
    }

    private var fullPreset: KeyboardPreset? {
        KeyboardPresetCatalog.resolvedLayout(for: keyboard)?.combinedPreset()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(keyboard.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let fullPreset {
                KeyboardIconView(preset: fullPreset)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 64, maxHeight: 28)
            }
        }
        .padding(.vertical, 2)
    }
}
