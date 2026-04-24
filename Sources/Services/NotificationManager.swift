import Foundation
import UserNotifications

/// Time unit for the "time remaining" notification threshold.
enum TimeUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days

    var id: String { rawValue }

    /// How many hours this unit represents.
    var hoursPerUnit: Double {
        switch self {
        case .minutes: return 1.0 / 60.0
        case .hours:   return 1.0
        case .days:    return 24.0
        }
    }
}

/// Local notifications for low battery + low time-remaining events. Tracks
/// per-peripheral "already notified" state in UserDefaults with hysteresis so
/// we don't spam when the battery hovers around the threshold.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// Retains the delegate so notifications present as banners even while
    /// our own app is frontmost. Without this, macOS silently routes the
    /// notification straight to Notification Center.
    private let presenter = NotificationPresenter()

    private init() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    // MARK: - Authorization

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    // MARK: - Threshold checks

    /// Evaluate enabled thresholds against the given device's latest data and
    /// fire notifications if they've just crossed below.
    func checkThresholds(for device: Device) {
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: "percentNotificationEnabled") {
            let threshold = Swift.max(1, defaults.integer(forKey: "percentNotificationThreshold"))
            checkPercent(device: device, threshold: threshold)
        }

        if defaults.bool(forKey: "timeNotificationEnabled") {
            let value = Swift.max(1, defaults.integer(forKey: "timeNotificationValue"))
            let unitRaw = defaults.string(forKey: "timeNotificationUnit") ?? TimeUnit.hours.rawValue
            let unit = TimeUnit(rawValue: unitRaw) ?? .hours
            let thresholdHours = Double(value) * unit.hoursPerUnit
            checkTime(device: device, thresholdHours: thresholdHours)
        }
    }

    // MARK: - Private

    private func checkPercent(device: Device, threshold: Int) {
        guard let latest = device.samples.max(by: { $0.timestamp < $1.timestamp }) else { return }
        // Key includes the threshold so a new threshold value starts with a
        // fresh flag — avoids "stuck notified" after the user changes the
        // setting.
        let key = "notified.percent.\(device.externalID).\(threshold)"
        let alreadyNotified = UserDefaults.standard.bool(forKey: key)

        if latest.percent <= threshold, !alreadyNotified {
            send(
                title: device.displayName,
                body: "Battery at \(latest.percent)%."
            )
            UserDefaults.standard.set(true, forKey: key)
        } else if latest.percent > threshold + 2 {
            // Hysteresis: require 3%+ rise above threshold before re-arming.
            UserDefaults.standard.set(false, forKey: key)
        }
    }

    private func checkTime(device: Device, thresholdHours: Double) {
        let projection = device.projection()
        guard let remaining = projection.hoursRemaining else { return }
        // Include threshold (as minutes) in the key so changing the setting
        // starts with a fresh flag.
        let thresholdMinutes = Int(thresholdHours * 60)
        let key = "notified.time.\(device.externalID).\(thresholdMinutes)"
        let alreadyNotified = UserDefaults.standard.bool(forKey: key)

        if remaining <= thresholdHours, !alreadyNotified {
            send(
                title: device.displayName,
                body: "About \(formatRemaining(hours: remaining)) remaining."
            )
            UserDefaults.standard.set(true, forKey: key)
        } else if remaining > thresholdHours * 1.25 {
            // Hysteresis: require 25% rise above threshold before re-arming.
            UserDefaults.standard.set(false, forKey: key)
        }
    }

    // MARK: - Test notifications

    /// Fires a sample low-battery notification immediately, using the given
    /// device's name when available.
    func sendPercentTest(device: Device?, threshold: Int) {
        send(
            title: device?.displayName ?? "Test Keyboard",
            body: "Battery at \(threshold)%. (Test notification)"
        )
    }

    /// Fires a sample time-remaining notification immediately.
    func sendTimeTest(device: Device?, thresholdHours: Double) {
        send(
            title: device?.displayName ?? "Test Keyboard",
            body: "About \(formatRemaining(hours: thresholdHours)) remaining. (Test notification)"
        )
    }

    private func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func formatRemaining(hours: Double) -> String {
        if hours < 1 {
            let m = Swift.max(1, Int((hours * 60).rounded()))
            return "\(m) \(m == 1 ? "minute" : "minutes")"
        }
        if hours < 48 {
            let h = Int(hours.rounded())
            return "\(h) \(h == 1 ? "hour" : "hours")"
        }
        let d = Int((hours / 24).rounded())
        return "\(d) \(d == 1 ? "day" : "days")"
    }
}

/// Delegate that opts into foreground-banner presentation for our app's
/// notifications. Without this, macOS silently routes them to Notification
/// Center when our app is frontmost.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
