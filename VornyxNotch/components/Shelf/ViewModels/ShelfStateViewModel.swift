//
//  ShelfStateViewModel.swift
//  VornyxNotch
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }

    @Published var isLoading: Bool = false

    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?

    private init() {
        items = ShelfPersistenceService.shared.load()
    }


    // MARK: - Pointing at what just landed

    /// Changes each time something asks for items to be pointed out, so views
    /// already on screen hear about it.
    @Published private(set) var highlightToken = UUID()
    /// The item to scroll to: the last of the ones pointed out.
    private(set) var highlightScrollTarget: UUID?
    /// Items still waiting to flash. Taken one by one by the item views, so a
    /// view that only appears once the notch has opened still gets its flash,
    /// and one that appears again later does not get it twice.
    private var pendingHighlights: Set<UUID> = []
    private var highlightExpiry: Task<Void, Never>?

    /// Flash these items, where they sit on the shelf, so it is plain where
    /// something that arrived has gone.
    func highlight(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        pendingHighlights = Set(ids)
        highlightScrollTarget = ids.last
        highlightToken = UUID()

        // Nobody opened the shelf to see it: it is old news by the next look.
        highlightExpiry?.cancel()
        highlightExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.pendingHighlights.removeAll()
            self?.highlightScrollTarget = nil
        }
    }

    /// True once for an item waiting to flash.
    func takeHighlight(_ id: UUID) -> Bool {
        pendingHighlights.remove(id) != nil
    }

    /// Add, and say which items on the shelf now stand for what was added -
    /// the existing one where an item was already there.
    @discardableResult
    func addReturningIDs(_ newItems: [ShelfItem]) -> [UUID] {
        add(newItems)
        return newItems.compactMap { new in
            let key = new.identityKey
            return items.first { $0.identityKey == key }?.id
        }
    }

    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        for it in newItems {
            let key = it.identityKey
            if !seen.contains(key) {
                merged.append(it)
                seen.insert(key)
            }
        }
        items = merged
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx].kind = .file(bookmark: bookmark)
        }
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self = self else { return }
            
            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   case .file = self.items[idx].kind {
                    self.items[idx].kind = .file(bookmark: bookmarkData)
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                self?.add(dropped)
                self?.isLoading = false
            }
        }
    }

    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            var keep: [ShelfItem] = []
            for item in self.items {
                switch item.kind {
                case .file(let data):
                    let bookmark = Bookmark(data: data)
                    if await bookmark.validate() {
                        keep.append(item)
                    } else {
                        item.cleanupStoredData()
                    }
                default:
                    keep.append(item)
                }
            }
            await MainActor.run { self.items = keep }
        }
    }


    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = resolveFileURL(for: it) { urls.append(u) }
        }
        return urls
    }
}
