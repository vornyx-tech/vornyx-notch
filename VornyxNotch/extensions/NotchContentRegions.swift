//
//  NotchContentRegions.swift
//  VornyxNotch
//
//  What the open notch's pages tell the notch about themselves: which parts of
//  a page scroll, and how much room a page wishes it had.
//

import SwiftUI

// MARK: - Regions that scroll

private struct ScrollableNotchHoverKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    /// Where `scrollableNotchContent()` reports to. The open notch sets this;
    /// pages never read it directly.
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
    /// leaves it alone.
    ///
    /// Closing is an up-swipe and scrolling is an up-swipe, so the two can only
    /// be told apart by what is under the pointer. Handing the whole page to
    /// scrolling was too broad: the month grid, the shortcut buttons and the
    /// player have nothing to scroll, and a swipe over them should close the
    /// notch exactly like a swipe over the header. So the claim is opt-in -
    /// only the handful of views that really scroll take it.
    func scrollableNotchContent() -> some View {
        modifier(ScrollableNotchContent())
    }
}

// MARK: - Pages asking for more room

/// A scrolling page telling the notch how it is getting on for space: how tall
/// its content is, and how much of that is currently on screen.
struct NotchContentFit: Equatable {
    var content: CGFloat = 0
    var visible: CGFloat = 0

    /// Points the page is short by; negative when it has room to spare.
    var shortfall: CGFloat { content - visible }
}

struct NotchContentFitKey: PreferenceKey {
    static let defaultValue = NotchContentFit()

    /// The neediest page wins. Nothing shows two growing pages at once today,
    /// but growing for the roomiest of them would be the wrong way round.
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
