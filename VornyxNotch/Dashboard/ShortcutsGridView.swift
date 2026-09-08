//
//  ShortcutsGridView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// Two rows of three website tiles, plus an add button in the first free slot.
struct ShortcutsGridView: View {
    @StateObject private var manager = WebShortcutsManager.shared
    @State private var isFetching = false

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
        Button(action: promptForShortcut) {
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

    // MARK: - Adding

    /// An AppKit prompt rather than a SwiftUI sheet.
    ///
    /// The notch lives in a non-activating panel that does not become key, and
    /// a sheet presented from it cannot take keyboard input - the field simply
    /// never accepts anything. Activating briefly for a modal is the same
    /// pattern the camera permission prompt already uses.
    private func promptForShortcut() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Add a shortcut"
        alert.informativeText = "Paste a link. The site's icon is fetched automatically; if it can't be found the tile shows the first letter instead."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "https://example.com"
        // Pre-fill from the clipboard when it already holds a link.
        if let pasted = NSPasteboard.general.string(forType: .string),
           WebShortcutsManager.normalise(pasted) != nil {
            field.stringValue = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        let raw = field.stringValue

        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()

        guard response == .alertFirstButtonReturn,
              WebShortcutsManager.normalise(raw) != nil
        else { return }

        isFetching = true
        Task {
            _ = await manager.add(raw)
            isFetching = false
        }
    }
}
