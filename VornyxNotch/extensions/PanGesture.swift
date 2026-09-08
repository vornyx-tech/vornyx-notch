//
//  PanGesture.swift
//  VornyxNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(direction: direction, threshold: threshold, action: action) 
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
            private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let raw = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}

// MARK: - Horizontal swipe

extension View {
    /// A two-finger horizontal swipe. Driven purely by scroll events, so unlike
    /// `panGesture` it sits behind buttons without swallowing their taps -
    /// which matters in the notch header, where the free space between the
    /// icons is the natural place to swipe.
    func horizontalSwipe(
        threshold: CGFloat = 30,
        action: @escaping (PanDirection) -> Void
    ) -> some View {
        background(HorizontalSwipeMonitor(threshold: threshold, action: action))
    }
}

private struct HorizontalSwipeMonitor: NSViewRepresentable {
    let threshold: CGFloat
    let action: (PanDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(threshold: threshold, action: action)
    }

    @MainActor final class Coordinator: NSObject {
        private let threshold: CGFloat
        var action: (PanDirection) -> Void
        private var monitor: Any?
        private weak var hostView: NSView?
        private var accumulated: CGFloat = 0
        /// One page per gesture: latched until the fingers lift.
        private var fired = false
        private var idleTask: Task<Void, Never>?

        init(threshold: CGFloat, action: @escaping (PanDirection) -> Void) {
            self.threshold = threshold
            self.action = action
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            hostView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        /// True when the pointer is over the strip this gesture belongs to.
        ///
        /// The monitor sees every scroll in the window, so without this a
        /// sideways scroll inside the notch content - the clipboard row, for
        /// instance - would page the tabs at the same time as scrolling itself.
        private func pointerIsOverHost(_ event: NSEvent) -> Bool {
            guard let hostView, hostView.window != nil else { return false }
            let frameInWindow = hostView.convert(hostView.bounds, to: nil)
            return frameInWindow.contains(event.locationInWindow)
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            idleTask?.cancel()
            idleTask = nil
            reset()
        }

        private func reset() {
            accumulated = 0
            fired = false
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                reset()
                return
            }

            guard pointerIsOverHost(event) else {
                reset()
                return
            }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            // Ignore anything that is mostly a vertical scroll: the notch already
            // uses up/down swipes to open and close.
            guard abs(dx) >= 1.5 * abs(dy) else { return }

            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            accumulated += dx * scale

            // Restart the gesture if it idles, so a second flick pages again.
            idleTask?.cancel()
            idleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.reset()
            }

            guard !fired, abs(accumulated) >= threshold else { return }
            fired = true
            // Natural scrolling: swiping content left reveals the page to its right.
            action(accumulated < 0 ? .right : .left)
        }
    }
}
