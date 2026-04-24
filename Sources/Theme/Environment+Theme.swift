import SwiftUI

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue: ColorRoles = ThemeCatalog.defaultTheme.dark
}

extension EnvironmentValues {
    /// Resolved color roles for the active theme and color scheme.
    /// Injected at the app root; read via `@Environment(\.themeColors)`.
    var themeColors: ColorRoles {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}
