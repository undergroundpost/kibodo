import SwiftUI
import AppKit

/// Keeps the app running when the main window is closed. Data collection
/// (via `DeviceManager`) continues in the background and the menu bar item
/// remains accessible. Quitting requires explicit action from the user
/// (⌘Q, App menu → Quit, or the Quit item in the menu bar popover).
///
/// Also manages the dock icon visibility based on the `hideDockWhenNoWindows`
/// user preference.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowsChanged),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowsChanged),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        updateActivationPolicy()
    }

    nonisolated deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowsChanged(_ notification: Notification) {
        // Defer so the window state is fully applied before we inspect it.
        Task { @MainActor [weak self] in
            self?.updateActivationPolicy()
        }
    }

    /// Inspects user preference + current window visibility and sets the
    /// activation policy accordingly:
    ///
    /// - Any main-capable window visible → `.regular` (dock icon shown)
    /// - No main-capable windows AND user enabled the hide option → `.accessory`
    /// - Otherwise → `.regular`
    func updateActivationPolicy() {
        let hideWhenClosed = UserDefaults.standard.bool(forKey: "hideDockWhenNoWindows")
        let hasVisibleMainWindow = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeMain
        }

        let desired: NSApplication.ActivationPolicy
        if hasVisibleMainWindow {
            desired = .regular
        } else if hideWhenClosed {
            desired = .accessory
        } else {
            desired = .regular
        }

        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
        }
    }
}
