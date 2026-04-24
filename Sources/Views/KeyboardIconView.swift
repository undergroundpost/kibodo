import SwiftUI

/// Renders a `KeyboardPreset` as a compact icon. Scales to fit whatever frame
/// the caller provides while preserving the preset's aspect ratio.
///
/// Keys fill with the view's current `foregroundStyle`, so callers control the
/// color — e.g. a peripheral card passes the theme's muted color, while the
/// sidebar passes `.secondary` to auto-adapt on row selection.
struct KeyboardIconView: View {
    let preset: KeyboardPreset
    var cornerRadius: CGFloat = 1.5
    var keyInset: CGFloat = 0.5

    var body: some View {
        Canvas { ctx, canvasSize in
            let bounds = preset.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            let padding: CGFloat = 1
            let scale = min(
                (canvasSize.width - padding * 2) / bounds.width,
                (canvasSize.height - padding * 2) / bounds.height
            )
            let scaledWidth = bounds.width * scale
            let scaledHeight = bounds.height * scale
            let xOffset = (canvasSize.width - scaledWidth) / 2 - bounds.minX * scale
            let yOffset = (canvasSize.height - scaledHeight) / 2 - bounds.minY * scale

            for key in preset.keys {
                let rect = CGRect(
                    x: key.x * scale + xOffset,
                    y: key.y * scale + yOffset,
                    width: key.w * scale,
                    height: key.h * scale
                ).insetBy(dx: keyInset, dy: keyInset)

                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                ctx.fill(path, with: .foreground)
            }
        }
        .aspectRatio(preset.bounds.width / preset.bounds.height, contentMode: .fit)
    }
}
