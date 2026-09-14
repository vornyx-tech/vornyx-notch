//
//  TabButton.swift
//  VornyxNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    /// False when `icon` names an asset. Asset art is drawn as a template so
    /// it tints with the tab state like the SF Symbols beside it.
    var isSystemImage: Bool = true
    let selected: Bool
    let onClick: () -> Void

    @State private var hovering = false

    /// Matches the optical height of the SF Symbols in the same pill.
    private let artworkHeight: CGFloat = 14
    /// The trimmed logo's own proportions. Fixing height alone let the pill's
    /// own frame squash the width, so both axes are pinned.
    private let artworkAspect: CGFloat = 28.0 / 24.0

    var body: some View {
        Button(action: onClick) {
            Group {
                if isSystemImage {
                    Image(systemName: icon)
                } else {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(artworkAspect, contentMode: .fit)
                        .frame(width: artworkHeight * artworkAspect, height: artworkHeight)
                }
            }
            .padding(.horizontal, 11)
            .contentShape(Capsule())
            // Scale and brightness rather than a background of its own: the
            // selected tab's capsule slides between tabs underneath, and a
            // second capsule here would fight it.
            .brightness(hovering && !selected ? 0.25 : 0)
            .scaleEffect(hovering && !selected ? 1.12 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: hovering)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering = $0 }
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
