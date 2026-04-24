import SwiftUI

/// Semantic color slots that every theme provides. Views pull from these
/// via the `themeColors` environment value rather than naming raw colors.
struct ColorRoles: Equatable {
    let background: Color   // window / root background
    let main: Color         // primary accent: trend line, healthy state, emphasis
    let error: Color        // error state: low battery, warnings
    let subAlt: Color       // alternate background: cards, sections
    let sub: Color          // secondary text, muted icons
    let text: Color         // primary text
}
