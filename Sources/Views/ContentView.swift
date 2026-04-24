import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Keyboard.name) private var keyboards: [Keyboard]
    @State private var selectedKeyboard: Keyboard?
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationSplitView {
            KeyboardListView(selectedKeyboard: $selectedKeyboard)
        } detail: {
            if let keyboard = selectedKeyboard, !keyboard.isDeleted {
                KeyboardDetailView(keyboard: keyboard)
            } else if keyboards.isEmpty {
                EmptyStateView()
            } else {
                ContentUnavailableView {
                    Label {
                        Text("Select a keyboard").font(.appTitle3)
                    } icon: {
                        Image(systemName: "keyboard")
                    }
                } description: {
                    Text("Your keyboard will appear in the sidebar when its dongle is plugged in and running Kibodo firmware.")
                        .font(.appBody)
                }
            }
        }
        .foregroundStyle(colors.text)
        .background(colors.background)
        .navigationTitle("Kibodo")
        .onChange(of: keyboards.map(\.externalID)) { _, newIDs in
            if let selected = selectedKeyboard, !newIDs.contains(selected.externalID) {
                selectedKeyboard = nil
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No keyboards connected").font(.appTitle3)
            } icon: {
                Image(systemName: "keyboard")
            }
        } description: {
            Text("Plug in your ZMK dongle to see battery levels. You can also enable the demo keyboard in Settings to explore the app.")
                .font(.appBody)
        }
    }
}
