//
//  NotchContentRegions.swift
//  VornyxNotch
//
//  What a page tells the notch: which parts of it scroll, and how much room it
//  wants.
//

import SwiftUI

// MARK: - Regions that scroll

private struct ScrollableNotchHoverKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    /// Where `scrollableNotchContent()` reports to. Set by the open notch.
    var notchScrollableHover: Binding<Bool>? {
        get { self[ScrollableNotchHoverKey.self] }
        set { self[ScrollableNotchHoverKey.self] = newValue }
    }
}

private struct ScrollableNotchContent: ViewModifier {
    @Environment(\.notchScrollableHover) private var hover

    func body(content: Content) -> some View {
        content.onHover { hover?.wrappedValue = $0 }
    }
}

extension View {
    /// Marks a view that does its own scrolling, so the notch's close gesture
    /// leaves it alone. Closing and scrolling are both up-swipes, told apart
    /// only by what is under the pointer.
    func scrollableNotchContent() -> some View {
        modifier(ScrollableNotchContent())
    }
}

// MARK: - Pages asking for more room

/// How tall a scrolling page's content is, and how much of it is on screen.
struct NotchContentFit: Equatable {
    var content: CGFloat = 0
    var visible: CGFloat = 0

    /// Points the page is short by; negative when it has room to spare.
    var shortfall: CGFloat { content - visible }
}

struct NotchContentFitKey: PreferenceKey {
    static let defaultValue = NotchContentFit()

    /// The neediest page wins.
    static func reduce(value: inout NotchContentFit, nextValue: () -> NotchContentFit) {
        let next = nextValue()
        if next.shortfall > value.shortfall { value = next }
    }
}

extension View {
    /// Reports this view's laid-out height, and each change to it.
    func measuringHeight(into height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, new in
                        height.wrappedValue = new
                    }
            }
        )
    }
}
