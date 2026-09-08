//
//  ClipboardView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// Clipboard history as a notch tab: a horizontal row of cards, newest first.
/// Horizontal because the notch is wide and short - a vertical list would show
/// two entries and waste the rest.
struct ClipboardView: View {
    @EnvironmentObject var vm: VornyxViewModel
    @StateObject private var clipboard = ClipboardManager.shared
    @State private var justCopied: UUID?

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

    private func card(_ item: ClipboardItem) -> some View {
        let copied = justCopied == item.id
        // Same concentric rule the shelf panels use: a card inside the notch
        // takes the notch's radius minus the gap it sits in.
        let radius = nestedCornerRadius(inset: 2)
        return Button {
            clipboard.copy(item)
            withAnimation(.smooth(duration: 0.2)) { justCopied = item.id }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.smooth(duration: 0.2)) {
                    if justCopied == item.id { justCopied = nil }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    if let bundleID = item.sourceBundleID {
                        AppIcon(for: bundleID)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    Text(item.date, style: .time)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if copied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.effectiveAccent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(item.preview)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(8)
            .frame(width: 150)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: .secondarySystemFill).opacity(copied ? 0.75 : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        copied ? Color.effectiveAccent.opacity(0.8) : .white.opacity(0.05),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy") { clipboard.copy(item) }
            Button("Delete", role: .destructive) { clipboard.remove(item) }
            Divider()
            Button("Clear all", role: .destructive) { clipboard.clear() }
        }
        .help(item.preview)
    }
}
