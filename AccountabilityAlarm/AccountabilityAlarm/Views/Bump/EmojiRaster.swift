import SwiftUI
import UIKit

/// Rasterizes an emoji to a bitmap so it can be sliced into pieces.
enum EmojiRaster {
    /// The glyph's visible width is about 82 percent of its point size's frame,
    /// matching `FistView`. The image is a square of `pointSize / 0.82` points.
    @MainActor
    static func image(_ emoji: String, pointSize: CGFloat) -> UIImage? {
        let side = pointSize / 0.82
        let content = Text(emoji)
            .font(.system(size: pointSize))
            .frame(width: side, height: side)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.uiImage
    }
}
