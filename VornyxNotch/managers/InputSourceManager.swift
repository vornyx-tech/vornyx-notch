//
//  InputSourceManager.swift
//  VornyxNotch
//
//  The keyboard layout, and a word in the notch as it changes.
//

import AppKit
import Carbon
import Defaults
import Foundation

/// A keyboard layout as the notch shows it.
struct InputSource: Equatable {
    let name: String
    /// The flag of the country the language is mostly spoken in, if any.
    let flag: String?
    /// `UK`, `EN` - the language's own code, for where there is little room.
    let code: String
}

/// Hears the system change layouts - by the menu, by Control-Space, by
/// Caps Lock - through the distributed notification Text Input Sources posts,
/// which reaches a sandboxed app.
@MainActor
final class InputSourceManager: ObservableObject {
    static let shared = InputSourceManager()

    @Published private(set) var current: InputSource?

    private var observer: NSObjectProtocol?
    private var backstop: Timer?
    private var settle: Task<Void, Never>?
    private var confirm: Task<Void, Never>?
    private var appObserver: NSObjectProtocol?
    /// Switching apps brings each app's own layout with it, when macOS keeps
    /// one per app or document; not something the user did.
    private var quietUntil = Date.distantPast
    /// What the banner last said, so a switch and straight back says nothing.
    private var announced: InputSource?

    private init() {}

    func start() {
        guard observer == nil else { return }
        current = Self.read()
        announced = current
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in InputSourceManager.shared.quietUntil = Date().addingTimeInterval(1) }
        }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in InputSourceManager.shared.notified() }
        }
        // For switches the notification never announces. Reading the current
        // source costs next to nothing.
        backstop = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in InputSourceManager.shared.changed() }
        }
    }

    /// The notification can come a moment before the switch has landed, and
    /// a read then finds the old layout and sees no change - which is why it
    /// only worked some of the time. Read again over the next half second.
    private func notified() {
        settle?.cancel()
        settle = Task { @MainActor [weak self] in
            for delay in [0, 50, 150, 300] {
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                guard !Task.isCancelled else { return }
                if self?.changed() == true { return }
            }
        }
    }

    /// True when the layout had changed.
    @discardableResult
    private func changed() -> Bool {
        guard let source = Self.read(), source != current else { return false }
        current = source
        confirmAnnouncement(of: source)
        return true
    }

    /// The layout macOS changes on its own - Latin for a password field,
    /// each app's or document's own as the cursor lands in it - is a real
    /// change, just not the user's, and was putting the banner up whenever
    /// the cursor moved. Only one that holds for a moment, away from a
    /// password field and an app switch, and differs from the last one
    /// shown, gets a banner.
    private func confirmAnnouncement(of source: InputSource) {
        confirm?.cancel()
        confirm = Task { @MainActor [weak self] in
            // Long enough for a password field's flip to Latin and back, and
            // no longer: every millisecond here is felt as lag.
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            guard Defaults[.inputSourceLiveActivity],
                  Self.read() == source, source != self.announced,
                  !IsSecureEventInputEnabled(),
                  Date() >= self.quietUntil
            else {
                // Record it anyway once it has settled, so returning to the
                // last announced one later still reads as a change.
                if Self.read() == source, !IsSecureEventInputEnabled() { self.announced = source }
                return
            }
            self.announced = source
            VornyxViewCoordinator.shared.announceInputSource()
        }
    }

    static func read() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        func property(_ key: CFString) -> AnyObject? {
            guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        }
        let name = property(kTISPropertyLocalizedName) as? String ?? "Keyboard"
        let language = (property(kTISPropertyInputSourceLanguages) as? [String])?.first ?? ""
        return InputSource(name: name, flag: flag(for: language), code: String(language.prefix(2)).uppercased())
    }

    /// `uk` → 🇺🇦, `en` → 🇺🇸: the region of the language's most likely
    /// full form, turned into regional indicator letters.
    static func flag(for language: String) -> String? {
        guard !language.isEmpty,
              let region = Locale.Language(identifier: language).maximalIdentifier
                .split(separator: "-").last.map(String.init),
              region.count == 2, region.allSatisfy(\.isLetter)
        else { return nil }
        return region.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }
            .map(String.init).joined()
    }
}
