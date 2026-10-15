//
//  ScreenshotWatcher.swift
//  VornyxNotch
//
//  New screenshots land on the shelf by themselves: the folder they are
//  saved to is watched, and each picture or recording that appears in it is
//  put on the shelf and pointed out, the way files from LocalSend are.
//

import AppKit
import Combine
import Defaults
import UniformTypeIdentifiers

@MainActor
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    private var source: DispatchSourceFileSystemObject?
    private var folder: URL?
    private var descriptor: Int32 = -1
    /// What was in the folder at the last look, so only what is new counts.
    private var known: Set<String> = []
    private var started = Date()
    private var settling: Set<String> = []
    private var observers: [Defaults.Observation] = []

    /// Follows its own setting and folder; nothing is watched until both are set.
    func start() {
        observers = [
            Defaults.observe(.screenshotsToShelf) { [weak self] _ in self?.reconfigure() },
            Defaults.observe(.screenshotsFolderBookmark) { [weak self] _ in self?.reconfigure() },
        ]
        reconfigure()
    }

    /// The folder being watched, for Settings to show.
    var folderURL: URL? {
        guard let data = Defaults[.screenshotsFolderBookmark] else { return nil }
        return Bookmark(data: data).resolveURL()
    }

    /// Asks which folder the screenshots are saved to - the Desktop unless
    /// changed in System Settings - and keeps the access it grants.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        panel.message = "Choose the folder your screenshots are saved to"
        panel.directoryURL = folderURL ?? URL(fileURLWithPath: "/Users/\(NSUserName())/Desktop")
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        Defaults[.screenshotsFolderBookmark] = bookmark
        Defaults[.screenshotsToShelf] = true
    }

    private func reconfigure() {
        stop()
        guard Defaults[.screenshotsToShelf], Defaults[.shelfEnabled], let url = folderURL,
              url.startAccessingSecurityScopedResource()
        else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            url.stopAccessingSecurityScopedResource()
            return
        }
        folder = url
        descriptor = fd
        started = Date()
        known = Set(listing(of: url).map(\.lastPathComponent))

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in self?.folderChanged() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func stop() {
        source?.cancel()
        source = nil
        folder?.stopAccessingSecurityScopedResource()
        folder = nil
        descriptor = -1
        known = []
        settling = []
    }

    private func listing(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .contentTypeKey, .isHiddenKey],
            options: [.skipsHiddenFiles])) ?? []
    }

    private func folderChanged() {
        guard let folder else { return }
        let now = listing(of: folder)
        let names = Set(now.map(\.lastPathComponent))
        let arrived = now.filter { url in
            let name = url.lastPathComponent
            guard !known.contains(name), !settling.contains(name) else { return false }
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentTypeKey])
            // Only pictures and recordings made since the watch began: a file
            // moved in from elsewhere, or the folder's old contents, are not
            // screenshots.
            guard let created = values?.creationDate, created >= started.addingTimeInterval(-2),
                  let type = values?.contentType, type.conforms(to: .image) || type.conforms(to: .movie)
            else { return false }
            return true
        }
        known = names
        for url in arrived {
            settling.insert(url.lastPathComponent)
            Task { await shelve(url) }
        }
    }

    /// Once the file has stopped growing - the screenshot app is still
    /// writing it when the folder first says it is there - put it on the
    /// shelf and show it.
    private func shelve(_ url: URL) async {
        defer { settling.remove(url.lastPathComponent) }
        var lastSize: Int? = nil
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(250))
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            if let size, size > 0, size == lastSize { break }
            lastSize = size
        }
        guard let bookmark = try? Bookmark(url: url) else { return }
        let ids = ShelfStateViewModel.shared.addReturningIDs([ShelfItem(kind: .file(bookmark: bookmark.data))])
        ShelfStateViewModel.shared.highlight(ids)
        NotificationCenter.default.post(name: .localSendRevealShelf, object: nil)
    }
}
