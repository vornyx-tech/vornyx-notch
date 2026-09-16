//
//  PermissionsRequestView.swift
//  VornyxNotch
//
//  Created by Alexander on 2025-06-23.
//

import AVFoundation
import CoreLocation
import EventKit
import SwiftUI

struct PermissionRequestView: View {
    let icon: Image
    let title: String
    let description: String
    let privacyNote: String?
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 56)
                .foregroundColor(.effectiveAccent)
                .padding(.top, 32)

            Text(title)
                .font(.title)
                .fontWeight(.semibold)

            Text(description)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let privacyNote = privacyNote {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.secondary)
                    Text(privacyNote)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.bottom, 8)
                .padding(.horizontal)
            }

            HStack {
                Button("Not Now") { onSkip() }
                    .buttonStyle(.bordered)
                Button("Allow Access") { onAllow() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Everything, on one screen

/// What the app can ask macOS for, and what each answer buys.
enum PermissionKind: String, CaseIterable, Identifiable {
    case camera
    case calendar
    case reminders
    case accessibility
    case location
    case localNetwork
    case mediaApps
    case systemAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .accessibility: return "Accessibility"
        case .location: return "Location"
        case .localNetwork: return "Local network"
        case .mediaApps: return "Music and Spotify"
        case .systemAudio: return "System audio"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .accessibility: return "hand.raised.fill"
        case .location: return "location.fill"
        case .localNetwork: return "antenna.radiowaves.left.and.right"
        case .mediaApps: return "music.note"
        case .systemAudio: return "waveform"
        }
    }

    /// One line, in terms of what you get - not what the API is called.
    var reason: String {
        switch self {
        case .camera: return "The mirror in the notch. Nothing is recorded or sent."
        case .calendar: return "Your next events on the dashboard."
        case .reminders: return "Reminders beside those events."
        case .accessibility: return "Media and brightness keys, and pasting from the clipboard."
        case .location: return "Local weather. You can name a place in Settings instead."
        case .localNetwork: return "Finding nearby devices for LocalSend."
        case .mediaApps: return "Reading what is playing, and the play, pause and skip buttons."
        case .systemAudio: return "Bars in the notch that move with the music. The screen is never captured."
        }
    }

    /// The pane macOS opens when an answer has to be changed by hand.
    var settingsPane: String? {
        switch self {
        case .camera: return "Privacy_Camera"
        case .calendar: return "Privacy_Calendars"
        case .reminders: return "Privacy_Reminders"
        case .accessibility: return "Privacy_Accessibility"
        case .location: return "Privacy_LocationServices"
        case .localNetwork, .mediaApps, .systemAudio: return nil
        }
    }

    /// macOS asks for these the first time the feature runs. There is no API to
    /// ask ahead of time and none to read the answer back, so the row says so
    /// rather than pretending the app is in charge of it.
    var isAskedOnFirstUse: Bool {
        self == .localNetwork || self == .mediaApps
    }
}

enum PermissionState: Equatable {
    case unknown
    case notAsked
    case granted
    case denied
    case onFirstUse
}

/// Every permission on one screen, each with its reason, before anything is
/// asked.
///
/// They used to arrive one full screen at a time, and macOS's own prompts then
/// turned up later, unexplained, while the app did ordinary things - which is
/// what something malicious looks like. Here the whole list is visible up
/// front, nothing is required, and whatever is skipped just leaves that
/// feature off.
struct PermissionsChecklistView: View {
    /// Nil in Settings, where this is a page rather than a step.
    var onContinue: (() -> Void)?

    @State private var states: [PermissionKind: PermissionState] = [:]
    @State private var asking: PermissionKind?
    @StateObject private var locationAsk = LocationPermissionAsk()

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.effectiveAccent)
                Text("Permissions")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Everything Vornyx Notch can ask macOS for, in one place. Allow what you want - all of it is optional, and anything you skip simply stays off.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 22)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(PermissionKind.allCases) { kind in
                        row(kind)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }

            if let onContinue {
                Button("Continue") { onContinue() }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .task { refresh() }
        // The location answer arrives through the manager's delegate, not from
        // the call that put the prompt up.
        .onChange(of: locationAsk.status) { _, _ in refresh() }
    }

    private func row(_ kind: PermissionKind) -> some View {
        let state = states[kind] ?? .unknown

        return HStack(spacing: 12) {
            Image(systemName: kind.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.effectiveAccent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(kind.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            action(for: kind, state: state)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    @ViewBuilder
    private func action(for kind: PermissionKind, state: PermissionState) -> some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .onFirstUse:
            Text("On first use")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .denied:
            // Once refused, only System Settings can change it back - and a
            // couple of these have no pane of their own to send you to.
            if kind.settingsPane != nil {
                Button("Settings") { openSettings(kind) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Text("Not allowed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .notAsked, .unknown:
            Button(asking == kind ? "..." : "Allow") { ask(kind) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(asking != nil)
        }
    }

    private func refresh() {
        for kind in PermissionKind.allCases where kind.isAskedOnFirstUse {
            states[kind] = .onFirstUse
        }
        if states[.systemAudio] == nil { states[.systemAudio] = .notAsked }
        states[.camera] = Self.state(AVCaptureDevice.authorizationStatus(for: .video))
        states[.calendar] = Self.state(EKEventStore.authorizationStatus(for: .event))
        states[.reminders] = Self.state(EKEventStore.authorizationStatus(for: .reminder))
        // Reading the status does not prompt; only `requestWhenInUseAuthorization` does.
        states[.location] = Self.state(CLLocationManager().authorizationStatus)

        Task {
            let granted = await XPCHelperClient.shared.isAccessibilityAuthorized()
            states[.accessibility] = granted ? .granted : .notAsked
        }
    }

    private func ask(_ kind: PermissionKind) {
        asking = kind
        Task {
            switch kind {
            case .camera:
                _ = await AVCaptureDevice.requestAccess(for: .video)
            case .calendar:
                _ = try? await CalendarService().requestAccess(to: .event)
            case .reminders:
                _ = try? await CalendarService().requestAccess(to: .reminder)
            case .accessibility:
                _ = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            case .location:
                locationAsk.prompt()
            case .systemAudio:
                let allowed = SystemAudioLevels.shared.requestAccess()
                states[.systemAudio] = allowed ? .granted : .denied
            case .localNetwork, .mediaApps:
                break
            }
            asking = nil
            refresh()
        }
    }

    private func openSettings(_ kind: PermissionKind) {
        guard let pane = kind.settingsPane,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private static func state(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        default: return .granted
        }
    }

    private static func state(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        default: return .granted
        }
    }

    private static func state(_ status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        default: return .granted
        }
    }
}

/// Puts up the location prompt and publishes the answer.
///
/// `CLLocationManager` answers through its delegate rather than the call, and
/// it has to stay alive to do it, so the prompt cannot be a free function.
@MainActor
final class LocationPermissionAsk: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func prompt() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let updated = manager.authorizationStatus
        Task { @MainActor in self.status = updated }
    }
}
