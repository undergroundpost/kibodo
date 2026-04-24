import SwiftUI

/// Which typeface the app renders in. Roboto Mono gives the "monkeytype" feel;
/// System uses the macOS default (SF Pro / SF Mono for mono sizes) for users
/// who prefer a more native look.
enum ThemeFont: String, CaseIterable, Identifiable {
    case robotoMono
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .robotoMono: return "Roboto Mono"
        case .system:     return "System"
        }
    }
}

/// Application fonts. Resolve at call time against the user's choice in
/// Settings → Appearance, so a root-level view that reads the same `@AppStorage`
/// key re-renders the tree when it changes.
extension Font {
    private static let robotoRegular = "RobotoMono-Regular"
    private static let robotoItalic = "RobotoMono-Italic"

    /// Reads the current font selection. Defaults to Roboto Mono when unset.
    private static var currentThemeFont: ThemeFont {
        let raw = UserDefaults.standard.string(forKey: "themeFontFamily")
            ?? ThemeFont.robotoMono.rawValue
        return ThemeFont(rawValue: raw) ?? .robotoMono
    }

    private static func themed(size: CGFloat, style: Font.TextStyle) -> Font {
        switch currentThemeFont {
        case .robotoMono: return .custom(robotoRegular, size: size, relativeTo: style)
        case .system:     return .system(size: size, design: .default)
        }
    }

    static var appLargeTitle:  Font { themed(size: 26, style: .largeTitle) }
    static var appTitle:       Font { themed(size: 22, style: .title) }
    static var appTitle2:      Font { themed(size: 17, style: .title2) }
    static var appTitle3:      Font { themed(size: 15, style: .title3) }
    static var appHeadline:    Font { themed(size: 13, style: .headline) }
    static var appBody:        Font { themed(size: 13, style: .body) }
    static var appCallout:     Font { themed(size: 12, style: .callout) }
    static var appSubheadline: Font { themed(size: 11, style: .subheadline) }
    static var appFootnote:    Font { themed(size: 10, style: .footnote) }
    static var appCaption:     Font { themed(size: 10, style: .caption) }
    static var appCaption2:    Font { themed(size: 10, style: .caption2) }

    /// A custom-sized font. With Roboto Mono selected, renders as the mono
    /// typeface — gives the app its "monkeytype" feel for numeric values.
    /// With System selected, falls through to SF Pro (proportional) so the
    /// whole app reads as a native macOS app, matching how macOS stock apps
    /// render stat values and numeric displays.
    static func appMono(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        switch currentThemeFont {
        case .robotoMono: return .custom(robotoRegular, size: size, relativeTo: style)
        case .system:     return .system(size: size)
        }
    }

    static func appMonoItalic(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        switch currentThemeFont {
        case .robotoMono: return .custom(robotoItalic, size: size, relativeTo: style)
        case .system:     return .system(size: size).italic()
        }
    }
}
