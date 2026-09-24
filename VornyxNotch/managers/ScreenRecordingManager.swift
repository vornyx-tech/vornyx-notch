//
//  ScreenRecordingManager.swift
//  VornyxNotch
//
//  Whether the screen is being recorded or shared, and since when.
//
//  Detection after DynamicNotch's SystemScreenRecordingMonitor by Evgeniy
//  Petrukovich (GPL-3.0), https://github.com/jackson-storm/dynamicnotch
//

import AppKit
import Defaults
import Foundation

@_silgen_name("CGSIsScreenWatcherPresent")
private func CGSIsScreenWatcherPresent() -> Bool

@_silgen_name("CGSRegisterNotifyProc")
private func CGSRegisterNotifyProc(
    _ callback: (@convention(c) (Int32, Int32, Int32, UnsafeMutableRawPointer?) -> Void)?,
    _ event: Int32,
    _ context: UnsafeMutableRawPointer?
) -> Bool

/// The window server knows when anything is watching the screen - the
/// screenshot toolbar's recording, QuickTime, a call sharing the screen - and
/// says so through two private notifications, 1502 and 1503. A two-second
/// poll backs them up.
@MainActor
final class ScreenRecordingManager: ObservableObject {
    static let shared = ScreenRecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?

    private var registered = false
    private var poll: Timer?
    /// No banner for a recording already running at launch.
    private var known = false

    private init() {}

    func start() {
        guard poll == nil else { return }
        if !registered {
            for event: Int32 in [1502, 1503] {
                registered = CGSRegisterNotifyProc({ _, _, _, _ in
                    Task { @MainActor in ScreenRecordingManager.shared.check() }
                }, event, nil) || registered
            }
        }
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in ScreenRecordingManager.shared.check() }
        }
        check()
    }

    func check() {
        let recording = CGSIsScreenWatcherPresent()
        guard recording != isRecording || !known else { return }
        let changed = known
        isRecording = recording
        startedAt = recording ? Date() : nil
        known = true
        if changed, recording, Defaults[.screenRecordingLiveActivity] {
            VornyxViewCoordinator.shared.announceScreenRecording()
        }
    }

    /// Ends a recording made with the screenshot toolbar, the way pressing
    /// its stop button does. The helper sends it, since a sandboxed app may
    /// not signal another process.
    func stop() {
        XPCHelperClient.shared.stopScreenCapture()
    }
}
