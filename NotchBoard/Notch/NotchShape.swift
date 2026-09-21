//
//  NotchShape.swift
//  NotchBoard
//
//  Dynamic Island silhouette. Hardware mode uses concave top "ears" that blend
//  into the MacBook camera cutout. Floating mode is a continuous rounded pill
//  for non-notch displays.
//

import SwiftUI

enum NotchEarStyle: Equatable {
    /// Concave top ears — flush with the hardware notch.
    case hardware
    /// Fully convex continuous pill — under the menu bar on non-notch screens.
    case floating
}

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var style: NotchEarStyle

    init(
        topCornerRadius: CGFloat = 10,
        bottomCornerRadius: CGFloat = 16,
        style: NotchEarStyle = .hardware
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.style = style
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch style {
        case .floating:
            return Path(roundedRect: rect, cornerRadius: max(topCornerRadius, bottomCornerRadius), style: .continuous)
        case .hardware:
            return hardwarePath(in: rect)
        }
    }

    private func hardwarePath(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left ear: concave curve blending into the hardware notch
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(
            x: rect.minX + topCornerRadius,
            y: rect.maxY - bottomCornerRadius
        ))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(
            x: rect.maxX - topCornerRadius - bottomCornerRadius,
            y: rect.maxY
        ))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(
            x: rect.maxX - topCornerRadius,
            y: rect.minY + topCornerRadius
        ))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}
