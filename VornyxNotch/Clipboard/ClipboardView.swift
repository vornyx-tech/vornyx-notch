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

    private let cardWidth: CGFloat = 172

    var body: some View {
        Group {
            if clipboard.items.isEmpty {
                empty
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(clipboard.items) { item in
                            card(item)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Card

    private func card(_ item: ClipboardItem) -> some View {
        let copied = justCopied == item.id
        let isHovered = hovered == item.id
        let radius = nestedCornerRadius(inset: 2)

        return Button {
            copy(item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                header(item, copied: copied)

                Text(item.preview)
                    .font(bodyFont(for: item))
                    .foregroundStyle(.white)
                    .lineSpacing(1)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 0)

                footer(item)
            }
            .padding(10)
            .frame(width: cardWidth)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white.opacity(copied ? 0.14 : (isHovered ? 0.10 : 0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        copied ? Color.effectiveAccent.opacity(0.9)
                               : .white.opacity(isHovered ? 0.16 : 0.06),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isHovered && !copied {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) { clipboard.remove(item) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
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
        .help(item.preview)
    }

    /// Kind glyph, source app and time on one baseline, so cards line up with
    /// each other however long their text is.
    private func header(_ item: ClipboardItem, copied: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon(for: item))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint(for: item))
                .frame(width: 16, height: 16)
                .background(Circle().fill(tint(for: item).opacity(0.18)))

            if let bundleID = item.sourceBundleID {
                AppIcon(for: bundleID)
                    .resizable()
                    .frame(width: 12, height: 12)
            }

            Spacer(minLength: 0)

            if copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.effectiveAccent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(item.date, style: .time)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
            }
        }
        .frame(height: 16)
    }

    private func footer(_ item: ClipboardItem) -> some View {
        HStack(spacing: 4) {
            Text(label(for: item))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint(for: item).opacity(0.95))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(item.text.count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .monospacedDigit()
        }
        .frame(height: 12)
    }

    // MARK: - Per-kind styling

    private func icon(for item: ClipboardItem) -> String {
        switch item.kind {
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .number: return "number"
        case .text: return "text.alignleft"
        }
    }

    private func tint(for item: ClipboardItem) -> Color {
        switch item.kind {
        case .link: return .blue
        case .code: return .purple
        case .number: return .orange
        case .text: return .teal
        }
    }

    private func label(for item: ClipboardItem) -> String {
        switch item.kind {
        case .link(let host): return host
        case .code: return "Code"
        case .number: return "Number"
        case .text: return item.lineCount > 1 ? "\(item.lineCount) lines" : "Text"
        }
    }

    private func bodyFont(for item: ClipboardItem) -> Font {
        if case .code = item.kind {
            return .system(size: 11, design: .monospaced)
        }
        return .system(size: 12.5)
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
