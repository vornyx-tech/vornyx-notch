//
//  ClipboardManager.swift
//  VornyxNotch
//

import AppKit
import Combine
import Defaults
import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    /// Bundle id of whatever was frontmost when this was copied, for the icon.
    let sourceBundleID: String?

    var preview: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// What the entry looks like, so a card can label itself.
    enum Kind {
        case link(String)
        case code
        case number
        case text
    }

    var kind: Kind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().hasPrefix("http"),
           let url = URL(string: trimmed), let host = url.host() {
            return .link(host)
        }
        if !trimmed.isEmpty, trimmed.count < 40,
           trimmed.allSatisfy({ $0.isNumber || "+-() .".contains($0) }) {
            return .number
        }
        let codeMarkers = ["{", "}", "();", "=>", "func ", "def ", "const ", "import ", "</"]
        if codeMarkers.contains(where: trimmed.contains) {
            return .code
        }
        return .text
    }

    var lineCount: Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}

/// Watches the general pasteboard and keeps a short history of text copies.
///
/// AppKit gives no change notification for the pasteboard, so this polls
/// `changeCount` - the same approach every clipboard manager on macOS uses.
/// Polling only runs while the feature is switched on.
@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipboardItem] = []

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    /// Set while we write to the pasteboard ourselves, so re-copying an item
    /// does not push a duplicate back onto the history.
    private var isWritingOurselves = false

    private init() {
        load()

        cancellable = Defaults.publisher(.clipboardEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    change.newValue ? self?.start() : self?.stop()
                }
            }

        if Defaults[.clipboardEnabled] { start() }
    }

    // MARK: - Watching

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard !isWritingOurselves else {
            isWritingOurselves = false
            return
        }

        // Respect the marker apps like password managers set on secrets.
        if pasteboard.types?.contains(.init("org.nspasteboard.ConcealedType")) == true { return }

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        add(text)
    }

    private func add(_ text: String) {
        // A repeat copy moves the existing entry to the top instead of stacking.
        items.removeAll { $0.text == text }
        items.insert(
            ClipboardItem(
                id: UUID(),
                text: text,
                date: .now,
                sourceBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            ),
            at: 0
        )

        let limit = max(1, Defaults[.clipboardHistoryLimit])
        if items.count > limit { items.removeLast(items.count - limit) }

        save()
    }

    // MARK: - Actions

    func copy(_ item: ClipboardItem) {
        isWritingOurselves = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount

        // Move it back to the top so the most recently used is first.
        if let index = items.firstIndex(of: item), index != 0 {
            items.remove(at: index)
            items.insert(item, at: 0)
            save()
        }
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    // MARK: - Persistence

    private var storeURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (support ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("VornyxNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("clipboard.json")
    }

    private func save() {
        guard Defaults[.clipboardPersistHistory] else { return }
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func load() {
        guard Defaults[.clipboardPersistHistory],
              let data = try? Data(contentsOf: storeURL),
              let stored = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return }
        items = stored
    }

    func forgetStoredHistory() {
        try? FileManager.default.removeItem(at: storeURL)
    }
}
