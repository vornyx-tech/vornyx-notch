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

/// A countdown you can see from the closed notch.
///
/// Deliberately the notch's own timer rather than a mirror of the Clock app's.
/// Reading a running system timer is possible, but every route to it - the
/// `mobiletimerd` preferences, scraping the unified log, driving the Clock
/// through Accessibility - needs to reach outside the app container, and this
/// app is sandboxed. See the note in Settings.
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
    /// Seconds left. Kept to the fraction so the ring moves smoothly; every
    /// label rounds it up, so a timer reads "1:00" for the whole first second
    /// rather than flicking to 0:59 immediately.
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0

    /// What the last countdown was set to, so the same one is one tap away.
    @Default(.timerLastDuration) var lastDuration: Double

    private var ticker: AnyCancellable?
    /// The wall-clock instant the countdown ends, rather than a running
    /// subtraction: a timer that counts its own ticks drifts, and loses time
    /// outright when the Mac sleeps mid-countdown.
    private var deadline: Date?

    private init() {}

    // MARK: - Reading

    var isActive: Bool { state == .running || state == .paused }

    /// 0 at the start, 1 at the end.
    var progress: Double {
        guard total > 0 else { return 0 }
        return ((total - remaining) / total).clamped(to: 0...1)
    }

    /// Seconds as a clock reads them: `1:05`, or `1:02:30` once there is an
    /// hour to show. Rounded up, so it only says zero when it is over.
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
        ticker?.cancel()
        ticker = nil
        deadline = nil
        state = .idle
        remaining = 0
        total = 0
    }

    /// Add - or take away - time without disturbing the countdown.
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
        // Four times a second: enough for the ring to move without stepping,
        // and far cheaper than a display link for something this slow.
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
        if Defaults[.timerSound] {
            AudioPlayer().play(fileName: "notification", fileExtension: "m4a")
        }
        announce(force: true)

        // The banner would otherwise sit there for good: `finished` is a state
        // with nothing counting down to end it.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, self.state == .finished else { return }
            self.reset()
        }
    }

    /// Show the countdown in the closed notch.
    private func announce(force: Bool = false) {
        guard force || Defaults[.timerLiveActivity] else { return }
        VornyxViewCoordinator.shared.announceTimer()
    }
}
