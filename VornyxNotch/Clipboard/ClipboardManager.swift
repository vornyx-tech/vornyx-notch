//
//  ClipboardManager.swift
//  VornyxNotch
//

import AppKit
import Combine
import Defaults
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    /// Bundle id of whatever was frontmost when this was copied, for the icon.
    let sourceBundleID: String?
    /// File name of this entry's PNG in the image store. Nil for text, and for
    /// history written before images were kept.
    let imageFileName: String?
    /// Pixel dimensions, so a card can label the image without opening it.
    let imageWidth: Int?
    let imageHeight: Int?
    /// What a card shows, worked out once when the entry is made or read back.
    let summary: Summary

    struct Summary: Equatable {
        let kind: Kind
        /// The start of the text on one line: all a card or its tooltip shows.
        let preview: String
        let lineCount: Int
        let characterCount: Int
    }

    /// What the entry looks like, so a card can label itself.
    enum Kind: Equatable {
        case image
        case link(String)
        case code
        case number
        case text
    }

    var isImage: Bool { imageFileName != nil }
    var kind: Kind { summary.kind }
    var preview: String { summary.preview }
    var lineCount: Int { summary.lineCount }

    init(
        id: UUID = UUID(), text: String, date: Date = .now, sourceBundleID: String?,
        imageFileName: String? = nil, imageWidth: Int? = nil, imageHeight: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.sourceBundleID = sourceBundleID
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        summary = Self.summarize(text, isImage: imageFileName != nil)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, date, sourceBundleID, imageFileName, imageWidth, imageHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            text: try container.decode(String.self, forKey: .text),
            date: try container.decode(Date.self, forKey: .date),
            sourceBundleID: try container.decodeIfPresent(String.self, forKey: .sourceBundleID),
            imageFileName: try container.decodeIfPresent(String.self, forKey: .imageFileName),
            imageWidth: try container.decodeIfPresent(Int.self, forKey: .imageWidth),
            imageHeight: try container.decodeIfPresent(Int.self, forKey: .imageHeight))
    }

    /// How much of a copy is read to describe it: a card shows three lines.
    private static let summaryWindow = 4_000
    private static let previewLength = 300

    private static func summarize(_ text: String, isImage: Bool) -> Summary {
        guard !isImage else {
            return Summary(kind: .image, preview: "", lineCount: 0, characterCount: 0)
        }
        let head = text.prefix(summaryWindow)
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)

        return Summary(
            kind: kind(of: trimmed, isWholeCopy: head.endIndex == text.endIndex),
            preview: String(trimmed.prefix(previewLength))
                .replacingOccurrences(of: "\n", with: " "),
            // Counted in bytes: a newline is one byte in UTF-8.
            lineCount: text.utf8.reduce(into: 1) { count, byte in
                if byte == 0x0A { count += 1 }
            },
            characterCount: text.count)
    }

    private static func kind(of trimmed: String, isWholeCopy: Bool) -> Kind {
        // A link or a number is the entire copy.
        if isWholeCopy {
            if trimmed.lowercased().hasPrefix("http"),
               let url = URL(string: trimmed), let host = url.host() {
                return .link(host)
            }
            if !trimmed.isEmpty, trimmed.count < 40,
               trimmed.allSatisfy({ $0.isNumber || "+-() .".contains($0) }) {
                return .number
            }
        }
        let codeMarkers = ["{", "}", "();", "=>", "func ", "def ", "const ", "import ", "</"]
        if codeMarkers.contains(where: trimmed.contains) {
            return .code
        }
        return .text
    }
}

/// Watches the general pasteboard and keeps a short history of copies. AppKit
/// gives no change notification, so this polls `changeCount` while the feature
/// is on. Everything but the pasteboard itself happens in `ClipboardStore`.
@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipboardItem] = []
    /// Small decoded pictures for image entries, by file name.
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    /// Image entries whose file could not be read.
    @Published private(set) var missingImages: Set<String> = []

    enum Thumbnail {
        case ready(NSImage)
        case loading
        case missing
    }

    private let store = ClipboardStore()
    private let launchDate = Date()
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    /// Copies still being described, chained so they land in the order made.
    private var ingestion: Task<Void, Never>?
    private var pendingSave: Task<Void, Never>?
    /// Saving waits for the stored history, or a copy made during launch would
    /// overwrite it.
    private var historyLoaded = false
    private var loadingThumbnails: Set<String> = []

    private init() {
        cancellable = Defaults.publisher(.clipboardEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    change.newValue ? self?.start() : self?.stop()
                }
            }

        if Defaults[.clipboardEnabled] { start() }
        loadHistory()
    }

    // MARK: - Watching

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        // Lets the system fold the tick in with its other wake-ups.
        timer.tolerance = 0.15
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

        // Respect the marker apps like password managers set on secrets.
        if pasteboard.types?.contains(.init("org.nspasteboard.ConcealedType")) == true { return }

        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // An image file copied in Finder (Cmd-C on it, not a drag) lands on
        // the pasteboard as a file URL, with its own filename as the plain
        // text alongside it - so text would otherwise win below and the card
        // would show a name instead of the picture.
        if let fileImage = Self.imageFileData(on: pasteboard) {
            enqueue { [store] in
                guard let stored = await store.storeImage(fileImage, isPNG: false) else { return }
                self.insert(ClipboardItem(
                    text: "", sourceBundleID: source, imageFileName: stored.fileName,
                    imageWidth: stored.width, imageHeight: stored.height))
            }
            return
        }

        if let text = pasteboard.string(forType: .string),
           text.contains(where: { !$0.isWhitespace }) {
            enqueue { [store] in
                let item = await store.describe(text, source: source)
                self.add(item)
            }
            return
        }

        // Screenshots and other copied images, checked after text: a rich
        // editor puts both on the pasteboard, and the text is what you meant.
        if let image = Self.imageData(on: pasteboard) {
            enqueue { [store] in
                guard let stored = await store.storeImage(image.data, isPNG: image.isPNG) else { return }
                self.insert(ClipboardItem(
                    text: "", sourceBundleID: source, imageFileName: stored.fileName,
                    imageWidth: stored.width, imageHeight: stored.height))
            }
        }
    }

    /// Chains the work, so two copies in quick succession keep their order.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = ingestion
        ingestion = Task {
            await previous?.value
            await work()
        }
    }

    /// The image on the pasteboard: a screenshot arrives as TIFF, an image
    /// dragged from a browser as PNG.
    private static func imageData(on pasteboard: NSPasteboard) -> (data: Data, isPNG: Bool)? {
        if let png = pasteboard.data(forType: .png) { return (png, true) }
        if let tiff = pasteboard.data(forType: .tiff) { return (tiff, false) }
        return nil
    }

    /// A single file on the pasteboard that is itself an image - Finder's
    /// Cmd-C on a file, not a screenshot or a drag. `nil` for anything else,
    /// including a multi-file selection: there is nowhere in a text-shaped
    /// history to put more than one picture at a time.
    private static func imageFileData(on pasteboard: NSPasteboard) -> Data? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              urls.count == 1, let url = urls.first,
              let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
              type.conforms(to: .image)
        else { return nil }
        return try? Data(contentsOf: url)
    }

    private func add(_ item: ClipboardItem) {
        // A repeat copy moves the existing entry to the top instead of
        // stacking. Text only.
        items.removeAll { !$0.isImage && $0.text == item.text }
        insert(item)
    }

    /// Puts an entry at the top and trims the history to the user's limit.
    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        trimToLimit()
        save()
    }

    private func trimToLimit() {
        let limit = max(1, Defaults[.clipboardHistoryLimit])
        guard items.count > limit else { return }
        discardImages(of: Array(items.suffix(items.count - limit)))
        items.removeLast(items.count - limit)
    }

    // MARK: - Images

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFileName.map { ClipboardStore.imagesDirectory.appendingPathComponent($0) }
    }

    /// The picture for an image card: downsampled to about the size it is
    /// drawn, decoded off the main thread, and kept. `.loading` until ready.
    func thumbnail(for item: ClipboardItem) -> Thumbnail {
        guard let fileName = item.imageFileName else { return .missing }
        if let image = thumbnails[fileName] { return .ready(image) }
        if missingImages.contains(fileName) { return .missing }
        guard !loadingThumbnails.contains(fileName) else { return .loading }

        loadingThumbnails.insert(fileName)
        let maxPixelSize = Self.thumbnailPixelSize(width: item.imageWidth, height: item.imageHeight)
        Task { [store] in
            let image = await store.thumbnail(named: fileName, maxPixelSize: maxPixelSize)
            loadingThumbnails.remove(fileName)
            // Deleted while it was decoding.
            guard items.contains(where: { $0.imageFileName == fileName }) else { return }
            if let image {
                thumbnails[fileName] = NSImage(cgImage: image, size: .zero)
            } else {
                missingImages.insert(fileName)
            }
        }
        return .loading
    }

    /// Longest side, in pixels, that keeps the shorter side covering the
    /// biggest card twice over for Retina. `.fill` scales by the shorter side.
    private static func thumbnailPixelSize(width: Int?, height: Int?) -> Int {
        let cover = 520
        guard let width, let height, width > 0, height > 0 else { return 1_024 }
        let long = max(width, height)
        let short = min(width, height)
        guard short > cover else { return long }
        return min(long * cover / short, 4_096)
    }

    /// Forgets the pictures of entries leaving the history, and their files.
    private func discardImages(of dropped: [ClipboardItem]) {
        let names = dropped.compactMap(\.imageFileName)
        guard !names.isEmpty else { return }
        for name in names {
            thumbnails[name] = nil
            missingImages.remove(name)
        }
        Task { [store] in await store.deleteImages(names) }
    }

    // MARK: - Actions

    func copy(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let url = imageURL(for: item) {
            // The stored PNG as it is: an NSImage would be decoded and
            // re-encoded as TIFF on the main thread.
            if let png = try? Data(contentsOf: url, options: .mappedIfSafe) {
                pasteboard.setData(png, forType: .png)
            }
        } else {
            pasteboard.setString(item.text, forType: .string)
        }
        // Our own write, so the next poll does not file it again.
        lastChangeCount = pasteboard.changeCount

        // Move it back to the top so the most recently used is first.
        if let index = items.firstIndex(where: { $0.id == item.id }), index != 0 {
            items.remove(at: index)
            items.insert(item, at: 0)
            save()
        }
    }

    func remove(_ item: ClipboardItem) {
        discardImages(of: [item])
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        discardImages(of: items)
        items.removeAll()
        save()
    }

    // MARK: - Persistence

    /// Saves a moment after the last change, not on every one, and off the
    /// main thread.
    private func save() {
        guard historyLoaded, Defaults[.clipboardPersistHistory] else { return }
        pendingSave?.cancel()
        let snapshot = items
        pendingSave = Task { [store] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await store.saveHistory(snapshot)
        }
    }

    /// Reads the saved history in the background, under anything copied since.
    private func loadHistory() {
        let persisted = Defaults[.clipboardPersistHistory]
        Task { [store, launchDate] in
            let stored = persisted ? await store.loadHistory() : nil
            let copiedMeanwhile = !items.isEmpty
            if let stored {
                let fresh = Set(items.map(\.id))
                items.append(contentsOf: stored.filter { !fresh.contains($0.id) })
                trimToLimit()
            }
            historyLoaded = true
            if copiedMeanwhile { save() }

            // Files from before this launch that no entry points at, left by a
            // crash between writing a PNG and saving the history.
            await store.sweepImages(
                keeping: Set(items.compactMap(\.imageFileName)), modifiedBefore: launchDate)
        }
    }

    func forgetStoredHistory() {
        pendingSave?.cancel()
        thumbnails.removeAll()
        missingImages.removeAll()
        Task { [store] in await store.forget() }
    }
}

// MARK: - Store

/// The clipboard's disk, and the work too heavy for the main thread. An actor,
/// so writes land in the order asked for.
actor ClipboardStore {
    nonisolated static let directory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (support ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("VornyxNotch", isDirectory: true)
    }()

    /// Images live as files beside the history: a base64 screenshot inside the
    /// JSON would be rewritten on every save.
    nonisolated static let imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
    private nonisolated static let historyURL = directory.appendingPathComponent("clipboard.json")

    struct StoredImage: Sendable {
        let fileName: String
        let width: Int
        let height: Int
    }

    func describe(_ text: String, source: String?) -> ClipboardItem {
        ClipboardItem(text: text, sourceBundleID: source)
    }

    /// Files a copied image as PNG. PNG bytes are kept as they came, anything
    /// else (a screenshot's TIFF) is converted.
    func storeImage(_ data: Data, isPNG: Bool) -> StoredImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }

        let png: Data
        if isPNG {
            png = data
        } else {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            png = output as Data
        }

        let fileName = "\(UUID().uuidString).png"
        do {
            try FileManager.default.createDirectory(at: Self.imagesDirectory, withIntermediateDirectories: true)
            try png.write(to: Self.imagesDirectory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            NSLog("Clipboard: could not store copied image: \(error.localizedDescription)")
            return nil
        }
        return StoredImage(fileName: fileName, width: width, height: height)
    }

    func thumbnail(named fileName: String, maxPixelSize: Int) -> CGImage? {
        let url = Self.imagesDirectory.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    }

    func deleteImages(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: Self.imagesDirectory.appendingPathComponent(name))
        }
    }

    func loadHistory() -> [ClipboardItem]? {
        guard let data = try? Data(contentsOf: Self.historyURL) else { return nil }
        return try? JSONDecoder().decode([ClipboardItem].self, from: data)
    }

    func saveHistory(_ items: [ClipboardItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? data.write(to: Self.historyURL, options: .atomic)
    }

    /// Deletes image files no entry points at, older than `cutoff` so an image
    /// copied while the history was loading is not mistaken for an orphan.
    func sweepImages(keeping live: Set<String>, modifiedBefore cutoff: Date) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.imagesDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        for url in files where !live.contains(url.lastPathComponent) {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
                  modified < cutoff
            else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func forget() {
        try? FileManager.default.removeItem(at: Self.historyURL)
        try? FileManager.default.removeItem(at: Self.imagesDirectory)
    }
}

// MARK: - Pasting

extension ClipboardManager {
    /// Send Command-V to whatever app is frontmost. Posting a key event into
    /// another app needs Accessibility, so this asks once and does nothing if
    /// the answer is no. The notch is non-activating, so the keystroke lands
    /// where you left the cursor.
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
