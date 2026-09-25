//
//  NotchShape.swift
//  VornyxNotch
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander on 2025-05-18.

import SwiftUI

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(
                topCornerRadius,
                bottomCornerRadius
            )
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    /// The radii actually used to draw, clamped to what `rect` can hold.
    /// A top+bottom radius taller than the notch, or wider than half of it,
    /// makes the corner curves cross each other and the shape collapses into
    /// a blob - so the drawn values are capped even if the stored ones are larger.
    private func resolvedRadii(in rect: CGRect) -> (top: CGFloat, bottom: CGFloat) {
        let widthBudget = max(0, rect.width / 2)
        let heightBudget = max(0, rect.height)

        var top = max(0, min(topCornerRadius, widthBudget, heightBudget))
        var bottom = max(0, min(bottomCornerRadius, widthBudget, heightBudget))

        // top and bottom curves share the vertical run and half the width.
        let overflow = (top + bottom) - min(widthBudget, heightBudget)
        if overflow > 0 {
            let total = top + bottom
            if total > 0 {
                top -= overflow * (top / total)
                bottom -= overflow * (bottom / total)
            }
        }

        return (max(0, top), max(0, bottom))
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let (topCornerRadius, bottomCornerRadius) = resolvedRadii(in: rect)

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY + topCornerRadius
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius + bottomCornerRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius - bottomCornerRadius,
                y: rect.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY + topCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        return path
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
