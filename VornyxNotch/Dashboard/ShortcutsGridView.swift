//
//  ShortcutsGridView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// Two rows of three website tiles, plus an add button in the first free slot.
struct ShortcutsGridView: View {
    @StateObject private var manager = WebShortcutsManager.shared
    @State private var isAdding = false
    @State private var draft = ""
    @State private var draftTitle = ""
    @State private var isFetching = false
    @State private var failed = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(manager.shortcuts) { shortcut in
                tile(shortcut)
            }
            if !manager.isFull {
                addTile
            }
        }
        .sheet(isPresented: $isAdding) { addSheet }
    }

    // MARK: - Tiles

    private func tile(_ shortcut: WebShortcut) -> some View {
        Button {
            manager.open(shortcut)
        } label: {
            VStack(spacing: 3) {
                Group {
                    if let icon = shortcut.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Text(shortcut.monogram)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(width: 20, height: 20)

                Text(shortcut.title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 4), style: .continuous)
                    .fill(.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .help(shortcut.url.absoluteString)
        .contextMenu {
            Button("Open") { manager.open(shortcut) }
            Button("Remove", role: .destructive) { manager.remove(shortcut) }
        }
    }

    private var addTile: some View {
        Button {
            draft = ""
            draftTitle = ""
            failed = false
            isAdding = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 20, height: 20)
                Text("Add")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 4), style: .continuous)
                    .strokeBorder(
                        .white.opacity(0.15),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add sheet

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a shortcut")
                .font(.headline)

            TextField("Paste a link", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            TextField("Name (optional)", text: $draftTitle)
                .textFieldStyle(.roundedBorder)

            if failed {
                Label("That does not look like a web address.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("The site's icon is fetched automatically. If it can't be found, the tile shows the first letter instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { isAdding = false }
                Button(isFetching ? "Adding…" : "Add", action: submit)
                    .buttonStyle(BorderedProminentButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func submit() {
        guard WebShortcutsManager.normalise(draft) != nil else {
            failed = true
            return
        }
        failed = false
        isFetching = true
        Task {
            let added = await manager.add(draft, title: draftTitle)
            isFetching = false
            if added { isAdding = false } else { failed = true }
        }
    }
}
