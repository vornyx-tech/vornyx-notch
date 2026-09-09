//
//  ClipboardManager.swift
//  VornyxNotch
//

import AppKit
import Combine
import Defaults
import Foundation
import UniformTypeIdentifiers

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    /// Bundle id of whatever was frontmost when this was copied, for the icon.
    let sourceBundleID: String?
    /// File name of this entry's PNG in the image store, for a screenshot or
    /// any other copied image. Nil for text - and nil for history written
    /// before images were kept, which decodes fine because it is optional.
    var imageFileName: String?
    /// Pixel dimensions, so a card can label the image without opening it.
    var imageWidth: Int?
    var imageHeight: Int?

    var isImage: Bool { imageFileName != nil }

    var preview: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// What the entry looks like, so a card can label itself.
    enum Kind {
        case image
        case link(String)
        case code
        case number
        case text
    }

    var kind: Kind {
        if isImage { return .image }
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
        sweepOrphanedImages()

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

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(text)
            return
        }

        // Screenshots and other copied images. Checked after text on purpose:
        // copying from a rich editor puts both on the pasteboard, and the text
        // is what you meant.
        if let image = Self.imageOnPasteboard(pasteboard) {
            add(image)
        }
    }

    /// PNG data for whatever image is on the pasteboard, if any.
    ///
    /// A screenshot arrives as TIFF, an image dragged from a browser as PNG,
    /// and neither carries a string - which is why the clipboard used to ignore
    /// both. Everything is normalised to PNG so the store holds one format.
    private static func imageOnPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        guard pasteboard.canReadItem(withDataConformingToTypes: [
            UTType.png.identifier, UTType.tiff.identifier,
        ]) else { return nil }

        guard let image = NSImage(pasteboard: pasteboard), image.size != .zero else {
            return nil
        }
        return image
    }

    private func add(_ text: String) {
        // A repeat copy moves the existing entry to the top instead of stacking.
        // Text only: see `add(_ image:)`.
        items.removeAll { !$0.isImage && $0.text == text }
        insert(
            ClipboardItem(
                id: UUID(),
                text: text,
                date: .now,
                sourceBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            )
        )
    }

    /// Puts an entry at the top and trims the history to the user's limit,
    /// taking any images that fall off the end with it.
    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)

        let limit = max(1, Defaults[.clipboardHistoryLimit])
        if items.count > limit {
            for dropped in items.suffix(items.count - limit) { discardImage(of: dropped) }
            items.removeLast(items.count - limit)
        }

        save()
    }

    /// Files a copied image. Unlike text, images are never de-duplicated: two
    /// screenshots of the same window are not the same copy, and comparing the
    /// pixels of every entry on every copy would cost more than it saves.
    private func add(_ image: NSImage) {
        guard let png = Self.pngData(from: image) else { return }

        let fileName = "\(UUID().uuidString).png"
        do {
            try png.write(to: imageStore.appendingPathComponent(fileName), options: .atomic)
        } catch {
            NSLog("Clipboard: could not store copied image: \(error.localizedDescription)")
            return
        }

        let pixels = Self.pixelSize(of: image)
        insert(
            ClipboardItem(
                id: UUID(),
                text: "",
                date: .now,
                sourceBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                imageFileName: fileName,
                imageWidth: pixels.map(\.width),
                imageHeight: pixels.map(\.height)
            )
        )
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// The image's real pixel dimensions, which are not its `size` on a Retina
    /// display - `size` is in points, and a screenshot is twice that.
    private static func pixelSize(of image: NSImage) -> (width: Int, height: Int)? {
        guard let rep = image.representations.first else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    // MARK: - Image store

    /// Images live as files beside the history rather than inside it: the
    /// history is JSON, and a base64 screenshot in it would be megabytes
    /// rewritten on every single copy.
    private var imageStore: URL {
        let directory = storeDirectory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFileName.map { imageStore.appendingPathComponent($0) }
    }

    /// Loaded images, so scrolling the row does not re-read PNGs from disk.
    private let imageCache = NSCache<NSString, NSImage>()

    func image(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        if let cached = imageCache.object(forKey: fileName as NSString) { return cached }
        guard let url = imageURL(for: item), let image = NSImage(contentsOf: url) else {
            return nil
        }
        imageCache.setObject(image, forKey: fileName as NSString)
        return image
    }

    /// Deletes the file behind an entry. Called wherever an entry leaves the
    /// history, or the store grows without bound.
    private func discardImage(of item: ClipboardItem) {
        guard let fileName = item.imageFileName else { return }
        imageCache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: imageStore.appendingPathComponent(fileName))
    }

    // MARK: - Actions

    func copy(_ item: ClipboardItem) {
        isWritingOurselves = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = image(for: item) {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setString(item.text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount

        // Move it back to the top so the most recently used is first.
        if let index = items.firstIndex(of: item), index != 0 {
            items.remove(at: index)
            items.insert(item, at: 0)
            save()
        }
    }

    func remove(_ item: ClipboardItem) {
        discardImage(of: item)
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        for item in items { discardImage(of: item) }
        items.removeAll()
        save()
    }

    // MARK: - Persistence

    private var storeDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (support ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("VornyxNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var storeURL: URL {
        storeDirectory.appendingPathComponent("clipboard.json")
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
        try? FileManager.default.removeItem(at: imageStore)
        imageCache.removeAllObjects()
    }

    /// Deletes image files no entry points at any more.
    ///
    /// Nothing should leave one behind - every path that drops an entry deletes
    /// its file - but a crash between writing the PNG and saving the history
    /// would, and those files are invisible to the user and never reclaimed.
    private func sweepOrphanedImages() {
        let live = Set(items.compactMap(\.imageFileName))
        let onDisk = (try? FileManager.default.contentsOfDirectory(
            at: imageStore, includingPropertiesForKeys: nil
        )) ?? []

        for url in onDisk where !live.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Pasting

extension ClipboardManager {
    /// Send Command-V to whatever app is frontmost.
    ///
    /// Copying is only half of what "pick this one" means: without this you
    /// still have to press Command-V yourself, which is the keystroke the
    /// shortcut was supposed to save. Posting a key event into another app is
    /// exactly what Accessibility gates, so this asks - once - and quietly does
    /// nothing but copy if the answer is no.
    ///
    /// The notch is a non-activating panel, so the app you were in never
    /// stopped being the frontmost one and the keystroke lands where you left
    /// the cursor.
    @MainActor
    static func pasteIntoFrontmostApp() async -> Bool {
        guard await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
        else { return false }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let v: CGKeyCode = 9

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
