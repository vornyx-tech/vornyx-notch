//
//  OnboardingFinishView.swift
//  VornyxNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.onboardingAccent)
                .frame(width: 64, height: 64)
                .background {
                    Circle()
                        .fill(Color.onboardingAccent.opacity(0.12))
                        .overlay(Circle().strokeBorder(Color.onboardingAccent.opacity(0.35), lineWidth: 1))
                }

            Text("Ready")
                .font(.system(size: 34, weight: .semibold))
                .padding(.top, 22)

            Text("Point at the notch and it opens. The rest is in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 8)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onFinish) {
                    Text("Start using it")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button(action: onOpenSettings) {
                    Text("Open Settings")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview {
    OnboardingFinishView(onFinish: { }, onOpenSettings: { })
}
