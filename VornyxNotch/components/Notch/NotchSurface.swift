//
//  NotchSurface.swift
//  VornyxNotch
//
//  What the panels, cards and buttons inside the open notch are made of.
//

import Defaults
import SwiftUI

extension View {
    /// The surface a panel, card or button sits on inside the open notch.
    ///
    /// With Liquid Glass on, it is glass of its own - glass inside glass. The
    /// regular, frosted variant, tinted dark: the notch behind it is the clear
    /// variant, and clear on clear would leave nothing for white text to stand
    /// out against. With Liquid Glass off, it is exactly the faint white wash
    /// and hairline border these surfaces always had, so turning the setting
    /// off gives back the old look to the pixel.
    ///
    /// - Parameters:
    ///   - fill: The white wash's opacity when glass is off.
    ///   - stroke: The border's opacity when glass is off.
    ///   - tint: A colour for the surface - a primary button, a message bubble.
    ///     Used as the fill when glass is off, and as the glass's tint when on
    ///     unless `glassTint` says otherwise.
    ///   - glassTint: The glass's tint alone, for states that the white wash
    ///     showed by getting brighter - hovered, copied, a drop over it - and
    ///     that glass has to show by colour instead.
    func notchSurface<S: InsettableShape>(
        _ shape: S,
        fill: Double = 0.05,
        stroke: Double = 0.07,
        tint: Color? = nil,
        glassTint: Color? = nil
    ) -> some View {
        modifier(NotchSurface(shape: shape, fill: fill, stroke: stroke, tint: tint, glassTint: glassTint))
    }
}

/// Whether the open notch is drawn as Liquid Glass - the setting, on a system
/// that has it.
enum NotchGlass {
    static var isActive: Bool {
        guard Defaults[.liquidGlassNotch] else { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

private struct NotchSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Double
    let stroke: Double
    let tint: Color?
    let glassTint: Color?

    @Default(.liquidGlassNotch) private var liquidGlass

    /// How dark untinted glass is. Enough to hold white text over a bright
    /// window behind the notch without turning the glass grey.
    private static var darkening: Double { 0.28 }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), liquidGlass {
            content
                .glassEffect(.regular.tint(glassTint ?? tint ?? .black.opacity(Self.darkening)), in: shape)
        } else {
            content
                .background(
                    shape
                        .fill(tint ?? .white.opacity(fill))
                        .overlay(shape.strokeBorder(.white.opacity(stroke), lineWidth: 1))
                )
        }
    }
}
