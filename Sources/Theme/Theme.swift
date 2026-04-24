import SwiftUI

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let light: ColorRoles
    let dark: ColorRoles

    func colors(for scheme: ColorScheme) -> ColorRoles {
        scheme == .dark ? dark : light
    }
}
