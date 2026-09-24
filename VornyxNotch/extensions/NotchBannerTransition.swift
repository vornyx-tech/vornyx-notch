//
//  NotchBannerTransition.swift
//  VornyxNotch
//
//  How a banner comes and goes in the closed notch.
//
//  Values after DynamicNotch's notchExpanded / notchCompact transitions and
//  its balanced animation preset, by Evgeniy Petrukovich (GPL-3.0),
//  https://github.com/jackson-storm/dynamicnotch
//

import SwiftUI

/// Blur, fade and a squash towards the camera - the content condenses out of
/// the notch rather than fading in on top of it.
private struct NotchBannerModifier: ViewModifier {
    var blur: CGFloat = 0
    var opacity: Double = 1
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .scaleEffect(x: scaleX, y: scaleY, anchor: anchor)
    }
}

extension AnyTransition {
    /// A banner hanging under the camera: grows down from the top.
    static var notchDropDown: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: NotchBannerModifier(blur: 20, opacity: 0, scaleX: 0.6, scaleY: 0.2, anchor: .top),
                identity: NotchBannerModifier(anchor: .top)),
            removal: .modifier(
                active: NotchBannerModifier(blur: 20, opacity: 0, scaleX: 0.4, scaleY: 0.2, anchor: .top),
                identity: NotchBannerModifier(anchor: .top)))
    }

    /// A banner either side of the camera: condenses from the middle.
    static var notchInline: AnyTransition {
        .modifier(
            active: NotchBannerModifier(blur: 20, opacity: 0, scaleX: 0.4, scaleY: 0.2, anchor: .center),
            identity: NotchBannerModifier(anchor: .center))
    }
}

extension Animation {
    /// The notch growing into a banner and back.
    static let notchBanner = Animation.spring(response: 0.45, dampingFraction: 0.8, blendDuration: 0.18)
}
