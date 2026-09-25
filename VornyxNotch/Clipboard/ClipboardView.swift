//
//  ClipboardView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// Clipboard history as a notch tab: a horizontal row of cards, newest first.
struct ClipboardView: View {
    @EnvironmentObject var vm: VornyxViewModel
    @StateObject private var clipboard = ClipboardManager.shared
    @State private var justCopied: UUID?
    @State private var hovered: UUID?
    /// The card the arrow keys are on. Nil until the keyboard is used.
    @State private var selected: UUID?
    @StateObject private var quickLookService = QuickLookService()

    @ObservedObject private var coordinator = VornyxViewCoordinator.shared

    /// How many cards the row shows at once. Cards are sized to fit this many
    /// across whatever room the notch gives, rather than a fixed width.
    private let visibleCards = 3
    private let cardSpacing: CGFloat = 8
    /// Breathing room between the row and the notch's inner edge.
    private let rowInset: CGFloat = 4
    /// Slack for a hovered card to grow into; the scroll view clips to its bounds.
    private let zoomHeadroom: CGFloat = 4

    /// Fixed parts of a card, so the text knows how many lines are left for it.
    private let headerHeight: CGFloat = 21
    private let footerHeight: CGFloat = 13
    /// The two gaps in the card's stack: header to body, body to footer.
    private let cardStackSpacing: CGFloat = 8

    var body: some View {
        Group {
            if clipboard.items.isEmpty {
                empty
            } else {
                GeometryReader { proxy in
                    let size = cardSize(in: proxy.size)

                    ScrollViewReader { scroller in
                        ScrollView(.horizontal) {
                            // A grid, so a second row fills column by column.
                            LazyHGrid(
                                rows: Array(
                                    repeating: GridItem(.fixed(size.height), spacing: cardSpacing),
                                    count: rows
                                ),
                                spacing: cardSpacing
                            ) {
                                ForEach(clipboard.items) { item in
                                    card(item, size: size)
                                        .id(item.id)
                                }
                            }
                            .padding(.horizontal, rowInset)
                            .padding(.vertical, zoomHeadroom)
                        }
                        .scrollIndicators(.never)
                        .scrollableNotchContent()
                        .onChange(of: selected) { _, id in
                            guard let id else { return }
                            withAnimation(.smooth(duration: 0.22)) {
                                scroller.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: beginKeyboardSessionIfAsked)
        .onDisappear(perform: endKeyboardSession)
        .onKeyDown(enabled: keysEnabled, handleKey)
        .quickLookPresenter(using: quickLookService)
    }

    /// A card's size: the row's width shared between `visibleCards`, and the
    /// page's height shared between however many rows are open.
    private func cardSize(in available: CGSize) -> CGSize {
        let columnGaps = cardSpacing * CGFloat(visibleCards - 1)
        let content = available.width - rowInset * 2 - columnGaps

        let rowGaps = cardSpacing * CGFloat(rows - 1)
        let height = available.height - zoomHeadroom * 2 - rowGaps

        return CGSize(
            width: max(140, content / CGFloat(visibleCards)),
            height: max(0, height / CGFloat(rows))
        )
    }

    // MARK: - Keyboard

    /// The arrows work whenever there are cards to walk.
    private var keysEnabled: Bool {
        !clipboard.items.isEmpty
    }

    /// Only a clipboard opened by its shortcut starts with a card picked out.
    private func beginKeyboardSessionIfAsked() {
        guard coordinator.keyboardSession else { return }
        VornyxNotchSkyLightWindow.takeKeyboardFocus()
        selected = clipboard.items.first?.id
    }

    /// Only this page's own state. The session outlives the page, so
    /// `ContentView` ends it when the notch closes.
    private func endKeyboardSession() {
        coordinator.clipboardRows = 1
        selected = nil
    }

    /// Arrows walk the row, Return takes the card, Delete drops it, Escape
    /// leaves. Anything else falls through.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let key = NotchKey(event) else { return false }
        // Command-arrows step the tabs, so let them past.
        guard !event.modifierFlags.contains(.command) else { return false }

        switch key {
        case .leftArrow:
            moveSelection(by: -rows)
        case .rightArrow:
            moveSelection(by: rows)
        case .downArrow:
            goDown()
        case .upArrow:
            goUp()
        case .returnKey, .enter:
            guard let item = selectedItem else { return false }
            takeAndLeave(item)
        case .delete, .forwardDelete:
            guard let item = selectedItem else { return false }
            removeKeepingPlace(item)
        case .space:
            // Finder's own shortcut, for the one card type it makes sense on:
            // text has no picture to blow up, so this is image cards only.
            // The pointer wins over the arrow-key selection when both are on
            // a card - the same order Finder's own hover-then-space follows.
            if quickLookService.isQuickLookOpen {
                quickLookService.hide()
                return true
            }
            let hoveredItem = hovered.flatMap { id in clipboard.items.first { $0.id == id } }
            guard let item = hoveredItem ?? selectedItem, item.isImage,
                  let url = clipboard.imageURL(for: item)
            else { return false }
            quickLookService.show(urls: [url])
        case .escape:
            vm.close()
        default:
            return false
        }
        return true
    }

    private var selectedItem: ClipboardItem? {
        clipboard.items.first { $0.id == selected }
    }

    /// How many rows of cards are open.
    private var rows: Int { coordinator.clipboardRows }

    /// Down opens the notch out by a row, then walks into it.
    private func goDown() {
        let index = selectedIndex ?? 0

        // A row already open beneath this card: just move into it.
        if index % rows < rows - 1 {
            moveSelection(by: 1)
            return
        }

        // Nothing below, so open one more row.
        guard rows < clipboardMaxRows else { return }
        let opened = rows + 1
        withAnimation(notchResizeAnimation) {
            coordinator.clipboardRows = opened
        }
        // The cards reflow, so the selected one may now have a card below it.
        if index % opened != opened - 1 {
            moveSelection(by: 1)
        }
    }

    /// Up steps out of the lower row first, then closes the row again.
    private func goUp() {
        let index = selectedIndex ?? 0
        if rows > 1, index % rows != 0 {
            moveSelection(by: -1)
            return
        }
        guard rows > 1 else { return }
        withAnimation(notchResizeAnimation) {
            coordinator.clipboardRows = rows - 1
        }
    }

    private var selectedIndex: Int? {
        guard let selected else { return nil }
        return clipboard.items.firstIndex { $0.id == selected }
    }

    /// Steps through the cards, stopping at the ends rather than wrapping. The
    /// offset is in cards, and the grid fills column-first, so a column is
    /// `rows` cards: left and right pass that, up and down pass one.
    private func moveSelection(by offset: Int) {
        let items = clipboard.items
        guard !items.isEmpty else { return }

        guard let current = selected, let index = items.firstIndex(where: { $0.id == current }) else {
            selected = items.first?.id
            return
        }
        let next = (index + offset).clamped(to: 0...(items.count - 1))
        guard next != index else { return }
        selected = items[next].id
    }

    /// Copy it, close the notch, and paste it where you were. Without
    /// Accessibility this quietly stops after copying.
    private func takeAndLeave(_ item: ClipboardItem) {
        copy(item)
        Task {
            // Long enough to see the tick.
            try? await Task.sleep(for: .milliseconds(240))
            vm.close()
            try? await Task.sleep(for: .milliseconds(140))
            _ = await ClipboardManager.pasteIntoFrontmostApp()
        }
    }

    /// Delete under the cursor, leaving the selection where your eye is.
    private func removeKeepingPlace(_ item: ClipboardItem) {
        let items = clipboard.items
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        withAnimation(.smooth(duration: 0.2)) { clipboard.remove(item) }

        let remaining = items.count - 1
        guard remaining > 0 else {
            selected = nil
            return
        }
        selected = clipboard.items[min(index, remaining - 1)].id
    }

    // MARK: - Card metrics

    /// Concentric with the notch, clamped to half the shorter side.
    private func cardRadius(for size: CGSize) -> CGFloat {
        min(innerPanelCornerRadius, size.width / 2, size.height / 2)
    }

    /// Padding grows with the radius, so text stays clear of the curve.
    private func cardPadding(for radius: CGFloat) -> CGFloat {
        max(12, radius * 0.42)
    }

    /// The room inside a card's padding: full width, and whatever height the
    /// fixed parts leave. Given outright, since `aspectRatio(.fill)` reports a
    /// minimum size and will not compress.
    private func contentSize(in size: CGSize, padding: CGFloat) -> CGSize {
        let chrome = padding * 2 + headerHeight + footerHeight + cardStackSpacing * 2
        return CGSize(
            width: max(0, size.width - padding * 2),
            height: max(0, size.height - chrome)
        )
    }

    /// How many lines of text fit that height, at most three.
    private func bodyLineLimit(_ item: ClipboardItem, height: CGFloat) -> Int {
        max(1, min(3, Int(height / bodyLineHeight(for: item))))
    }

    // MARK: - Card

    private func card(_ item: ClipboardItem, size: CGSize) -> some View {
        let copied = justCopied == item.id
        let isSelected = selected == item.id
        // Selection lights a card the same way the pointer does.
        let isHovered = hovered == item.id || isSelected
        let radius = cardRadius(for: size)
        let padding = cardPadding(for: radius)
        let content = contentSize(in: size, padding: padding)

        return Button {
            copy(item)
        } label: {
            VStack(alignment: .leading, spacing: cardStackSpacing) {
                header(item, copied: copied)
                    .frame(width: content.width)

                if item.isImage {
                    thumbnail(item, radius: max(4, radius - padding), size: content)
                } else {
                    Text(item.preview)
                        .font(bodyFont(for: item))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineSpacing(2.5)
                        .lineLimit(bodyLineLimit(item, height: content.height))
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(
                            width: content.width,
                            height: content.height,
                            alignment: .topLeading
                        )
                }

                footer(item)
                    .frame(width: content.width)
            }
            .padding(padding)
            .frame(width: size.width, height: size.height)
            .notchSurface(
                RoundedRectangle(cornerRadius: radius, style: .continuous),
                fill: copied ? 0.16 : (isHovered ? 0.12 : 0.07), stroke: 0,
                glassTint: copied
                    ? Color.effectiveAccent.opacity(0.35)
                    : (isHovered ? Color.white.opacity(0.1) : nil))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            // The selection's light, thrown inwards: a thick accent stroke,
            // blurred and clipped back to the card.
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.effectiveAccent.opacity(0.5), lineWidth: 20)
                        .blur(radius: 6)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        copied ? Color.effectiveAccent.opacity(0.9)
                            : isSelected ? Color.effectiveAccent.opacity(0.55)
                            : .white.opacity(isHovered ? 0.16 : 0.06),
                        lineWidth: isSelected || copied ? 1.5 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if (hovered == item.id || isSelected) && !copied {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) { clipboard.remove(item) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(.black.opacity(0.6)))
                    }
                    .springyTile(hoverScale: 1.15, pressScale: 0.88, hoverBrightness: 0.15)
                    .padding(5)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        // A smaller lift than the dashboard tiles, whose 7% would eat the gap
        // to the next card. Brightness is left to the fill below.
        .springyTile(hoverScale: 1.035, pressScale: 0.965, hoverBrightness: 0)
        // The keyboard's own lift, on the same spring as `springyTile`.
        .scaleEffect(isSelected ? 1.05 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isSelected)
        .zIndex(isSelected ? 1 : 0)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) {
                if hovering { hovered = item.id } else if hovered == item.id { hovered = nil }
            }
        }
        .contextMenu {
            Button("Copy") { copy(item) }
            Button("Delete", role: .destructive) { clipboard.remove(item) }
            Divider()
            Button("Clear all", role: .destructive) { clipboard.clear() }
        }
        .help(item.isImage ? label(for: item) : item.preview)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.title)
                .foregroundStyle(Color(white: 0.65))
            Text("Clipboard is empty")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text("Anything you copy shows up here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A copied image, filling the card's body. Cropped rather than fitted: a
    /// screenshot fitted into this card is an unreadable sliver.
    private func thumbnail(_ item: ClipboardItem, radius: CGFloat, size: CGSize) -> some View {
        Group {
            switch clipboard.thumbnail(for: item) {
            case .ready(let image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            case .loading:
                // Decoding off the main thread.
                Color.white.opacity(0.04)
            case .missing:
                // The file is gone: deleted underneath us, or the history
                // outlived it.
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Size first, then clip: only a clip outside the fixed frame crops the
        // filled image back to the card.
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// Kind glyph, source app and time on one baseline.
    private func header(_ item: ClipboardItem, copied: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon(for: item))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint(for: item))
                .frame(width: headerHeight, height: headerHeight)
                .background(Circle().fill(tint(for: item).opacity(0.20)))

            if let bundleID = item.sourceBundleID {
                Image(nsImage: SourceAppIcon.image(for: bundleID))
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            }

            Spacer(minLength: 0)

            if copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.effectiveAccent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(item.date, style: .time)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(height: headerHeight)
    }

    private func footer(_ item: ClipboardItem) -> some View {
        HStack(spacing: 4) {
            Text(label(for: item))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint(for: item).opacity(0.95))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(measure(of: item))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(height: footerHeight)
    }

    // MARK: - Per-kind styling

    private func icon(for item: ClipboardItem) -> String {
        switch item.kind {
        case .image: return "photo"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .number: return "number"
        case .text: return "text.alignleft"
        }
    }

    private func tint(for item: ClipboardItem) -> Color {
        switch item.kind {
        case .image: return .pink
        case .link: return .blue
        case .code: return .purple
        case .number: return .orange
        case .text: return .teal
        }
    }

    private func label(for item: ClipboardItem) -> String {
        switch item.kind {
        case .image: return "Image"
        case .link(let host): return host
        case .code: return "Code"
        case .number: return "Number"
        case .text: return item.lineCount > 1 ? "\(item.lineCount) lines" : "Text"
        }
    }

    /// Images report their pixel size instead of a character count.
    private func measure(of item: ClipboardItem) -> String {
        if item.isImage {
            guard let width = item.imageWidth, let height = item.imageHeight else { return "" }
            return "\(width)×\(height)"
        }
        return "\(item.summary.characterCount)"
    }

    private func bodyFontSize(for item: ClipboardItem) -> CGFloat {
        if case .code = item.kind { return 12 }
        return 13.5
    }

    private func bodyFont(for item: ClipboardItem) -> Font {
        if case .code = item.kind {
            return .system(size: bodyFontSize(for: item), design: .monospaced)
        }
        return .system(size: bodyFontSize(for: item))
    }

    /// A line of body text with its leading, near enough to count lines by.
    private func bodyLineHeight(for item: ClipboardItem) -> CGFloat {
        bodyFontSize(for: item) * 1.2 + 2.5
    }

    private func copy(_ item: ClipboardItem) {
        clipboard.copy(item)
        withAnimation(.smooth(duration: 0.2)) { justCopied = item.id }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.smooth(duration: 0.2)) {
                if justCopied == item.id { justCopied = nil }
            }
        }
    }
}

/// App icons by bundle id, looked up once: `AppIcon(for:)` asks Launch
/// Services and reads the icon on every call.
@MainActor
private enum SourceAppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let workspace = NSWorkspace.shared
        let icon = workspace.urlForApplication(withBundleIdentifier: bundleID)
            .map { workspace.icon(forFile: $0.path) }
            ?? workspace.icon(for: .applicationBundle)
        cache[bundleID] = icon
        return icon
    }
}
