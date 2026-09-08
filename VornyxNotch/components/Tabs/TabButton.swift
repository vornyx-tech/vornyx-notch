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

    /// Matches the optical height of the SF Symbols in the same pill.
    private let artworkHeight: CGFloat = 13

    var body: some View {
        Button(action: onClick) {
            Group {
                if isSystemImage {
                    Image(systemName: icon)
                } else {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: artworkHeight)
                }
            }
            .padding(.horizontal, 15)
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
