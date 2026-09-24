//
//  CountdownManager.swift
//  VornyxNotch
//
//  The notch's own countdown timer.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// A countdown you can see from the closed notch. The app's own timer, not a
/// mirror of the Clock app's: reading that needs to reach outside the sandbox.
@MainActor
final class CountdownManager: ObservableObject {
    static let shared = CountdownManager()

    enum State: Equatable {
        case idle
        case running
        case paused
        /// Reached zero and not yet acknowledged.
        case finished
    }

    @Published private(set) var state: State = .idle
    /// Seconds left, kept to the fraction so the ring moves smoothly. Labels
    /// round it up.
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0

    /// What the last countdown was set to, so the same one is one tap away.
    @Default(.timerLastDuration) var lastDuration: Double

    private var ticker: AnyCancellable?
    /// The sound repeating once a countdown has finished, until Stop.
    private var alarm: Task<Void, Never>?
    /// The wall-clock instant the countdown ends; counting ticks would drift
    /// and lose time across sleep.
    private var deadline: Date?

    private init() {}

    /// The countdown's own colour: the line on the notch's edge, and the
    /// closed notch's icon and ring with it, so the two never disagree.
    static let color: Color = .orange

    // MARK: - Reading

    var isActive: Bool { state == .running || state == .paused }

    /// Running, paused, or just finished: everything the closed notch keeps
    /// the countdown up for. Finished counts, or the banner went after its
    /// three seconds and the notch shrank, then sat idle until the reset.
    var isShowingInNotch: Bool { isActive || state == .finished }

    /// 0 at the start, 1 at the end.
    var progress: Double {
        guard total > 0 else { return 0 }
        return ((total - remaining) / total).clamped(to: 0...1)
    }

    /// Seconds as a clock reads them, rounded up: `1:05`, or `1:02:30`.
    var label: String {
        Self.format(remaining)
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval).rounded(.up))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Driving

    func start(_ duration: TimeInterval) {
        guard duration > 0 else { return }
        total = duration
        remaining = duration
        lastDuration = duration
        deadline = Date().addingTimeInterval(duration)
        state = .running
        startTicking()
        announce()
    }

    func pause() {
        guard state == .running else { return }
        // Freeze what is left; the deadline is rebuilt from it on resume.
        remaining = max(0, deadline?.timeIntervalSinceNow ?? remaining)
        deadline = nil
        state = .paused
        ticker?.cancel()
        announce()
    }

    func resume() {
        guard state == .paused else { return }
        deadline = Date().addingTimeInterval(remaining)
        state = .running
        startTicking()
        announce()
    }

    func toggle() {
        switch state {
        case .running: pause()
        case .paused: resume()
        case .idle, .finished: start(lastDuration)
        }
    }

    func reset() {
        alarm?.cancel()
        alarm = nil
        ticker?.cancel()
        ticker = nil
        deadline = nil
        state = .idle
        remaining = 0
        total = 0
    }

    /// Add or take away time without disturbing the countdown.
    func adjust(by seconds: TimeInterval) {
        switch state {
        case .running:
            guard let deadline else { return }
            let updated = deadline.addingTimeInterval(seconds)
            guard updated > Date() else { return }
            self.deadline = updated
            total = max(total + seconds, updated.timeIntervalSinceNow)
            remaining = updated.timeIntervalSinceNow
        case .paused:
            let updated = max(1, remaining + seconds)
            total = max(total + seconds, updated)
            remaining = updated
        case .idle, .finished:
            start(max(60, lastDuration + seconds))
        }
    }

    private func startTicking() {
        ticker?.cancel()
        // Four times a second is enough for the ring to move without stepping.
        ticker = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard let deadline else { return }
        let left = deadline.timeIntervalSinceNow

        guard left > 0 else {
            remaining = 0
            self.deadline = nil
            ticker?.cancel()
            ticker = nil
            state = .finished
            finish()
            return
        }
        remaining = left
    }

    private func finish() {
        announce(force: true)

        // An alarm, not a notification: it keeps going until Stop. The ten
        // minutes are only the backstop for a countdown nobody came back to;
        // the notch shows it for all of it - see `isShowingInNotch`.
        alarm?.cancel()
        alarm = Task { [weak self] in
            let started = Date()
            while !Task.isCancelled, let self, self.state == .finished {
                // A system sound of its own: notification.m4a is the greeting
                // played on first launch.
                if Defaults[.timerSound] {
                    (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
                }
                if Date().timeIntervalSince(started) > 600 {
                    self.reset()
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Show the countdown in the closed notch.
    private func announce(force: Bool = false) {
        guard force || Defaults[.timerLiveActivity] else { return }
        VornyxViewCoordinator.shared.announceTimer()
    }
}
