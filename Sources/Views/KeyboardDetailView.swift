import SwiftUI
import SwiftData

struct KeyboardDetailView: View {
    let keyboard: Keyboard

    var body: some View {
        KeyboardSummaryView(keyboard: keyboard)
            .navigationTitle(keyboard.name)
    }
}
