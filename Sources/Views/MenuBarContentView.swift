import SwiftUI
import SwiftData

/// Menu bar popover content. Deliberately uses system fonts and colors rather
/// than the app's theme — menu bar items blend in with macOS rather than
/// standing out like the main window.
struct MenuBarContentView: View {
    @Query(sort: \Device.name) private var devices: [Device]
    @Environment(\.openWindow) private var openWindow

    private var sortedPeripherals: [Device] {
        devices.sorted { percent(for: $0) < percent(for: $1) }
    }

    private func percent(for device: Device) -> Int {
        device.samples.max(by: { $0.timestamp < $1.timestamp })?.percent ?? 100
    }

    private func percentLabel(for device: Device) -> String {
        if let sample = device.samples.max(by: { $0.timestamp < $1.timestamp }) {
            return "\(sample.percent)%"
        }
        return "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if devices.isEmpty {
                HStack {
                    Text("No keyboards connected")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            } else {
                ForEach(sortedPeripherals) { device in
                    HStack {
                        Text(device.displayName)
                        Spacer()
                        Text(percentLabel(for: device))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
                }
            }

            Divider()
                .padding(.vertical, 4)

            MenuBarButton("Open Kibodo") {
                // If the dock icon is currently hidden, bring it back before
                // showing the window so the user has normal app chrome.
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            MenuBarButton("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 5)
        .frame(minWidth: 240)
    }
}

/// Menu item button with the standard macOS hover highlight.
private struct MenuBarButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(isHovering ? Color.white : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(isHovering ? Color.accentColor : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
