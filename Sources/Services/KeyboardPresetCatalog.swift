import Foundation

/// A whole-keyboard layout. For split keyboards it exposes both halves; the
/// correct half is picked at render time using the peripheral's label.
struct KeyboardLayout: Identifiable, Hashable {
    let id: String
    let name: String
    let leftHalf: KeyboardPreset
    let rightHalf: KeyboardPreset

    func preset(for peripheralName: String) -> KeyboardPreset? {
        let lowered = peripheralName.lowercased()
        if lowered.contains("left") { return leftHalf }
        if lowered.contains("right") { return rightHalf }
        return nil
    }

    /// Synthesizes a single preset representing the whole keyboard with both
    /// halves placed side by side and a small gap between them. Useful for
    /// the sidebar row where we want the full keyboard shape, not just one
    /// half.
    func combinedPreset(gap: Double = 1.5) -> KeyboardPreset {
        let rightShift = leftHalf.bounds.maxX + gap
        let rightShifted = rightHalf.keys.map {
            PresetKey(x: $0.x + rightShift, y: $0.y, w: $0.w, h: $0.h, r: $0.r)
        }
        return KeyboardPreset(
            id: id + "-full",
            name: name,
            keys: leftHalf.keys + rightShifted
        )
    }
}

/// Sentinel for `Keyboard.layoutID` meaning "don't render a custom icon."
/// A nil `layoutID` means "auto-detect"; anything else is a real layout id
/// with this one exception.
enum KeyboardLayoutSentinel {
    static let none = "none"
}

/// Bundled physical-layout presets. Coordinates are approximate — for a small
/// icon the exact positions matter less than the overall shape reading as the
/// right keyboard (Corne vs. Sofle vs. Kyria etc.).
enum KeyboardPresetCatalog {
    static let allLayouts: [KeyboardLayout] = [
        corne5Col,
        corne6Col,
        cantor,
        adux,
        piantor,
        ferrisSweep,
        chocofi,
        totem,
        kyria,
        lily58,
        sofle,
        iris,
    ]

    static func layout(id: String) -> KeyboardLayout? {
        allLayouts.first(where: { $0.id == id })
    }

    /// Resolves the keyboard-level layout honoring the explicit choice
    /// (`layoutID`) with a conservative name-based fallback.
    static func resolvedLayout(for keyboard: Keyboard) -> KeyboardLayout? {
        if let chosen = keyboard.layoutID {
            if chosen == KeyboardLayoutSentinel.none { return nil }
            return layout(id: chosen)
        }
        let haystack = ([keyboard.name] + keyboard.peripherals.map(\.name))
            .joined(separator: " ")
            .lowercased()
        if haystack.contains("corne") { return corne6Col }
        return nil
    }

    /// Resolves the per-half preset for rendering on a peripheral card.
    static func preset(for keyboard: Keyboard, peripheralName: String) -> KeyboardPreset? {
        resolvedLayout(for: keyboard)?.preset(for: peripheralName)
    }

    // MARK: - Layouts

    /// Builds a KeyboardLayout from a split spec by generating left + right halves.
    private static func makeLayout(
        id: String,
        name: String,
        rows: Int,
        cols: Int,
        stagger: [Double],
        thumbs: [(x: Double, y: Double)]
    ) -> KeyboardLayout {
        KeyboardLayout(
            id: id,
            name: name,
            leftHalf: KeyboardPreset(
                id: id + "-left",
                name: "\(name) · Left",
                keys: splitSide(rows: rows, cols: cols, stagger: stagger, thumbs: thumbs, mirrored: false)
            ),
            rightHalf: KeyboardPreset(
                id: id + "-right",
                name: "\(name) · Right",
                keys: splitSide(rows: rows, cols: cols, stagger: stagger, thumbs: thumbs, mirrored: true)
            )
        )
    }

    /// Generates keys for one side of a split keyboard.
    /// - Finger keys laid out as rows × cols with per-column y offset (`stagger`).
    /// - Thumb coordinates given in the left-hand frame; right mirrors along X.
    private static func splitSide(
        rows: Int,
        cols: Int,
        stagger: [Double],
        thumbs: [(x: Double, y: Double)],
        mirrored: Bool
    ) -> [PresetKey] {
        var keys: [PresetKey] = []
        for row in 0..<rows {
            for col in 0..<cols {
                let columnStagger = mirrored ? stagger[cols - 1 - col] : stagger[col]
                keys.append(PresetKey(x: Double(col), y: Double(row) + columnStagger))
            }
        }
        let maxCol = Double(cols - 1)
        if mirrored {
            // Mirror thumb xs along the side's midline and reverse order so the
            // "innermost" thumb (closest to center) stays innermost visually.
            for thumb in thumbs.reversed() {
                keys.append(PresetKey(x: maxCol - thumb.x, y: thumb.y))
            }
        } else {
            for thumb in thumbs {
                keys.append(PresetKey(x: thumb.x, y: thumb.y))
            }
        }
        return keys
    }

    // 3×5 + 3 thumb
    private static let corne5Col = makeLayout(
        id: "corne-5col",
        name: "Corne (5-col)",
        rows: 3,
        cols: 5,
        stagger: [0.25, 0.125, 0.0, 0.125, 0.25],
        thumbs: [(2, 3.25), (3, 3.5), (4, 3.75)]
    )

    // 3×6 + 3 thumb
    private static let corne6Col = makeLayout(
        id: "corne-6col",
        name: "Corne (6-col)",
        rows: 3,
        cols: 6,
        stagger: [0.375, 0.25, 0.0, 0.0, 0.125, 0.25],
        thumbs: [(3, 3.25), (4, 3.5), (5, 3.75)]
    )

    // 3×5 + 3 thumb, mild stagger
    private static let cantor = makeLayout(
        id: "cantor",
        name: "Cantor",
        rows: 3,
        cols: 5,
        stagger: [0.25, 0.125, 0.0, 0.125, 0.25],
        thumbs: [(2, 3.2), (3, 3.35), (4, 3.5)]
    )

    // 3×5 + 3 thumb, flatter stagger
    private static let adux = makeLayout(
        id: "adux",
        name: "A. Dux",
        rows: 3,
        cols: 5,
        stagger: [0.2, 0.1, 0.0, 0.1, 0.15],
        thumbs: [(2, 3.15), (3, 3.3), (4, 3.45)]
    )

    // 3×5 + 3 thumb, aggressive stagger
    private static let piantor = makeLayout(
        id: "piantor",
        name: "Piantor",
        rows: 3,
        cols: 5,
        stagger: [0.35, 0.2, 0.0, 0.1, 0.2],
        thumbs: [(2, 3.25), (3, 3.45), (4, 3.6)]
    )

    // 3×5 + 2 thumb (minimal 34-key)
    private static let ferrisSweep = makeLayout(
        id: "ferris-sweep",
        name: "Ferris Sweep",
        rows: 3,
        cols: 5,
        stagger: [0.25, 0.125, 0.0, 0.125, 0.25],
        thumbs: [(3, 3.4), (4, 3.55)]
    )

    // 3×5 + 2 thumb (similar minimal, slightly different stagger)
    private static let chocofi = makeLayout(
        id: "chocofi",
        name: "Chocofi",
        rows: 3,
        cols: 5,
        stagger: [0.3, 0.15, 0.0, 0.1, 0.25],
        thumbs: [(3, 3.35), (4, 3.5)]
    )

    // 3×5 + 3 thumb (aggressive column stagger, "tented" look)
    private static let totem = makeLayout(
        id: "totem",
        name: "Totem",
        rows: 3,
        cols: 5,
        stagger: [0.5, 0.25, 0.0, 0.25, 0.5],
        thumbs: [(2, 3.3), (3, 3.55), (4, 3.85)]
    )

    // 3×6 + 5 thumb cluster (Kyria-style)
    private static let kyria = makeLayout(
        id: "kyria",
        name: "Kyria",
        rows: 3,
        cols: 6,
        stagger: [0.5, 0.375, 0.125, 0.0, 0.125, 0.375],
        thumbs: [(3, 3.25), (4, 3.25), (3, 4.25), (4, 4.25), (5, 4.25)]
    )

    // 4×6 + 4 thumb
    private static let lily58 = makeLayout(
        id: "lily58",
        name: "Lily58",
        rows: 4,
        cols: 6,
        stagger: [0.375, 0.25, 0.125, 0.0625, 0.125, 0.25],
        thumbs: [(2, 4.4), (3, 4.55), (4, 4.7), (5, 4.85)]
    )

    // 5×6 + 5 thumb cluster (Sofle)
    private static let sofle = makeLayout(
        id: "sofle",
        name: "Sofle",
        rows: 5,
        cols: 6,
        stagger: [0.375, 0.25, 0.125, 0.0625, 0.125, 0.25],
        thumbs: [(2, 5.3), (3, 5.45), (4, 5.6), (5, 5.75), (5, 6.5)]
    )

    // 5×6 + 4 thumb (Iris)
    private static let iris = makeLayout(
        id: "iris",
        name: "Iris",
        rows: 5,
        cols: 6,
        stagger: [0.375, 0.25, 0.0, 0.0, 0.25, 0.375],
        thumbs: [(3, 5.25), (4, 5.5), (5, 5.75)]
    )
}
