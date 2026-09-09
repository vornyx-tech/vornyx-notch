//
//  Button+Bouncing.swift
//  VornyxNotch
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//
import SwiftUI
import Defaults

struct BouncingButtonStyle: ButtonStyle {
    let vm: VornyxViewModel
    @State private var isPressed = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Defaults[.cornerRadiusScaling] ? 10 : MusicPlayerImageSizes.cornerRadiusInset.closed)
                    .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                    .strokeBorder(.white.opacity(0.04), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .onChange(of: configuration.isPressed) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.3, blendDuration: 0.3)) {
                    isPressed.toggle()
                }
            }
    }
}

extension Button {
    func bouncingStyle(vm: VornyxViewModel) -> some View {
        self.buttonStyle(BouncingButtonStyle(vm: vm))
    }
}

/// A tile that answers the pointer: it lifts when you hover it, squashes when
/// you press, and springs back past its resting size when you let go.
///
/// The two halves of the press are deliberately different springs. Going down
/// is quick and tightly damped, because a press has to feel like it landed the
/// instant you click. Coming back up is slow and loosely damped, so it
/// overshoots and settles - that overshoot is the whole trampoline feel, and a
/// well-damped spring on the way up would just look like the tile deflating.
///
/// Code-only tuning, like `AlbumArtStyle`: change the numbers and rebuild.
struct SpringyTileButtonStyle: ButtonStyle {
    @State private var hovering = false

    /// How far the tile grows under the pointer. Small on purpose: the shortcut
    /// tiles sit 6pt apart in a grid, and anything punchier has them colliding.
    /// Scale is proportional, so the bigger the tile the less of it a caller
    /// wants - a clipboard card is nine times the width and asks for a third
    /// of this.
    var hoverScale: CGFloat = 1.07
    /// How far it squashes while held.
    var pressScale: CGFloat = 0.9
    /// Lightening under the pointer, on top of the scale. The tiles are a faint
    /// white wash on black, so a few percent is plainly visible.
    var hoverBrightness: Double = 0.07

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(hovering && !configuration.isPressed ? hoverBrightness : 0)
            .scaleEffect(scale(for: configuration))
            .animation(
                configuration.isPressed
                    ? .spring(response: 0.13, dampingFraction: 0.9)
                    : .spring(response: 0.34, dampingFraction: 0.42),
                value: configuration.isPressed
            )
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }

    private func scale(for configuration: Configuration) -> CGFloat {
        if configuration.isPressed { return pressScale }
        return hovering ? hoverScale : 1
    }
}

extension View {
    /// See `SpringyTileButtonStyle`. The defaults are tuned for the dashboard's
    /// shortcut tiles; bigger tiles pass smaller numbers.
    func springyTile(
        hoverScale: CGFloat = 1.07,
        pressScale: CGFloat = 0.9,
        hoverBrightness: Double = 0.07
    ) -> some View {
        buttonStyle(
            SpringyTileButtonStyle(
                hoverScale: hoverScale,
                pressScale: pressScale,
                hoverBrightness: hoverBrightness
            )
        )
    }
}
