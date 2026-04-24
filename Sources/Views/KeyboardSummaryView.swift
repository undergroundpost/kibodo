import SwiftUI
import SwiftData

struct KeyboardSummaryView: View {
    let keyboard: Keyboard
    @AppStorage("disconnectThresholdSeconds") private var disconnectThresholdSeconds: Double = 120
    @Environment(\.themeColors) private var colors

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private var isOnline: Bool {
        Date().timeIntervalSince(keyboard.lastSeen) < disconnectThresholdSeconds
    }

    private var totalSamples: Int {
        keyboard.peripherals.reduce(0) { $0 + $1.samples.count }
    }

    private var sortedPeripherals: [Device] {
        keyboard.peripherals.sorted(by: { $0.slot < $1.slot })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if !sortedPeripherals.isEmpty {
                    peripheralsRow
                }
                statsGrid
                BatteryTrendChart(keyboard: keyboard)
                LayerUsageChart(keyboard: keyboard)
            }
            .padding(24)
        }
    }

    private var peripheralsRow: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(sortedPeripherals) { peripheral in
                PeripheralCard(device: peripheral)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var statsGrid: some View {
        // Only Total Usage + Current Session tick with wall-clock time, so we
        // scope the TimelineView to them — otherwise expensive stats like
        // `averageBatteryLifeText` (linear regression across history) recompute
        // every second for no reason.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: 24, alignment: .leading)],
            spacing: 24
        ) {
            StatCell(
                title: "Status",
                value: isOnline ? "Active" : "Disconnected"
            )
            StatCell(
                title: "Active Layer",
                value: isOnline ? (keyboard.activeLayerDisplayName ?? "—") : "—"
            )
            StatCell(title: "Samples", value: "\(totalSamples)")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatCell(
                    title: "Total Usage",
                    value: formatDuration(totalUsageSeconds(now: context.date))
                )
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatCell(
                    title: "Current Session",
                    value: currentSessionText(now: context.date)
                )
            }
            StatCell(
                title: "Avg Battery Life",
                value: averageBatteryLifeText
            )
            StatCell(title: "Last Charged", value: lastChargedText)
            StatCell(
                title: "First Seen",
                value: Self.dateFormatter.string(from: keyboard.firstSeen)
            )
            StatCell(
                title: "Last Seen",
                value: Self.dateFormatter.string(from: keyboard.lastSeen)
            )
        }
    }

    private func totalUsageSeconds(now: Date) -> TimeInterval {
        var total = keyboard.totalConnectedSeconds
        if isOnline {
            total += now.timeIntervalSince(keyboard.lastSeen)
        }
        return total
    }

    private func currentSessionText(now: Date) -> String {
        guard isOnline, let start = keyboard.currentSessionStart else {
            return "—"
        }
        return formatDuration(now.timeIntervalSince(start))
    }

    private var averageBatteryLifeText: String {
        if let hours = keyboard.averageBatteryLifeHours {
            return formatDuration(hours * 3600)
        }
        return "—"
    }

    private var lastChargedText: String {
        guard let lastCharged = keyboard.lastCharged else { return "—" }
        return lastCharged.formatted(.relative(presentation: .named))
    }
}

private struct PeripheralCard: View {
    let device: Device
    @Environment(\.themeColors) private var colors
    @Environment(\.deviceManager) private var deviceManager

    @State private var renameText: String = ""
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false

    private var latestSample: BatterySample? {
        device.samples.max(by: { $0.timestamp < $1.timestamp })
    }

    private var projection: BatteryProjection {
        device.projection()
    }

    private var percentText: String {
        guard let sample = latestSample else { return "—" }
        return "\(sample.percent)%"
    }

    private var remainingText: String {
        if let remaining = projection.formattedRemaining {
            return "\(remaining) remaining"
        }
        switch projection.reason {
        case .notEnoughSamples, .tooLittleElapsed:
            return "Gathering data…"
        case .noDropYet:
            return "No drain observed yet"
        case .none:
            return ""
        }
    }

    private var preset: KeyboardPreset? {
        guard let keyboard = device.keyboard else { return nil }
        return KeyboardPresetCatalog.preset(for: keyboard, peripheralName: device.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let preset {
                    KeyboardIconView(preset: preset)
                        .foregroundStyle(colors.sub)
                        .frame(width: 32, height: 22)
                }
                Text(device.displayName.lowercased())
                    .font(.appTitle3)
                    .foregroundStyle(colors.sub)
                Spacer()
                kebabMenu
            }

            Text(percentText)
                .font(.appMono(size: 96))
                .bold()
                .foregroundStyle(colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(remainingText)
                .font(.appTitle3)
                .foregroundStyle(colors.text.opacity(0.5))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(colors.subAlt))
        .alert("Rename peripheral", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                device.userName = trimmed.isEmpty ? nil : trimmed
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(device.displayName)?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete", role: .destructive) {
                deviceManager?.delete(device)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove this peripheral and its \(device.samples.count) battery sample\(device.samples.count == 1 ? "" : "s"). This cannot be undone.")
        }
    }

    private var kebabMenu: some View {
        Menu {
            Button {
                renameText = device.displayName
                isRenaming = true
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete Peripheral…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.appCallout)
                .foregroundStyle(colors.sub)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct StatCell: View {
    let title: String
    let value: String
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.lowercased())
                .font(.appTitle3)
                .foregroundStyle(colors.sub)
            Text(value)
                .font(.appMono(size: 34))
                .bold()
                .foregroundStyle(colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
