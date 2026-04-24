import SwiftUI
import SwiftData

@main
struct KibodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer
    @State private var deviceManager: DeviceManager
    @AppStorage("demoDeviceEnabled") private var demoDeviceEnabled = false
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    init() {
        let schema = Schema([Keyboard.self, Device.self, BatterySample.self, LayerUsage.self])
        // NOTE: the store file name is kept as-is so existing users' battery
        // history survives the rename. The bundle identifier is also unchanged
        // for the same reason (sandbox container path is bundle-id scoped).
        let storeURL = URL.applicationSupportDirectory
            .appending(path: "ZMKBatteryMonitor-v2.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
        self.container = container
        _deviceManager = State(wrappedValue: DeviceManager(modelContext: container.mainContext))
    }

    var body: some Scene {
        Window("Kibodo", id: "main") {
            ContentView()
                .environment(\.deviceManager, deviceManager)
                .themedRoot()
                .onAppear {
                    deviceManager.add(HIDBatteryDataSource())
                    syncDemoSource()
                }
                .onChange(of: demoDeviceEnabled) { _, _ in syncDemoSource() }
        }
        .modelContainer(container)

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarContentView()
        } label: {
            // The label renders in a separate SwiftUI environment from the
            // popover content, so it needs its own modelContainer attachment
            // to drive @Query.
            MenuBarLabel()
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)

        Settings {
            SettingsView()
                .themedRoot()
        }
    }

    private func syncDemoSource() {
        if demoDeviceEnabled {
            deviceManager.add(DemoBatteryDataSource())
        } else {
            deviceManager.purgeAll(sourceID: "demo")
        }
    }
}
