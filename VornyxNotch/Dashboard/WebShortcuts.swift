//
//  WebShortcuts.swift
//  VornyxNotch
//

import AppKit
import Defaults
import Foundation

struct WebShortcut: Codable, Identifiable, Equatable, Defaults.Serializable {
    let id: UUID
    var title: String
    var url: URL
    /// Cached favicon bytes, so the grid draws offline.
    var iconData: Data?

    var host: String { url.host() ?? url.absoluteString }

    /// First letter of the site, for when no icon could be fetched.
    var monogram: String {
        String(title.first ?? host.first ?? "?").uppercased()
    }

    var icon: NSImage? {
        guard let iconData else { return nil }
        return NSImage(data: iconData)
    }
}

@MainActor
final class WebShortcutsManager: ObservableObject {
    static let shared = WebShortcutsManager()

    @Published var shortcuts: [WebShortcut] = Defaults[.webShortcuts] {
        didSet { Defaults[.webShortcuts] = shortcuts }
    }

    /// Two rows of three.
    static let capacity = 6

    var isFull: Bool { shortcuts.count >= Self.capacity }

    private init() {}

    /// Accepts a URL with or without a scheme.
    static func normalise(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.host() != nil else { return nil }
        return url
    }

    func add(_ raw: String, title: String? = nil) async -> Bool {
        guard !isFull, let url = Self.normalise(raw) else { return false }

        let host = url.host() ?? raw
        let name = (title?.isEmpty == false ? title! : Self.prettyName(from: host))
        var shortcut = WebShortcut(id: UUID(), title: name, url: url, iconData: nil)
        shortcut.iconData = await Self.fetchIcon(for: url)

        shortcuts.append(shortcut)
        return true
    }

    func remove(_ shortcut: WebShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
    }

    func open(_ shortcut: WebShortcut) {
        NSWorkspace.shared.open(shortcut.url)
    }

    /// "github.com" -> "Github", "www.bbc.co.uk" -> "Bbc".
    private static func prettyName(from host: String) -> String {
        let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let name = stripped.split(separator: ".").first.map(String.init) ?? stripped
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// DuckDuckGo's icon service first: bare /favicon.ico is missing on many sites.
    private static func fetchIcon(for url: URL) async -> Data? {
        guard let host = url.host() else { return nil }

        let candidates = [
            URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
            URL(string: "https://\(host)/favicon.ico"),
        ].compactMap { $0 }

        for candidate in candidates {
            var request = URLRequest(url: candidate)
            request.timeoutInterval = 8
            guard
                let (data, response) = try? await URLSession.shared.data(for: request),
                (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                !data.isEmpty,
                NSImage(data: data) != nil
            else { continue }
            return data
        }
        return nil
    }
}
