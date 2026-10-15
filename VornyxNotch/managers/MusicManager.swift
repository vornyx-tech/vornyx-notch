//
//  MusicManager.swift
//  VornyxNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    /// The one the notch is showing. Every command goes to it, so the rest
    /// of the class is unchanged by there being two.
    private var activeController: (any MediaControllerProtocol)?
    private var primaryController: (any MediaControllerProtocol)?
    private var secondaryController: (any MediaControllerProtocol)?
    /// The last state each source sent, which is how `chooseSource` knows who
    /// is playing without asking either app again.
    private var primaryState: PlaybackState?
    private var secondaryState: PlaybackState?

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var animations: VornyxAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @ObservedObject var coordinator = VornyxViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [TimedLyric] = []
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false

    private var artworkData: Data? = nil
    /// Bumped every time a different cover is asked for. A decode that finishes
    /// for an older request is dropped: decodes run in the background, a large
    /// old cover can finish after a small new one, and it used to land on top -
    /// the player showing the previous track's artwork after a skip.
    private var artworkGeneration = 0
    private var artworkRecheck: Task<Void, Never>?

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false

    enum SkipDirection { case forward, backward }
    /// Which way the last skip from the notch went, so the new title slides in
    /// from the matching side. Only known for skips pressed here: a track
    /// changed from the keyboard or the music app itself reads as forward.
    @Published private(set) var skipDirection: SkipDirection = .forward
    private var skipDirectionReset: Task<Void, Never>?
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Release both sources, not only the one on screen.
        activeController = nil
        primaryController = nil
        secondaryController = nil
        primaryState = nil
        secondaryState = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self else { return }
                    self.record(state, from: controller)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        controllerCancellables.removeAll()
        primaryController = nil
        secondaryController = nil
        primaryState = nil
        secondaryState = nil

        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType: MediaControllerType =
            (self.isNowPlayingDeprecated && preferredType == .nowPlaying) ? .appleMusic : preferredType

        primaryController = createController(for: controllerType)
        if primaryController == nil, controllerType != .appleMusic {
            // Fallback to Apple Music if preferred controller couldn't be created
            primaryController = createController(for: .appleMusic)
        }

        if let secondType = Defaults[.secondaryMediaController],
           secondType != .nowPlaying, secondType != controllerType {
            secondaryController = createController(for: secondType)
        }

        if let primaryController {
            setActiveController(primaryController)
        }
    }

    /// Files a state under the source that sent it, then lets the pair decide
    /// which one the notch is showing. Only the chosen source's states go on to
    /// `updateFromPlaybackState`: fed both, the artwork animation and the lyrics
    /// lookup would thrash between two players.
    private func record(_ state: PlaybackState, from controller: any MediaControllerProtocol) {
        if controller === primaryController {
            primaryState = state
        } else if controller === secondaryController {
            secondaryState = state
        } else {
            return
        }

        chooseSource()
        guard activeController === controller else { return }
        updateFromPlaybackState(state)
    }

    /// Whichever is playing wins. The primary breaks a tie, and when neither is
    /// playing the notch stays where it is, so a pair of idle players does not
    /// flip the notch back and forth between them.
    private func chooseSource() {
        guard let secondary = secondaryController else {
            if let primaryController, activeController !== primaryController {
                setActiveController(primaryController)
            }
            return
        }

        let wanted: (any MediaControllerProtocol)?
        if primaryState?.isPlaying == true {
            wanted = primaryController
        } else if secondaryState?.isPlaying == true {
            wanted = secondary
        } else {
            wanted = activeController ?? primaryController
        }

        if let wanted, activeController !== wanted {
            setActiveController(wanted)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Cancel any existing flip animation
        flipWorkItem?.cancel()

        // Set new active controller
        activeController = controller
        
        self.canFavoriteTrack = controller.supportsFavorite

        // Get current state from active controller
        forceUpdate()
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    // Also overrules any cover still decoding for the last track.
                    self.artworkGeneration += 1
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork

            // Recorded on every change, not only when new artwork came with it.
            // Held back, a track that kept the same cover - the rest of an
            // album - was never counted as seen, and every poll after it looked
            // like a new track again. Artwork arriving late is still caught: it
            // is compared by its bytes, not by these.
            let trackChanged = titleChanged || artistChanged || albumChanged || bundleChanged
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier

            // A new track still carrying the last track's artwork. Players often
            // send the new cover a moment later, and some never announce it on
            // its own - so ask again rather than wait for an update that may not
            // come. If the cover really is the same, asking changes nothing.
            if trackChanged && !artworkChanged && state.artwork != nil {
                self.recheckArtworkSoon()
            }

            // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }

            // Fetch lyrics on content change
            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        self.timestampDate = state.lastUpdated
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            let loved = result.booleanValue
            self.isFavoriteTrack = loved
            self.forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    // MARK: - Lyrics
    /// Bumped for every track the lyrics are looked up for. A lookup that
    /// finishes for an older one - the sources answer seconds apart - is
    /// dropped rather than landing on the track playing now.
    private var lyricsGeneration = 0

    /// Whether a lookup is still the one for the track playing.
    private func isCurrentLookup(_ generation: Int) -> Bool { generation == lyricsGeneration }

    /// The lyrics from each source in turn, best first, stopping at the first
    /// that has them:
    /// 1. Apple Music's own, when it is the player.
    /// 2. LRCLIB, timed by the line - and for Apple Music's text, the timings.
    /// 3. NetEase, timed by the word, replacing line timings when it has them.
    /// 4. Genius, untimed, when nothing else has the song.
    /// "No lyrics" only once every source has been asked.
    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String) {
        lyricsGeneration += 1
        let generation = lyricsGeneration
        guard Defaults[.enableLyrics], !title.isEmpty else {
            DispatchQueue.main.async {
                self.isFetchingLyrics = false
                self.currentLyrics = ""
                self.syncedLyrics = []
            }
            return
        }

        let fromAppleMusic = bundleIdentifier?.contains("com.apple.Music") == true
        Task { @MainActor in
            self.isFetchingLyrics = true
            self.currentLyrics = ""
            self.syncedLyrics = []

            // Timed lyrics found before are kept, so a song that had them
            // has them again however the services are doing today.
            if let cached = await Self.cachedLyrics(title: title, artist: artist), isCurrentLookup(generation) {
                self.syncedLyrics = cached.lines
                self.currentLyrics = cached.plain
                self.isFetchingLyrics = false
                return
            }

            // Every source asked at once, each answer shown the moment it
            // comes if it beats what is up: asked one after another, a slow
            // source held up all the rest.
            var textRank = 0
            var linesRank = 0
            await withTaskGroup(of: FoundLyrics?.self) { group in
                if fromAppleMusic {
                    group.addTask { await self.appleMusicLyrics().map { .text($0, rank: 3) } }
                }
                group.addTask {
                    guard let found = await self.lrclibLyrics(title: title, artist: artist) else { return nil }
                    return .both(found.plain, rank: 2, lines: found.lines)
                }
                group.addTask { await self.netEaseLyrics(title: title, artist: artist).map { .lines($0) } }

                for await found in group {
                    guard let found, isCurrentLookup(generation) else { continue }
                    let (text, rankOfText, lines): (String, Int, [TimedLyric]) = {
                        switch found {
                        case .text(let text, let rank): return (text, rank, [])
                        case .lines(let lines): return ("", 0, lines)
                        case .both(let text, let rank, let lines): return (text, rank, lines)
                        }
                    }()
                    if !lines.isEmpty, Self.rank(of: lines) > linesRank {
                        linesRank = Self.rank(of: lines)
                        self.syncedLyrics = lines
                    }
                    if !text.isEmpty, rankOfText > textRank {
                        textRank = rankOfText
                        self.currentLyrics = text
                    }
                    if self.currentLyrics.isEmpty, !self.syncedLyrics.isEmpty {
                        self.currentLyrics = self.syncedLyrics.map(\.text).joined(separator: "\n")
                    }
                    if !self.currentLyrics.isEmpty { self.isFetchingLyrics = false }
                }
            }

            if self.currentLyrics.isEmpty, self.syncedLyrics.isEmpty, isCurrentLookup(generation),
               let text = await self.geniusLyrics(title: title, artist: artist), isCurrentLookup(generation) {
                self.currentLyrics = text
            }
            guard isCurrentLookup(generation) else { return }
            self.isFetchingLyrics = false

            // Words without times - a busy LRCLIB, most often. Ask for the
            // times once more after a while; the words stay up meanwhile.
            if self.syncedLyrics.isEmpty {
                try? await Task.sleep(for: .seconds(15))
                guard isCurrentLookup(generation) else { return }
                var lines = await self.lrclibLyrics(title: title, artist: artist)?.lines ?? []
                if lines.isEmpty { lines = await self.netEaseLyrics(title: title, artist: artist) ?? [] }
                guard isCurrentLookup(generation), !lines.isEmpty else { return }
                self.syncedLyrics = lines
            }
            if isCurrentLookup(generation), !self.syncedLyrics.isEmpty {
                await Self.cacheLyrics(
                    CachedLyrics(plain: self.currentLyrics, lines: self.syncedLyrics),
                    title: title, artist: artist)
            }
        }
    }

    /// What one source found: words, timed lines, or both.
    private enum FoundLyrics: Sendable {
        case text(String, rank: Int)
        case lines([TimedLyric])
        case both(String, rank: Int, lines: [TimedLyric])
    }

    /// How good a set of timed lines is: timed by the word beats timed by the
    /// line with the words guessed.
    private static func rank(of lines: [TimedLyric]) -> Int {
        lines.contains { !$0.wordsEstimated && !$0.words.isEmpty } ? 2 : 1
    }

    // MARK: Lyrics kept on disk

    struct CachedLyrics: Codable {
        let plain: String
        let lines: [TimedLyric]
    }

    /// One file per track, named by its title and artist reduced to letters
    /// and digits, in Application Support.
    private static func lyricsCacheFile(title: String, artist: String) -> URL? {
        let key = String((matchKey(title) + "-" + matchKey(artist)).prefix(150))
        guard !key.isEmpty, key != "-",
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "VornyxNotch", isDirectory: true)
            .appendingPathComponent("Lyrics", isDirectory: true)
            .appendingPathComponent(key + ".json")
    }

    private static func cachedLyrics(title: String, artist: String) async -> CachedLyrics? {
        guard let file = lyricsCacheFile(title: title, artist: artist) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: file),
                  let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data),
                  !cached.lines.isEmpty
            else { return nil }
            return cached
        }.value
    }

    private static func cacheLyrics(_ lyrics: CachedLyrics, title: String, artist: String) async {
        guard let file = lyricsCacheFile(title: title, artist: artist) else { return }
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(lyrics).write(to: file, options: .atomic)
        }.value
    }

    /// The lyrics Apple Music has for the current track, if it is running
    /// and has any.
    @MainActor
    private func appleMusicLyrics() async -> String? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        else { return nil }
        let script = """
        tell application \"Music\"
            if it is running then
                if player state is playing or player state is paused then
                    try
                        set l to lyrics of current track
                        if l is missing value then
                            return \"\"
                        else
                            return l
                        end if
                    on error
                        return \"\"
                    end try
                else
                    return \"\"
                end if
            else
                return \"\"
            end if
        end tell
        """
        guard let result = try? await AppleScriptHelper.execute(script),
              let text = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    // MARK: Untimed lyrics

    /// Genius, the last resort: it times nothing, but has words for a great
    /// deal that no lyrics service times, fresh Russian rap included. Found by
    /// its search, read off the song's page.
    @MainActor
    private func geniusLyrics(title: String, artist: String) async -> String? {
        let bare = Self.bareTitle(title)
        var components = URLComponents(string: "https://genius.com/api/search/song")
        components?.queryItems = [.init(name: "q", value: "\(Self.firstArtist(artist)) \(bare)")]
        guard let url = components?.url,
              let data = await Self.webData(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = (json["response"] as? [String: Any])?["sections"] as? [[String: Any]]
        else { return nil }

        let wantedTitle = Self.matchKey(bare)
        let wantedArtist = Self.matchKey(artist)
        let hits = sections.flatMap { $0["hits"] as? [[String: Any]] ?? [] }
            .compactMap { $0["result"] as? [String: Any] }
        let song = hits.first { hit in
            guard let name = hit["title"] as? String, Self.matchKey(Self.bareTitle(name)) == wantedTitle,
                  let artists = hit["artist_names"] as? String else { return false }
            let key = Self.matchKey(Self.firstArtist(artists))
            return !key.isEmpty && (wantedArtist.contains(key) || key.contains(wantedArtist))
        }
        guard let path = song?["url"] as? String, let page = URL(string: path),
              let html = await Self.webData(page).flatMap({ String(data: $0, encoding: .utf8) })
        else { return nil }
        return Self.geniusLyrics(in: html)
    }

    /// The lyrics off a Genius song page: the text of its lyrics containers,
    /// without the contributor header inside them or the "[Verse 1]" labels.
    static func geniusLyrics(in html: String) -> String? {
        var parts: [String] = []
        var searchFrom = html.startIndex
        while let open = html.range(of: #"<div[^>]*data-lyrics-container="true"[^>]*>"#,
                                    options: .regularExpression, range: searchFrom..<html.endIndex) {
            guard let close = closingDiv(in: html, after: open.upperBound) else { break }
            parts.append(String(html[open.upperBound..<close.lowerBound]))
            searchFrom = close.upperBound
        }
        guard !parts.isEmpty else { return nil }

        var body = parts.joined(separator: "\n")
        while let open = body.range(of: #"<div[^>]*data-exclude-from-selection="true"[^>]*>"#,
                                    options: .regularExpression),
              let close = closingDiv(in: body, after: open.upperBound) {
            body.removeSubrange(open.lowerBound..<close.upperBound)
        }
        body = body
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let decoded = decodingEntities(body)
        let lines = decoded.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !($0.hasPrefix("[") && $0.hasSuffix("]")) }
        let text = lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// `&amp;`, `&#x27;`, `&#8212;` and the like back into their characters.
    /// By hand: AppKit's HTML reader would also fold the line breaks away.
    private static func decodingEntities(_ text: String) -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            guard let semi = rest[amp...].prefix(10).firstIndex(of: ";") else {
                result += "&"
                rest = rest[rest.index(after: amp)...]
                continue
            }
            let entity = rest[rest.index(after: amp)..<semi]
            var character: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                character = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(String.init)
            } else if entity.hasPrefix("#") {
                character = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map(String.init)
            } else {
                character = named[String(entity)]
            }
            if let character {
                result += character
                rest = rest[rest.index(after: semi)...]
            } else {
                result += "&"
                rest = rest[rest.index(after: amp)...]
            }
        }
        return result + rest
    }

    /// The `</div>` closing the div whose opening tag ends at `start`,
    /// counting the divs nested inside it.
    private static func closingDiv(in html: String, after start: String.Index) -> Range<String.Index>? {
        var depth = 1
        var cursor = start
        while let tag = html.range(of: #"<(/?)div\b[^>]*>"#, options: .regularExpression,
                                   range: cursor..<html.endIndex) {
            depth += html[tag].hasPrefix("</") ? -1 : 1
            if depth == 0 { return tag }
            cursor = tag.upperBound
        }
        return nil
    }

    private static func webData(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    /// The first of several artists - "greyrock, tewiq & madk1d" -> "greyrock".
    private static func firstArtist(_ artist: String) -> String {
        artist
            .components(separatedBy: CharacterSet(charactersIn: ",&;/"))
            .first?
            .replacingOccurrences(of: #"\s+(feat\.?|ft\.?|x|and)\s+.*$"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces) ?? artist
    }

    // MARK: Word-timed lyrics

    /// NetEase Cloud Music times each word for a good part of its catalogue,
    /// Western music included, in its own "yrc" format; where it does not, it
    /// often times the lines. It is not a public API, so any failure is just
    /// nothing found.
    @MainActor
    private func netEaseLyrics(title: String, artist: String) async -> [TimedLyric]? {
        var components = URLComponents(string: "https://music.163.com/api/cloudsearch/pc")
        components?.queryItems = [
            .init(name: "s", value: normalizedQuery("\(Self.bareTitle(title)) \(artist)")),
            .init(name: "type", value: "1"),
            .init(name: "limit", value: "10"),
        ]
        guard let url = components?.url,
              let search = await Self.netEaseJSON(url),
              let songs = (search["result"] as? [String: Any])?["songs"] as? [[String: Any]]
        else { return nil }

        let wantedTitle = Self.matchKey(Self.bareTitle(title))
        let wantedArtist = Self.matchKey(artist)
        let candidates = songs.filter { song in
            guard let name = song["name"] as? String,
                  Self.matchKey(Self.bareTitle(name)) == wantedTitle else { return false }
            let artists = (song["ar"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            guard artists.contains(where: {
                let key = Self.matchKey($0)
                return !key.isEmpty && (wantedArtist.contains(key) || key.contains(wantedArtist))
            }) else { return false }
            // Another cut of the song is timed for that cut.
            guard songDuration > 0, let ms = song["dt"] as? Double else { return true }
            return abs(ms / 1000 - songDuration) <= 3
        }

        for song in candidates.prefix(3) {
            guard let id = song["id"] as? Int,
                  let url = URL(string: "https://music.163.com/api/song/lyric/v1?id=\(id)&lv=0&yv=0&tv=0&rv=0&kv=0"),
                  let lyrics = await Self.netEaseJSON(url)
            else { continue }
            var lines = ((lyrics["yrc"] as? [String: Any])?["lyric"] as? String).map(Self.parseYRC) ?? []
            // No word timings: its line timings.
            if lines.isEmpty, let lrc = (lyrics["lrc"] as? [String: Any])?["lyric"] as? String {
                lines = self.parseLRC(lrc)
            }
            if !lines.isEmpty { return lines }
        }
        return nil
    }

    private static func netEaseJSON(_ url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// A title without what players add to it - "(Remastered 2011)",
    /// "- Single Version", "[feat. …]".
    private static func bareTitle(_ title: String) -> String {
        var bare = title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        if let dash = bare.range(of: " - ") { bare = String(bare[..<dash.lowerBound]) }
        return bare.trimmingCharacters(in: .whitespaces)
    }

    /// Lowercase letters and digits only, accents dropped, for comparing names
    /// spelled a little differently by two services.
    private static func matchKey(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// NetEase's yrc: `[start,duration]` before each line and
    /// `(start,duration,0)` before each word, in milliseconds. Credit lines
    /// come as JSON objects and are skipped.
    private static func parseYRC(_ yrc: String) -> [TimedLyric] {
        guard let lineTag = try? NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#),
              let wordTag = try? NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)"#)
        else { return [] }
        var result: [TimedLyric] = []
        for lineSub in yrc.split(whereSeparator: \.isNewline) {
            let line = String(lineSub) as NSString
            guard let tag = lineTag.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length))
            else { continue }
            let start = (Double(line.substring(with: tag.range(at: 1))) ?? 0) / 1000
            let tags = wordTag.matches(in: line as String, range: NSRange(location: 0, length: line.length))
            var words: [TimedWord] = []
            for (index, word) in tags.enumerated() {
                let from = word.range.location + word.range.length
                let to = index + 1 < tags.count ? tags[index + 1].range.location : line.length
                let text = line.substring(with: NSRange(location: from, length: to - from))
                let wordStart = (Double(line.substring(with: word.range(at: 1))) ?? 0) / 1000
                let duration = (Double(line.substring(with: word.range(at: 2))) ?? 0) / 1000
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    // A space timed on its own belongs to the word before.
                    if let last = words.popLast() {
                        words.append(TimedWord(start: last.start, end: last.end, text: last.text + text))
                    }
                } else {
                    words.append(TimedWord(start: wordStart, end: wordStart + duration, text: text))
                }
            }
            // Its English is timed word by word but now and then loses the
            // space between two - "howto" - which alphabets need back. Not
            // between Chinese characters, which go without.
            for index in words.indices.dropLast() {
                let word = words[index]
                if let last = word.text.unicodeScalars.last, let first = words[index + 1].text.unicodeScalars.first,
                   isAlphabetic(last), isAlphabetic(first) {
                    words[index] = TimedWord(start: word.start, end: word.end, text: word.text + " ")
                }
            }
            words = spaced(words)
            let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            result.append(TimedLyric(time: start, text: text, words: words))
        }
        return result.sorted { $0.time < $1.time }
    }

    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }

    /// LRCLIB's matches for a track, trying looser searches when a strict one
    /// finds nothing: the title stripped of "(feat. …)" and the like, then
    /// only the first of several artists - "greyrock, tewiq & madk1d" is often
    /// filed under "greyrock" - then title and artist as free text. Nil when
    /// none of them could be asked at all.
    private func lrclibSearch(title: String, artist: String) async -> [[String: Any]]? {
        let bare = Self.bareTitle(title)
        let firstArtist = Self.firstArtist(artist)
        var searches: [[URLQueryItem]] = [
            [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)],
        ]
        if bare != title {
            searches.append([.init(name: "track_name", value: bare), .init(name: "artist_name", value: artist)])
        }
        if !firstArtist.isEmpty, firstArtist != artist {
            searches.append([.init(name: "track_name", value: bare), .init(name: "artist_name", value: firstArtist)])
        }
        searches.append([.init(name: "q", value: "\(bare) \(firstArtist)")])

        var answered = false
        for items in searches {
            guard let results = await lrclibRequest("search", items) as? [[String: Any]] else { continue }
            answered = true
            if !results.isEmpty { return results }
        }
        return answered ? [] : nil
    }

    /// One LRCLIB request, asked again when the server is busy - it answers
    /// 503 often enough at busy hours that the lyrics went missing for songs
    /// it has. `endpoint` is "search" or "get".
    private func lrclibRequest(_ endpoint: String, _ items: [URLQueryItem]) async -> Any? {
        var components = URLComponents(string: "https://lrclib.net/api/\(endpoint)")
        components?.queryItems = items.map { .init(name: $0.name, value: $0.value.map(normalizedQuery)) }
        // URLComponents leaves "+" alone, which a server reads as a space.
        let query = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = query
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("VornyxNotch (https://github.com/vornyx-tech/vornyx-notch)", forHTTPHeaderField: "User-Agent")

        // LRCLIB limits how fast it is asked and answers 429 past that; a
        // second or two later it answers again. Short waits only ran into the
        // limit again, the timed lyrics never came, and an untimed source
        // stood in for a song LRCLIB has.
        let backoff: [Double] = [1, 2.5, 5]
        for attempt in 0...backoff.count {
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse
            else {
                if attempt < backoff.count { try? await Task.sleep(for: .seconds(backoff[attempt])) }
                continue
            }
            if http.statusCode == 200 {
                return try? JSONSerialization.jsonObject(with: data)
            }
            // Busy or rate limited is worth another go; anything else is not.
            guard http.statusCode == 429 || http.statusCode >= 500, attempt < backoff.count else { return nil }
            let asked = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            try? await Task.sleep(for: .seconds(min(asked ?? backoff[attempt], 10)))
        }
        return nil
    }

    /// Of LRCLIB's matches, the timed lyrics most likely to keep time with
    /// this recording: one as long as the track - another cut of the song is
    /// timed for that cut - and of those, one that times each word.
    private func bestSyncedLyrics(in results: [[String: Any]]) -> String? {
        let candidates: [(text: String, durationOff: Double, timesWords: Bool)] = results.compactMap { result in
            guard let text = (result["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            let duration = (result["duration"] as? Double) ?? (result["duration"] as? Int).map(Double.init)
            let off = duration.map { songDuration > 0 ? abs($0 - songDuration) : 0 } ?? .infinity
            return (text, off, text.range(of: #"<\d{1,3}:\d{2}"#, options: .regularExpression) != nil)
        }
        let matching = candidates.filter { $0.durationOff <= 3 }
        let pool = matching.isEmpty ? candidates : matching
        return (pool.first { $0.timesWords } ?? pool.first)?.text
    }

    /// LRCLIB's text and timings, or nil when it has neither. The exact
    /// lookup first - title, artist and length, one quick answer - and the
    /// searches only when that finds nothing.
    @MainActor
    private func lrclibLyrics(title: String, artist: String) async -> (plain: String, lines: [TimedLyric])? {
        var results: [[String: Any]] = []
        if songDuration > 0,
           let exact = await lrclibRequest("get", [
               .init(name: "track_name", value: title),
               .init(name: "artist_name", value: artist),
               .init(name: "duration", value: String(Int(songDuration.rounded()))),
           ]) as? [String: Any] {
            results = [exact]
        }
        if results.isEmpty {
            results = await lrclibSearch(title: title, artist: artist) ?? []
        }
        guard let first = results.first(where: { ($0["plainLyrics"] as? String)?.isEmpty == false })
                ?? results.first
        else { return nil }
        let plain = (first["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let synced = bestSyncedLyrics(in: results) ?? ""
        let lines = synced.isEmpty ? [] : parseLRC(synced)
        guard !plain.isEmpty || !lines.isEmpty else { return nil }
        return (plain, lines)
    }

    // MARK: - Synced lyrics helpers
    /// Plain LRC - `[mm:ss.xx]` before each line, several for a line sung more
    /// than once - and the enhanced kind, with a `<mm:ss.xx>` before each word
    /// and one after the last, which is what lights the words up one by one.
    private func parseLRC(_ lrc: String) -> [TimedLyric] {
        guard let lineTag = try? NSRegularExpression(pattern: #"^\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#),
              let wordTag = try? NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>"#)
        else { return [] }

        func seconds(_ match: NSTextCheckingResult, in line: NSString) -> Double {
            let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
            let secs = Double(line.substring(with: match.range(at: 2))) ?? 0
            let fractionRange = match.range(at: 3)
            // "5" is half a second, "05" a twentieth, "005" a two-hundredth.
            let fraction = fractionRange.location != NSNotFound
                ? Double("0." + line.substring(with: fractionRange)) ?? 0 : 0
            return minutes * 60 + secs + fraction
        }

        var result: [TimedLyric] = []
        for lineSub in lrc.split(whereSeparator: \.isNewline) {
            var line = String(lineSub).trimmingCharacters(in: .whitespaces) as NSString
            var times: [Double] = []
            while let match = lineTag.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) {
                times.append(seconds(match, in: line))
                line = line.substring(from: match.range.length) as NSString
            }
            guard !times.isEmpty else { continue }

            let body = line as String
            let tags = wordTag.matches(in: body, range: NSRange(location: 0, length: line.length))
            var words: [TimedWord] = []
            var text = body
            if !tags.isEmpty {
                for (index, tag) in tags.enumerated() {
                    let from = tag.range.location + tag.range.length
                    let to = index + 1 < tags.count ? tags[index + 1].range.location : line.length
                    let word = line.substring(with: NSRange(location: from, length: to - from))
                    let start = seconds(tag, in: line)
                    let end = index + 1 < tags.count ? seconds(tags[index + 1], in: line) : start
                    if word.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Spaces between two tags belong to the word before.
                        if let last = words.popLast() {
                            words.append(TimedWord(start: last.start, end: end, text: last.text + word))
                        }
                    } else {
                        words.append(TimedWord(start: start, end: end, text: word))
                    }
                }
                // Text before the first tag, if any, joins the first word.
                let lead = line.substring(to: tags[0].range.location)
                if !lead.trimmingCharacters(in: .whitespaces).isEmpty, let first = words.first {
                    words[0] = TimedWord(start: first.start, end: first.end, text: lead + first.text)
                }
                words = Self.spaced(words)
                text = words.map(\.text).joined()
            }
            text = text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            // The words are timed for one of the times - the nearest - and a
            // repeat of the line keeps them where they fall within it.
            let anchor = words.first.map { first in
                times.min { abs($0 - first.start) < abs($1 - first.start) } ?? first.start
            }
            for time in times {
                let shift = anchor.map { time - $0 } ?? 0
                let shifted = words.map { TimedWord(start: $0.start + shift, end: $0.end + shift, text: $0.text) }
                result.append(TimedLyric(time: time, text: text, words: shifted))
            }
        }
        return Self.estimatingWords(result.sorted { $0.time < $1.time })
    }

    /// A letter or digit of an alphabet that puts spaces between words.
    private static func isAlphabetic(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x0530 && (CharacterSet.alphanumerics.contains(scalar) || scalar == "'")
    }

    /// Words timed by guesswork for the lines that only have a line time - most
    /// lyrics - so they light up too. The line's span is shared out by
    /// syllables, the way it is sung more than by letters, and the span is
    /// capped at a slow singing pace so a line before an instrumental break is
    /// not spread over the break. Not exact - a held note runs ahead of it -
    /// but close enough to follow.
    private static func estimatingWords(_ lines: [TimedLyric]) -> [TimedLyric] {
        lines.enumerated().map { index, line in
            guard line.words.isEmpty else { return line }
            let pieces = line.text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard !pieces.isEmpty else { return line }
            let weights = pieces.map { Double(syllables(in: $0)) }
            let total = weights.reduce(0, +)
            let next = index + 1 < lines.count ? lines[index + 1].time : line.time + 6
            let gap = max(next - line.time, 0.3)
            // Lines are sung through to a little before the next; a pause left.
            let span = min(gap * 0.88, 0.6 + total * 0.42)

            var start = line.time
            let words = pieces.enumerated().map { offset, piece in
                let length = span * weights[offset] / total
                defer { start += length }
                return TimedWord(start: start, end: start + length,
                                 text: piece + (offset < pieces.count - 1 ? " " : ""))
            }
            return TimedLyric(time: line.time, text: line.text, words: words, wordsEstimated: true)
        }
    }

    /// Vowel groups, near enough to syllables for Latin and Cyrillic; a
    /// letter each in scripts without vowels to count, like Chinese.
    private static func syllables(in word: String) -> Int {
        let vowels = Set("aeiouyàáâãäåèéêëìíîïòóôõöùúûüýÿæœаеєиіїоуюяэыё")
        var count = 0
        var inVowel = false
        var letters = 0
        for character in word.lowercased() where character.isLetter {
            letters += 1
            let isVowel = vowels.contains(character)
            if isVowel && !inVowel { count += 1 }
            inVowel = isVowel
        }
        if count == 0 {
            let latinOrCyrillic = word.unicodeScalars.contains { $0.value < 0x0530 && CharacterSet.letters.contains($0) }
            count = latinOrCyrillic ? 1 : letters
        }
        return max(count, 1)
    }

    /// Each word trimmed, with one space after it where the line had any
    /// between it and the next - none inside a word timed in syllables, none
    /// after the last - so the words put together read as the line does.
    private static func spaced(_ words: [TimedWord]) -> [TimedWord] {
        words.enumerated().map { index, word in
            let next = index + 1 < words.count ? words[index + 1].text : nil
            let gap = next.map { word.text.last?.isWhitespace == true || $0.first?.isWhitespace == true } ?? false
            let text = word.text.trimmingCharacters(in: .whitespaces) + (gap ? " " : "")
            return TimedWord(start: word.start, end: word.end, text: text)
        }
    }

    /// How far ahead of the song the lyrics run. A line timed to the moment
    /// it is sung, drawn a tick later and rolling in over a few tenths of a
    /// second, was read a second or so after it was heard; Apple Music shows
    /// the next line a little early for the same reason.
    static let lyricsLead: Double = 0.3

    /// The line being sung at `elapsed`: the next one shown `lyricsLead`
    /// early, but never while the line before is still being sung. Lyrics
    /// timed by the word say when a line's last word ends, and the line
    /// stays until then - a long last note, or lyrics timed a touch early,
    /// used to lose the end of the line to the next one.
    func activeLyricIndex(at elapsed: Double) -> Int? {
        guard var index = lyricIndex(at: elapsed + Self.lyricsLead) else { return nil }
        while index > 0, elapsed < syncedLyrics[index].time {
            let previous = syncedLyrics[index - 1]
            guard !previous.wordsEstimated, let last = previous.words.last,
                  elapsed < last.end - 0.05 else { break }
            index -= 1
        }
        return index
    }

    /// The same for single words, which light up as they are sung: only a
    /// frame or two early, to make up for the drawing.
    static let wordLead: Double = 0.12

    func lyricLine(at elapsed: Double) -> String {
        guard let index = lyricIndex(at: elapsed) else { return currentLyrics }
        return syncedLyrics[index].text
    }

    /// The synced line being sung at `elapsed`: the last to have started, or
    /// the first while the song is still before it.
    func lyricIndex(at elapsed: Double) -> Int? {
        guard !syncedLyrics.isEmpty else { return nil }
        var low = 0
        var high = syncedLyrics.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if syncedLyrics[mid].time <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return idx
    }

    /// When a synced line stops being sung: its last word's end if it has
    /// word timings, otherwise when the next line starts - capped, so an
    /// instrumental gap after it does not stretch it out for half a minute.
    func lyricEnd(at index: Int) -> Double {
        let line = syncedLyrics[index]
        if let last = line.words.last, last.end > last.start { return last.end }
        let next = index + 1 < syncedLyrics.count ? syncedLyrics[index + 1].time : songDuration
        return min(max(next, line.time + 0.5), line.time + 8)
    }

    /// Where the song is now, run on from the last playback report.
    func elapsed(at date: Date) -> Double {
        guard isPlaying else { return elapsedTime }
        let progressed = elapsedTime + date.timeIntervalSince(timestampDate) * playbackRate
        return min(max(progressed, 0), max(songDuration, 0))
    }

    private var lyricClock: Double = 0
    private var lyricClockDate: Date = .distantPast

    /// `elapsed(at:)` for the lyrics' animation: a clock that runs evenly
    /// and eases into each correction the player reports, rather than
    /// jumping by it. Taken straight, every report nudged the song a few
    /// hundredths of a second, and the lit words and their lift twitched with
    /// it. A seek, a new track or a resume is caught up with at once.
    func smoothedElapsed(at date: Date) -> Double {
        let target = elapsed(at: date)
        guard isPlaying else {
            lyricClock = target
            lyricClockDate = date
            return target
        }
        let dt = date.timeIntervalSince(lyricClockDate)
        // A second view asking for a moment already past.
        if dt <= 0 { return lyricClock + dt * playbackRate }
        let predicted = lyricClock + dt * playbackRate
        let drift = target - predicted
        lyricClock = dt > 0.5 || abs(drift) > 0.35 ? target : predicted + drift * min(1, dt * 2.5)
        lyricClockDate = date
        return lyricClock
    }

    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()

        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        artworkGeneration += 1
        let generation = artworkGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    // A newer cover has been asked for since: this one is stale.
                    guard let self, generation == self.artworkGeneration else { return }
                    self.usingAppIconForArtwork = false
                    self.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    /// Ask the player for its state again, twice, shortly after a track change
    /// whose cover did not come with it.
    private func recheckArtworkSoon() {
        artworkRecheck?.cancel()
        artworkRecheck = Task { [weak self] in
            for delay in [800, 2000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.forceUpdate()
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                self.calculateAverageColor()
            }
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func nextTrack() {
        noteSkip(.forward)
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        noteSkip(.backward)
        Task {
            await activeController?.previousTrack()
        }
    }

    /// Held for a few seconds - long enough for the new track to arrive, short
    /// enough that a later change from elsewhere does not inherit it.
    private func noteSkip(_ direction: SkipDirection) {
        skipDirection = direction
        skipDirectionReset?.cancel()
        skipDirectionReset = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.skipDirection = .forward
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}

// MARK: - Timed lyrics

/// One word of a line, for lyrics that time each word. `text` carries the
/// space after it, so the words put back together read as the line.
struct TimedWord: Equatable, Codable {
    let start: Double
    let end: Double
    let text: String
}

/// One synced line. `words` are timed by the lyrics where they time them,
/// and estimated from the line's time where they do not.
struct TimedLyric: Equatable, Codable {
    let time: Double
    let text: String
    let words: [TimedWord]
    /// The words' times are guessed from the line's, not given by the lyrics.
    var wordsEstimated = false

    /// How far through the line the singing is, 0 to 1, by the words where
    /// they are timed, by the line's own span where they are not.
    func progress(at elapsed: Double, end: Double) -> Double {
        guard !words.isEmpty else {
            guard end > time else { return elapsed >= time ? 1 : 0 }
            return ((elapsed - time) / (end - time)).clamped(to: 0...1)
        }
        guard let word = words.lastIndex(where: { $0.start <= elapsed }) else { return 0 }
        let current = words[word]
        let span = max(current.end - current.start, 0.01)
        let within = ((elapsed - current.start) / span).clamped(to: 0...1)
        let before = words[..<word].reduce(0) { $0 + $1.text.count }
        let total = max(words.reduce(0) { $0 + $1.text.count }, 1)
        return (Double(before) + within * Double(current.text.count)) / Double(total)
    }

    /// How lit each word is, 0 to 1. Empty when the words are not timed.
    func wordFill(at elapsed: Double) -> [Double] {
        words.map { word in
            let span = max(word.end - word.start, 0.01)
            return ((elapsed - word.start) / span).clamped(to: 0...1)
        }
    }
}
