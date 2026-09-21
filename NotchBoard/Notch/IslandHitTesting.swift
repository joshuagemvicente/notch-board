import Foundation

/// Shared island hit geometry — clicks and hover must use the same predicate.
enum IslandHitTesting {
    /// NSHostingView is flipped (origin top-left); island sits at y = 0, centered.
    /// Idle pad is 0 so the compact panel's tiny shadow margins stay click-through.
    static func pointInIsland(
        _ point: CGPoint,
        in bounds: CGRect,
        shapeWidth: CGFloat,
        shapeHeight: CGFloat,
        hovered: Bool
    ) -> Bool {
        let pad: CGFloat = hovered ? 2 : 0
        let rect = CGRect(
            x: bounds.midX - shapeWidth / 2 - pad,
            y: 0,
            width: shapeWidth + pad * 2,
            height: shapeHeight + pad
        )
        return rect.contains(point)
    }
}
