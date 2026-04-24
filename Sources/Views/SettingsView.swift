import SwiftUI
import SwiftData
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            NotificationSettingsTab()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
            ThemeSettingsTab()
                .tabItem {
                    Label("Theme", systemImage: "paintpalette")
                }
        }
        .frame(width: 520, height: 640)
    }
}

private struct NotificationSettingsTab: View {
    @AppStorage("percentNotificationEnabled") private var percentEnabled = false
    @AppStorage("percentNotificationThreshold") private var percentThreshold: Int = 10
    @AppStorage("timeNotificationEnabled") private var timeEnabled = false
    @AppStorage("timeNotificationValue") private var timeValue: Int = 1
    @AppStorage("timeNotificationUnit") private var timeUnitRaw: String = TimeUnit.hours.rawValue

    @Query(sort: \Device.slot) private var devices: [Device]
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    private var timeUnitBinding: Binding<TimeUnit> {
        Binding(
            get: { TimeUnit(rawValue: timeUnitRaw) ?? .hours },
            set: { timeUnitRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            if authStatus == .denied {
                Section {
                    Text("Notifications are disabled for Kibodo. Enable them in System Settings → Notifications to receive alerts.")
                        .font(.appCaption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Notify when battery drops below a threshold", isOn: $percentEnabled)
                    .onChange(of: percentEnabled) { _, newValue in
                        if newValue { requestAuthIfNeeded() }
                    }
                HStack {
                    Text("Threshold")
                    Spacer()
                    TextField("", value: $percentThreshold, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("%")
                }
                .disabled(!percentEnabled)
                HStack {
                    Spacer()
                    Button("Test notification") {
                        NotificationManager.shared.sendPercentTest(
                            device: devices.first,
                            threshold: Swift.max(1, percentThreshold)
                        )
                    }
                    .disabled(authStatus == .denied)
                }
            } header: {
                Text("Low battery")
            }

            Section {
                Toggle("Notify when time remaining drops below a threshold", isOn: $timeEnabled)
                    .onChange(of: timeEnabled) { _, newValue in
                        if newValue { requestAuthIfNeeded() }
                    }
                HStack {
                    Text("Threshold")
                    Spacer()
                    TextField("", value: $timeValue, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Picker("", selection: timeUnitBinding) {
                        ForEach(TimeUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                .disabled(!timeEnabled)
                HStack {
                    Spacer()
                    Button("Test notification") {
                        let unit = TimeUnit(rawValue: timeUnitRaw) ?? .hours
                        let hours = Double(Swift.max(1, timeValue)) * unit.hoursPerUnit
                        NotificationManager.shared.sendTimeTest(
                            device: devices.first,
                            thresholdHours: hours
                        )
                    }
                    .disabled(authStatus == .denied)
                }
            } header: {
                Text("Time remaining")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            Task { @MainActor in
                authStatus = await NotificationManager.shared.authorizationStatus()
            }
        }
    }

    private func requestAuthIfNeeded() {
        Task { @MainActor in
            _ = await NotificationManager.shared.requestAuthorization()
            authStatus = await NotificationManager.shared.authorizationStatus()
        }
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage("demoDeviceEnabled") private var demoDeviceEnabled = false
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("disconnectThresholdSeconds") private var disconnectThresholdSeconds: Double = 120
    @AppStorage("hideDockWhenNoWindows") private var hideDockWhenNoWindows = false
    @AppStorage("menuBarShowIcon") private var menuBarShowIcon = true
    @AppStorage("menuBarUseCustomIcon") private var menuBarUseCustomIcon = false
    @AppStorage("menuBarShowLayer") private var menuBarShowLayer = false
    @AppStorage("menuBarShowBattery") private var menuBarShowBattery = false
    @AppStorage("menuBarBatteryLowestOnly") private var menuBarBatteryLowestOnly = true
    @AppStorage("menuBarFilledBadges") private var menuBarFilledBadges = true
    @State private var launchAtLogin: Bool = false
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { oldValue, newValue in
                        setLaunchAtLogin(newValue, fallbackTo: oldValue)
                    }
                if let error = launchAtLoginError {
                    Text(error)
                        .font(.appCaption)
                        .foregroundStyle(.red)
                } else {
                    Text("Starts Kibodo automatically when you sign in. The app runs in the background to log battery history continuously.")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Startup")
            }

            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Show keyboard icon", isOn: $menuBarShowIcon)
                    .disabled(!showInMenuBar)
                Toggle("Use custom icon", isOn: $menuBarUseCustomIcon)
                    .disabled(!showInMenuBar || !menuBarShowIcon)
                    .padding(.leading, 20)
                Toggle("Show active layer", isOn: $menuBarShowLayer)
                    .disabled(!showInMenuBar)
                Toggle("Show battery level", isOn: $menuBarShowBattery)
                    .disabled(!showInMenuBar)
                Toggle("Lowest peripheral only", isOn: $menuBarBatteryLowestOnly)
                    .disabled(!showInMenuBar || !menuBarShowBattery)
                    .padding(.leading, 20)
                Toggle("Filled badges", isOn: $menuBarFilledBadges)
                    .disabled(!showInMenuBar || (!menuBarShowIcon && !menuBarShowLayer && !menuBarShowBattery))
                Text("Layer names and battery levels render alongside the icon. Filled badges show them as pills; disable for plain text.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Menu bar")
            }

            Section {
                Toggle("Hide dock icon when no windows are open", isOn: $hideDockWhenNoWindows)
                Text("When the main window is closed, the app keeps running in the background without a dock icon. Open it again from the menu bar.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Dock")
            }

            Section {
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Slider(value: $disconnectThresholdSeconds, in: 30...600, step: 10)
                            .frame(width: 220)
                        Text(formatThreshold(disconnectThresholdSeconds))
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Disconnect threshold")
                }
                Text("If no data arrives from a keyboard in this window, it's shown as disconnected. Default is 2 minutes.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Connection")
            }

            Section {
                Toggle("Enable demo keyboard", isOn: $demoDeviceEnabled)
                Text("Adds a synthetic keyboard with two peripherals and fake battery data, for testing and demos. Turning this off removes the demo keyboard from the list.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Demo")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool, fallbackTo previous: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            // Revert the toggle without re-triggering onChange.
            DispatchQueue.main.async {
                launchAtLogin = previous
            }
        }
    }

    private func formatThreshold(_ seconds: Double) -> String {
        let secs = Int(seconds.rounded())
        if secs < 60 {
            return "\(secs)s"
        }
        let mins = secs / 60
        let rem = secs % 60
        return rem == 0 ? "\(mins)m" : "\(mins)m \(rem)s"
    }
}

private struct ThemeSettingsTab: View {
    @AppStorage("selectedThemeID") private var selectedThemeID: String = "default"
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("themeFontFamily") private var themeFontRaw: String = ThemeFont.robotoMono.rawValue
    /// Observed so the preview re-renders whenever any custom color changes.
    @AppStorage(CustomTheme.versionKey) private var customThemeVersion: Int = 0
    @Environment(\.themeColors) private var colors

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private var themeFont: Binding<ThemeFont> {
        Binding(
            get: { ThemeFont(rawValue: themeFontRaw) ?? .robotoMono },
            set: { themeFontRaw = $0.rawValue }
        )
    }

    var body: some View {
        let _ = customThemeVersion
        Form {
            Section {
                Picker("Theme", selection: $selectedThemeID) {
                    ForEach(ThemeCatalog.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Picker("Font", selection: themeFont) {
                    ForEach(ThemeFont.allCases) { font in
                        Text(font.displayName).tag(font)
                    }
                }
                Picker("Appearance", selection: appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Theme")
            }

            if selectedThemeID == CustomTheme.id {
                CustomThemeEditor()
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct CustomThemeEditor: View {
    /// Observed so SwiftUI re-renders this form whenever a color is edited
    /// (the bump is written in addition to the color itself).
    @AppStorage(CustomTheme.versionKey) private var version: Int = 0

    var body: some View {
        Section {
            Menu("Pre-fill from…") {
                ForEach(ThemeCatalog.builtIn) { theme in
                    Button(theme.name) { CustomTheme.prefill(from: theme) }
                }
            }
        } header: {
            Text("Custom")
        }

        Section {
            ForEach(CustomTheme.Role.allCases, id: \.self) { role in
                ColorPicker(role.displayName, selection: binding(for: .light, role), supportsOpacity: false)
            }
        } header: {
            Text("Custom · Light")
        }

        Section {
            ForEach(CustomTheme.Role.allCases, id: \.self) { role in
                ColorPicker(role.displayName, selection: binding(for: .dark, role), supportsOpacity: false)
            }
        } header: {
            Text("Custom · Dark")
        }
    }

    private func binding(for scheme: CustomTheme.Scheme, _ role: CustomTheme.Role) -> Binding<Color> {
        Binding(
            get: {
                _ = version  // keep the getter dependent on the observed version
                return CustomTheme.color(scheme, role)
            },
            set: { CustomTheme.set($0, scheme, role) }
        )
    }
}
