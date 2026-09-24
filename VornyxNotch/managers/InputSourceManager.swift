//
//  InputSourceManager.swift
//  VornyxNotch
//
//  The keyboard layout, and a word in the notch as it changes.
//

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

    private init() {}

    func start() {
        guard observer == nil else { return }
        current = Self.read()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in InputSourceManager.shared.notified() }
        }
        // For switches the notification never announces. Reading the current
        // source costs next to nothing.
        backstop = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in InputSourceManager.shared.changed() }
        }
    }

    /// The notification can come a moment before the switch has landed, and
    /// a read then finds the old layout and sees no change - which is why it
    /// only worked some of the time. Read again over the next half second.
    private func notified() {
        settle?.cancel()
        settle = Task { @MainActor [weak self] in
            for delay in [0, 100, 300, 600] {
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
        if Defaults[.inputSourceLiveActivity] {
            VornyxViewCoordinator.shared.announceInputSource()
        }
        return true
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
