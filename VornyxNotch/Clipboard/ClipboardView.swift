//
//  ClipboardView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// Clipboard history as a notch tab: a horizontal row of cards, newest first.
///
/// Horizontal because the notch is wide and short - a vertical list would show
/// two entries and waste the rest - and cards because that is the language the
/// shelf already speaks.
struct ClipboardView: View {
    @EnvironmentObject var vm: VornyxViewModel
    @StateObject private var clipboard = ClipboardManager.shared
    @State private var justCopied: UUID?
    @State private var hovered: UUID?
    /// The card the arrow keys are on. Nil until the keyboard is used, so a
    /// mouse-only visit shows no selection ring at all.
    @State private var selected: UUID?

    @ObservedObject private var coordinator = VornyxViewCoordinator.shared

    /// How many cards the row shows at once.
    ///
    /// Cards are sized to fit exactly this many across the room the notch
    /// gives, rather than being a fixed width: a hardcoded 184pt overran the
    /// stock 640pt notch by twelve points, so the row always ended on a card
    /// sliced in half by the notch's edge.
    private let visibleCards = 3
    private let cardSpacing: CGFloat = 8
    /// Breathing room between the row and the notch's inner edge.
    private let rowInset: CGFloat = 4
    /// Slack above and below the row for a hovered card to grow into. The
    /// scroll view clips to its own bounds, so without this the top and bottom
    /// of the card the pointer is on would be shaved off as it lifts.
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
                // Read the room before drawing, rather than letting the cards
                // state a size: the notch hands this page a fixed height and
                // width, and a card that asks for more just draws past the
                // edges. Sizing to what is actually there keeps the row inside
                // the notch whatever the corner radius and font metrics work
                // out to.
                GeometryReader { proxy in
                    let size = cardSize(in: proxy.size)

                    ScrollViewReader { scroller in
                        ScrollView(.horizontal) {
                            // A grid rather than a stack, so a second row fills
                            // column by column: down is the next card, right is
                            // the one after that. Newest still reads first,
                            // top-left to bottom-right.
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
    }

    /// A card's size: the row's width shared between `visibleCards`, and the
    /// page's height shared between however many rows are open.
    ///
    /// The notch grows by a row's worth when a row opens, so the division comes
    /// out at about the same card height either way - the point of opening out
    /// is to see more cards, not smaller ones.
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

    /// The arrows work whenever there are cards to walk - the open notch holds
    /// the keyboard regardless of how it was opened.
    private var keysEnabled: Bool {
        !clipboard.items.isEmpty
    }

    /// Only a clipboard opened by its shortcut starts with a card picked out.
    /// Arriving with the mouse shows no selection ring until an arrow is
    /// actually pressed, at which point `moveSelection` picks the first card.
    private func beginKeyboardSessionIfAsked() {
        guard coordinator.keyboardSession else { return }
        VornyxNotchSkyLightWindow.takeKeyboardFocus()
        selected = clipboard.items.first?.id
    }

    /// Only this page's own state. The session itself outlives the page - you
    /// can Command-arrow to the shelf and back - so `ContentView` ends it when
    /// the notch closes.
    private func endKeyboardSession() {
        // The rows fold back whether or not the keyboard was in use: a notch
        // that reopened at the height you last left it would be a surprise.
        coordinator.clipboardRows = 1
        selected = nil
    }

    /// Arrows walk the row, Return takes the card, Delete drops it, Escape
    /// leaves. Anything else falls through to whoever would normally get it.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let key = NotchKey(event) else { return false }
        // Command-arrows step the tabs, which is the notch's business, not the
        // row's - let them past.
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
    ///
    /// The first press is the one that makes room: rather than telling you
    /// somewhere else exists, the notch grows a row and the cards that were off
    /// the end of the strip come up into it. After that, down is just down -
    /// the next card in the column.
    private func goDown() {
        let index = selectedIndex ?? 0

        // A row already open beneath this card: just move into it. Growing here
        // instead was the bug - with three rows allowed, the second press
        // opened a third row rather than stepping down into the second.
        if index % rows < rows - 1 {
            moveSelection(by: 1)
            return
        }

        // Nothing below, so make somewhere to go - one row, not all of them.
        guard rows < clipboardMaxRows else { return }
        let opened = rows + 1
        withAnimation(notchResizeAnimation) {
            coordinator.clipboardRows = opened
        }
        // The cards reflow into the taller grid, so where the selected one
        // lands decides whether there is now anything below it.
        if index % opened != opened - 1 {
            moveSelection(by: 1)
        }
    }

    /// Up is the way back: out of the lower row first, and then - from the top
    /// row - the notch closes the row again. Pressing up until the notch is
    /// back to one row undoes exactly what pressing down did.
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

    /// Steps through the cards and stops at the ends rather than wrapping - the
    /// same rule the tabs follow, so a held arrow key cannot spin the history.
    ///
    /// The offset is in cards, and the grid fills column-first, so a whole
    /// column is `rows` cards: left and right pass that, up and down pass one.
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

    /// Copy it, get out of the way, and paste it where you were.
    ///
    /// Pasting is the point: you pressed the shortcut to put something into the
    /// document you are in, and stopping at the pasteboard leaves you to press
    /// Command-V yourself - the very keystroke this was meant to save. The
    /// notch closes first because it is a panel over that document, and the
    /// keystroke wants a clean frontmost app to land in.
    ///
    /// Without Accessibility this quietly stops after copying, which is exactly
    /// what it used to do.
    private func takeAndLeave(_ item: ClipboardItem) {
        copy(item)
        Task {
            // Long enough to see the tick, short enough that it does not feel
            // like waiting.
            try? await Task.sleep(for: .milliseconds(240))
            vm.close()
            try? await Task.sleep(for: .milliseconds(140))
            _ = await ClipboardManager.pasteIntoFrontmostApp()
        }
    }

    /// Delete under the cursor, leaving the selection where your eye is: on
    /// whatever slid into the gap, or the new last card at the end of the row.
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

    /// The same rule the shelf panels follow: concentric with the notch.
    ///
    /// Clamped to half the shorter side, because past that a rounded rectangle
    /// stops being one - the arcs meet and the shape becomes a stadium.
    private func cardRadius(for size: CGSize) -> CGFloat {
        min(innerPanelCornerRadius, size.width / 2, size.height / 2)
    }

    /// Padding grows with the radius, so the glyphs and text stay clear of the
    /// curve however round the notch is set.
    private func cardPadding(for radius: CGFloat) -> CGFloat {
        max(12, radius * 0.42)
    }

    /// The room inside a card's padding: full width, and whatever height the
    /// fixed parts leave. Every row is given this outright rather than left to
    /// negotiate for it.
    ///
    /// A thumbnail cannot be trusted to compress. `aspectRatio(.fill)` reports
    /// a *minimum* of the size that covers the other axis - 190pt wide for a
    /// 4:1 screenshot in a 48pt-tall row - and a flexible frame around it caps
    /// nothing. Left to itself it widens the whole stack, the padded stack
    /// overruns the card, and the fixed frame centres the overflow: every row
    /// shifts sideways and the header and footer slide out through the corner
    /// curve, which is what clipped the "I" off the footer's label.
    private func contentSize(in size: CGSize, padding: CGFloat) -> CGSize {
        let chrome = padding * 2 + headerHeight + footerHeight + cardStackSpacing * 2
        return CGSize(
            width: max(0, size.width - padding * 2),
            height: max(0, size.height - chrome)
        )
    }

    /// How many lines of text fit that height. Three at the stock notch height;
    /// fewer rather than overflowing when the notch - or the corner radius,
    /// which sets the padding - leaves less.
    private func bodyLineLimit(_ item: ClipboardItem, height: CGFloat) -> Int {
        max(1, min(3, Int(height / bodyLineHeight(for: item))))
    }

    // MARK: - Card

    private func card(_ item: ClipboardItem, size: CGSize) -> some View {
        let copied = justCopied == item.id
        let isSelected = selected == item.id
        // The arrow keys light a card the same way the pointer does, so the two
        // ways of getting around the row look like one thing.
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
        // The same lift-and-squash the dashboard's shortcut tiles answer with,
        // scaled down: the tiles are 20pt and these are 180, and a card growing
        // by the tiles' 7% would eat the gap to its neighbour. Brightness is
        // left to the fill below, which already lightens on hover and has the
        // copied state to show as well.
        .springyTile(hoverScale: 1.035, pressScale: 0.965, hoverBrightness: 0)
        // The keyboard's own lift. `springyTile` answers the pointer and knows
        // nothing about the arrow keys, so selection does its own - on the same
        // spring, so a card picked up either way settles identically.
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

    /// A copied image, filling the card's body the way its text would.
    ///
    /// `.fill` and clipped rather than `.fit`: a screenshot is usually much
    /// wider than this card, and fitting it leaves a letterboxed sliver too
    /// small to recognise. Cropping to the card shows the top-left of the shot
    /// at a readable size, which is enough to tell two screenshots apart.
    private func thumbnail(_ item: ClipboardItem, radius: CGFloat, size: CGSize) -> some View {
        Group {
            if let image = clipboard.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                // The file is gone - deleted underneath us, or the history
                // outlived it. Say so rather than showing an empty hole.
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // The size first, then the clip: a filled image overruns whichever axis
        // it has to, and only a clip applied *outside* the fixed frame crops
        // that overrun back to the card.
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// Kind glyph, source app and time on one baseline, so cards line up with
    /// each other however long their text is.
    private func header(_ item: ClipboardItem, copied: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon(for: item))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint(for: item))
                .frame(width: headerHeight, height: headerHeight)
                .background(Circle().fill(tint(for: item).opacity(0.20)))

            if let bundleID = item.sourceBundleID {
                AppIcon(for: bundleID)
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

    /// A character count means nothing for a screenshot, so images report
    /// their pixel size instead.
    private func measure(of item: ClipboardItem) -> String {
        if item.isImage {
            guard let width = item.imageWidth, let height = item.imageHeight else { return "" }
            return "\(width)×\(height)"
        }
        return "\(item.text.count)"
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
