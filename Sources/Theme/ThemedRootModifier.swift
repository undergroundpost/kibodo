import SwiftUI

/// Resolves the current theme + font + appearance preferences from
/// `@AppStorage`, injects `themeColors` into the environment, sets the env
/// font, and applies `preferredColorScheme`. Apply once near the scene root
/// via `.themedRoot()`.
///
/// This is a `View` wrapper (not a `ViewModifier`) so the dynamic-property
/// machinery reliably invalidates its body when any observed `@AppStorage`
/// changes, guaranteeing a fresh render of the themed subtree.
struct ThemedRoot<Content: View>: View {
    @AppStorage("selectedThemeID") private var selectedThemeID: String = "default"
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("themeFontFamily") private var themeFontFamily: String = ThemeFont.robotoMono.rawValue
    /// Observed so live Custom-theme edits re-render the subtree. The actual
    /// colors live in their own keys — this is just a change counter.
    @AppStorage(CustomTheme.versionKey) private var customThemeVersion: Int = 0
    @Environment(\.colorScheme) private var systemScheme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var effectiveScheme: ColorScheme {
        appearanceMode.preferredColorScheme ?? systemScheme
    }

    var body: some View {
        // Reference the version explicitly so SwiftUI actually observes the
        // key — bumping it forces this body to re-run and the env.themeColors
        // below to be re-resolved from the latest UserDefaults values.
        let _ = customThemeVersion
        let theme = ThemeCatalog.theme(id: selectedThemeID)
        let colors = theme.colors(for: effectiveScheme)
        content
            .font(.appBody)
            .environment(\.themeColors, colors)
            .preferredColorScheme(appearanceMode.preferredColorScheme)
            // `Font.app*` computes from UserDefaults at call time. Giving the
            // subtree a new identity when the font selection changes forces
            // SwiftUI to rebuild every child body, so each `.appXxx` call
            // re-reads UserDefaults.
            .id(themeFontFamily)
    }
}

extension View {
    func themedRoot() -> some View {
        ThemedRoot { self }
    }
}
