import SwiftUI
import SwiftData
import AppKit

/// The view shown in the macOS menu bar. Composable via user settings:
/// icon, active layer, battery levels (all/lowest-only). Badges render as
/// filled pills with reversed text so they stay legible at menu-bar size.
///
/// Implementation note: the composition is rasterized via `ImageRenderer`.
/// `MenuBarExtra`'s label pipeline doesn't reliably compose HStacks with 3+
/// custom-styled children; handing macOS a single pre-rendered image bypasses
/// that entirely.
struct MenuBarLabel: View {
    @AppStorage("menuBarShowIcon") private var showIcon = true
    @AppStorage("menuBarUseCustomIcon") private var useCustomIcon = false
    @AppStorage("menuBarShowLayer") private var showLayer = false
    @AppStorage("menuBarShowBattery") private var showBattery = false
    @AppStorage("menuBarBatteryLowestOnly") private var batteryLowestOnly = true
    @AppStorage("menuBarFilledBadges") private var filledBadges = true
    @Environment(\.colorScheme) private var colorScheme

    @Query private var keyboards: [Keyboard]
    @Query private var devices: [Device]

    var body: some View {
        if let image = rasterized {
            Image(nsImage: image)
        } else {
            Image(systemName: "keyboard")
        }
    }

    private var rasterized: NSImage? {
        let renderer = ImageRenderer(content: rendered)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    @ViewBuilder
    private var rendered: some View {
        HStack(spacing: 4) {
            if showIcon || !hasAnyBadge {
                icon
            }
            if showLayer, let text = layerText {
                badge(text)
            }
            if showBattery {
                // Index-keyed id so two peripherals at the same percent don't
                // collapse into a single badge (ForEach dedupes on \.self).
                ForEach(Array(batteryBadges.enumerated()), id: \.offset) { _, text in
                    badge(text)
                }
            }
        }
        .padding(.vertical, 2)
        .environment(\.colorScheme, colorScheme)
        // Kill any implicit SwiftUI animation: ImageRenderer rasterizes one
        // size-stable image at a time, so any inter-frame interpolation just
        // shows up as visual jitter when layer text resizes the pill.
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private var icon: some View {
        if useCustomIcon, let layout = activeLayout {
            fillWrapper {
                KeyboardIconView(preset: layout.combinedPreset(), cornerRadius: 1, keyInset: 0.4)
                    .frame(width: 38, height: 14)
            }
        } else {
            fillWrapper {
                Image(systemName: "keyboard")
            }
        }
    }

    /// Wraps an icon view in the same pill styling as text badges when
    /// `filledBadges` is on; otherwise just applies the plain foreground color.
    @ViewBuilder
    private func fillWrapper<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if filledBadges {
            content()
                .foregroundStyle(pillForeground)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(pillBackground)
                )
        } else {
            content()
                .foregroundStyle(foreground)
        }
    }

    private var activeLayout: KeyboardLayout? {
        for kb in keyboards {
            if let layout = KeyboardPresetCatalog.resolvedLayout(for: kb) {
                return layout
            }
        }
        return nil
    }

    /// Ensures there's always something to click — if the user turns off
    /// every option, fall back to the icon so the menu doesn't disappear.
    private var hasAnyBadge: Bool {
        (showLayer && layerText != nil) || (showBattery && !batteryBadges.isEmpty)
    }

    private var foreground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var pillBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var pillForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    @ViewBuilder
    private func badge(_ text: String) -> some View {
        // Monospaced design keeps every char the same width, so changing
        // layers (BASE → NUMPAD) and changing battery digits (5% → 100%)
        // grow/shrink the pill in clean, uniform increments instead of
        // jumping by uneven amounts.
        let font = Font.system(size: 11, weight: .semibold, design: .monospaced)
        if filledBadges {
            Text(text)
                .font(font)
                .foregroundStyle(pillForeground)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(pillBackground)
                )
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(foreground)
        }
    }

    private var layerText: String? {
        for kb in keyboards {
            if let name = kb.activeLayerDisplayName {
                return name
            }
        }
        return nil
    }

    private var batteryBadges: [String] {
        let withPercent = devices
            .sorted { $0.slot < $1.slot }
            .compactMap { device -> Int? in
                device.samples.max(by: { $0.timestamp < $1.timestamp })?.percent
            }
        guard !withPercent.isEmpty else { return [] }

        if batteryLowestOnly {
            if let lowest = withPercent.min() {
                return ["\(lowest)%"]
            }
            return []
        }
        return withPercent.map { "\($0)%" }
    }
}
