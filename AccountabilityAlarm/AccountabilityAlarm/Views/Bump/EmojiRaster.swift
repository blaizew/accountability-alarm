import SwiftUI
import UIKit

/// Rasterizes an emoji to a bitmap so it can be sliced into pieces.
enum EmojiRaster {
    /// The glyph is sized at `FistView.fontFactor` times the frame width,
    /// matching `FistView`. The image is a square of `pointSize / fontFactor` points.
    @MainActor
    static func image(_ emoji: String, pointSize: CGFloat) -> UIImage? {
        let side = pointSize / FistView.fontFactor
        let content = Text(emoji)
            .font(.system(size: pointSize))
            .fixedSize()
            .frame(width: side, height: side)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.uiImage
    }
}
