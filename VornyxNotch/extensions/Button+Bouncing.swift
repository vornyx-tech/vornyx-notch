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
                RoundedRectangle(cornerRadius: 10)
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

// MARK: - Jelly hover

extension View {
    /// Leans and stretches towards the pointer while it is over the view, and
    /// wobbles back into shape when it leaves - the way Liquid Glass panels
    /// follow the Apple Pencil hovering over them.
    func hoverJelly(pull: CGFloat = 3, stretch: CGFloat = 0.025) -> some View {
        modifier(HoverJelly(maxPull: pull, maxStretch: stretch))
    }
}

private struct HoverJelly: ViewModifier {
    let maxPull: CGFloat
    let maxStretch: CGFloat

    /// Where the pointer is, from the middle: -1 to 1 across each axis.
    @State private var lean: CGSize = .zero
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .modifier(JellyEffect(lean: lean, maxPull: maxPull, maxStretch: maxStretch))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    guard size.width > 0, size.height > 0 else { return }
                    let target = CGSize(
                        width: ((point.x - size.width / 2) / (size.width / 2)).clamped(to: -1...1),
                        height: ((point.y - size.height / 2) / (size.height / 2)).clamped(to: -1...1))
                    // Follows softly, a beat behind the pointer.
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        lean = target
                    }
                case .ended:
                    // Let go: eases back past rest once or twice and settles.
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.5)) {
                        lean = .zero
                    }
                }
            }
    }
}

/// Moves the view towards `lean` and stretches it along that direction,
/// squashing it a little across - one transform about the view's middle,
/// animatable, so the springs above carry it through every wobble.
private struct JellyEffect: GeometryEffect {
    var lean: CGSize
    let maxPull: CGFloat
    let maxStretch: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(lean.width, lean.height) }
        set { lean = CGSize(width: newValue.first, height: newValue.second) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let amount = min(1, hypot(lean.width, lean.height))
        guard amount > 0.001 else { return ProjectionTransform() }
        let angle = atan2(lean.height, lean.width)
        let along = 1 + maxStretch * amount
        let across = 1 - maxStretch * 0.5 * amount
        let transform = CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
            .concatenating(CGAffineTransform(rotationAngle: -angle))
            .concatenating(CGAffineTransform(scaleX: along, y: across))
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(
                translationX: size.width / 2 + lean.width * maxPull,
                y: size.height / 2 + lean.height * maxPull))
        return ProjectionTransform(transform)
    }
}
