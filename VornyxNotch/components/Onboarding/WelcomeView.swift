//
//  WelcomeView.swift
//  VornyxNotch
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI

struct WelcomeView: View {
    var onGetStarted: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)

            Text("Vornyx Notch")
                .font(.system(size: 34, weight: .semibold))
                .padding(.top, 22)

            Text("The space around the notch, put to work: music, a shelf for\nfiles, the clipboard, and a dashboard behind them.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .lineSpacing(3)
                .padding(.top, 8)

            Spacer(minLength: 0)

            Button {
                onGetStarted?()
            } label: {
                Text("Get started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text("Takes a minute. Two permissions, then you pick a player.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview {
    WelcomeView()
}
