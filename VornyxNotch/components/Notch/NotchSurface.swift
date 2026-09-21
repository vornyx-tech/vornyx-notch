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
    /// Tinted glass with Liquid Glass on, a faint white wash and hairline
    /// border with it off.
    ///
    /// - Parameters:
    ///   - fill: The white wash's opacity when glass is off.
    ///   - stroke: The border's opacity when glass is off.
    ///   - tint: The fill when glass is off, the glass's tint when on.
    ///   - glassTint: The glass's tint alone, for hover, copied and drop states.
    ///   - interactive: Glass that answers the pointer with its own highlight.
    ///   - frosted: Regular glass rather than clear, and untinted.
    func notchSurface<S: InsettableShape>(
        _ shape: S,
        fill: Double = 0.05,
        stroke: Double = 0.07,
        tint: Color? = nil,
        glassTint: Color? = nil,
        interactive: Bool = false,
        frosted: Bool = false
    ) -> some View {
        modifier(NotchSurface(
            shape: shape, fill: fill, stroke: stroke, tint: tint, glassTint: glassTint,
            interactive: interactive, frosted: frosted))
    }
}

/// Whether the open notch is drawn as Liquid Glass: the setting, on a system
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
    let interactive: Bool
    let frosted: Bool

    @Default(.liquidGlassNotch) private var liquidGlass

    /// How dark untinted glass is: enough to hold white text over a bright
    /// window behind the notch.
    private static var darkening: Double { 0.20 }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let tinted = frosted
            ? Glass.regular.tint(glassTint ?? tint ?? .white.opacity(0.04))
            : Glass.clear.tint(glassTint ?? tint ?? .black.opacity(Self.darkening))
        return interactive ? tinted.interactive() : tinted
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), liquidGlass {
            content
                .glassEffect(glass, in: shape)
                // Glass takes no part in hit testing.
                .contentShape(shape)
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
