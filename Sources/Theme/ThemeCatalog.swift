import SwiftUI

/// Registry of built-in themes. Add a new theme to `all` to make it
/// selectable from Settings — no other code changes required.
enum ThemeCatalog {
    static let defaultTheme = Theme(
        id: "default",
        name: "Default",
        light: ColorRoles(
            background: Color(hex: "#d8d2c3"),
            main:       Color(hex: "#513a2a"),
            error:      Color(hex: "#ca4754"),
            subAlt:     Color(hex: "#cdc0af"),
            sub:        Color(hex: "#8b6f5c"),
            text:       Color(hex: "#393b3b")
        ),
        dark: ColorRoles(
            background: Color(hex: "#1c1e26"),
            main:       Color(hex: "#c4a88a"),
            error:      Color(hex: "#d55170"),
            subAlt:     Color(hex: "#17181f"),
            sub:        Color(hex: "#db886f"),
            text:       Color(hex: "#bbbbbb")
        )
    )

    /// Mirrors the colors Apple uses in stock apps like Notes and Calendar —
    /// white/off-white surfaces, system blue accent, and the standard label /
    /// secondary-label grays. Pick this with the System font for a look that
    /// passes for a native macOS app.
    static let appleTheme = Theme(
        id: "apple",
        name: "Apple",
        light: ColorRoles(
            background: Color(hex: "#FFFFFF"),
            main:       Color(hex: "#007AFF"),
            error:      Color(hex: "#FF3B30"),
            subAlt:     Color(hex: "#F2F2F7"),
            sub:        Color(hex: "#8E8E93"),
            text:       Color(hex: "#000000")
        ),
        dark: ColorRoles(
            background: Color(hex: "#1E1E1E"),
            main:       Color(hex: "#0A84FF"),
            error:      Color(hex: "#FF453A"),
            subAlt:     Color(hex: "#2C2C2E"),
            sub:        Color(hex: "#98989D"),
            text:       Color(hex: "#FFFFFF")
        )
    )

    static let pinkTheme = Theme(
        id: "pink",
        name: "Pink",
        light: ColorRoles(
            background: Color(hex: "#ffffff"),
            main:       Color(hex: "#f5b1cc"),
            error:      Color(hex: "#ffe495"),
            subAlt:     Color(hex: "#f2f2f2"),
            sub:        Color(hex: "#93e8d3"),
            text:       Color(hex: "#00ac8c")
        ),
        dark: ColorRoles(
            background: Color(hex: "#333a45"),
            main:       Color(hex: "#f44c7f"),
            error:      Color(hex: "#da3333"),
            subAlt:     Color(hex: "#2e343d"),
            sub:        Color(hex: "#939eae"),
            text:       Color(hex: "#e9ecf0")
        )
    )

    /// Built-in (fixed) themes. The Custom theme is appended separately in
    /// `all` since its colors are read dynamically from UserDefaults.
    static let builtIn: [Theme] = [defaultTheme, appleTheme, pinkTheme]

    /// All selectable themes, including the user's current Custom values.
    /// Recomputed each access so the preview reflects live edits.
    static var all: [Theme] { builtIn + [customTheme()] }

    static func theme(id: String) -> Theme {
        if id == CustomTheme.id { return customTheme() }
        return builtIn.first { $0.id == id } ?? defaultTheme
    }

    /// Builds the Custom theme from UserDefaults, falling back to the Default
    /// theme's values for any unset role.
    static func customTheme() -> Theme {
        Theme(
            id: CustomTheme.id,
            name: "Custom",
            light: ColorRoles(
                background: CustomTheme.color(.light, .background),
                main:       CustomTheme.color(.light, .main),
                error:      CustomTheme.color(.light, .error),
                subAlt:     CustomTheme.color(.light, .subAlt),
                sub:        CustomTheme.color(.light, .sub),
                text:       CustomTheme.color(.light, .text)
            ),
            dark: ColorRoles(
                background: CustomTheme.color(.dark, .background),
                main:       CustomTheme.color(.dark, .main),
                error:      CustomTheme.color(.dark, .error),
                subAlt:     CustomTheme.color(.dark, .subAlt),
                sub:        CustomTheme.color(.dark, .sub),
                text:       CustomTheme.color(.dark, .text)
            )
        )
    }
}

/// Keys and helpers for the user-editable Custom theme. Colors live in
/// UserDefaults as `#RRGGBB` strings; `version` is a monotonically-increasing
/// counter the themed root observes so live edits re-render the subtree.
enum CustomTheme {
    static let id = "custom"
    static let versionKey = "customThemeVersion"

    enum Scheme: String { case light, dark }
    enum Role: String, CaseIterable {
        case background, main, error, subAlt, sub, text

        var displayName: String {
            switch self {
            case .background: return "Background"
            case .main:       return "Main"
            case .error:      return "Error"
            case .subAlt:     return "SubAlt"
            case .sub:        return "Sub"
            case .text:       return "Text"
            }
        }
    }

    static func key(_ scheme: Scheme, _ role: Role) -> String {
        "custom.\(scheme.rawValue).\(role.rawValue)"
    }

    static func color(_ scheme: Scheme, _ role: Role) -> Color {
        let fallback = Self.fallback(scheme, role)
        guard let stored = UserDefaults.standard.string(forKey: key(scheme, role)),
              !stored.isEmpty else {
            return fallback
        }
        return Color(hex: stored)
    }

    static func set(_ color: Color, _ scheme: Scheme, _ role: Role) {
        UserDefaults.standard.set(color.hexString, forKey: key(scheme, role))
        bumpVersion()
    }

    /// Copies every role of the given theme into the Custom slots. Lets users
    /// start from a known-good palette.
    static func prefill(from theme: Theme) {
        for role in Role.allCases {
            UserDefaults.standard.set(color(from: theme, .light, role).hexString,
                                      forKey: key(.light, role))
            UserDefaults.standard.set(color(from: theme, .dark, role).hexString,
                                      forKey: key(.dark, role))
        }
        bumpVersion()
    }

    private static func bumpVersion() {
        let v = UserDefaults.standard.integer(forKey: versionKey)
        UserDefaults.standard.set(v + 1, forKey: versionKey)
    }

    private static func fallback(_ scheme: Scheme, _ role: Role) -> Color {
        color(from: ThemeCatalog.defaultTheme, scheme, role)
    }

    private static func color(from theme: Theme, _ scheme: Scheme, _ role: Role) -> Color {
        let roles = scheme == .light ? theme.light : theme.dark
        switch role {
        case .background: return roles.background
        case .main:       return roles.main
        case .error:      return roles.error
        case .subAlt:     return roles.subAlt
        case .sub:        return roles.sub
        case .text:       return roles.text
        }
    }
}
