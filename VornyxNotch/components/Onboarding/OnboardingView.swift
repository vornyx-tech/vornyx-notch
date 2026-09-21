//
//  OnboardingView.swift
//  VornyxNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case musicPermission
    case features
    case finished
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackdrop()

            VStack(spacing: 0) {
                OnboardingNotchMark()
                    .padding(.bottom, 4)

                ZStack {
                    switch step {
                    case .welcome:
                        WelcomeView { advance(to: .permissions) }
                            .transition(.opacity)

                    case .permissions:
                        PermissionsChecklistView { advance(to: .musicPermission) }
                            .transition(.opacity)

                    case .musicPermission:
                        MusicControllerSelectionView(onContinue: {
                            VornyxViewCoordinator.shared.firstLaunch = false
                            advance(to: .features)
                        })
                        .transition(.opacity)

                    case .features:
                        FeatureTourView { advance(to: .finished) }
                            .transition(.opacity)

                    case .finished:
                        OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                OnboardingProgress(step: step)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: 460, height: 640)
        .preferredColorScheme(.dark)
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.45)) { step = next }
    }
}

/// Near-black with the accent bleeding in from the top, the way the notch is
/// lit by album art.
private struct OnboardingBackdrop: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.04, green: 0.04, blue: 0.05)

            RadialGradient(
                colors: [Color.effectiveAccent.opacity(0.38), .clear],
                center: .top, startRadius: 0, endRadius: 360
            )
            .blur(radius: 40)

            LinearGradient(
                colors: [.white.opacity(0.06), .clear],
                startPoint: .top, endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

/// The product's own silhouette, drawn where a title bar would be.
private struct OnboardingNotchMark: View {
    var body: some View {
        NotchShape(topCornerRadius: 8, bottomCornerRadius: 14)
            .fill(.black)
            .frame(width: 132, height: 26)
            .overlay {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 15)
                    .offset(y: -1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// One dot per step, the current one stretched into a bar.
private struct OnboardingProgress: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item == step ? Color.effectiveAccent : .white.opacity(0.18))
                    .frame(width: item == step ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
    }
}

/// The last stop before "You're all set": what the notch can do beyond media,
/// and where to find it later. The button waits a few seconds so the list gets
/// read rather than clicked through.
struct FeatureTourView: View {
    let onContinue: () -> Void

    private static let holdSeconds = 5

    @State private var remaining = FeatureTourView.holdSeconds
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        .init(symbol: "sparkles",
              title: "AI chat",
              detail: "Ask a question in the notch, answered with your own Gemini key."),
        .init(symbol: "antenna.radiowaves.left.and.right",
              title: "LocalSend",
              detail: "Files and text to any device on the network. No account, no cloud."),
        .init(symbol: "cloud.sun.fill",
              title: "Weather",
              detail: "Now and the days ahead, on the dashboard."),
        .init(symbol: "square.grid.2x2.fill",
              title: "Shortcuts",
              detail: "Your sites and tools a click away, beside the calendar and timer."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("More than a player")
                .font(.system(size: 27, weight: .semibold))
                .padding(.top, 26)

            Text("Every part of this can be switched on or off in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    if index > 0 {
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(height: 1)
                    }
                    FeatureRow(symbol: feature.symbol, title: feature.title, detail: feature.detail)
                }
            }
            .padding(.top, 26)

            Spacer(minLength: 16)

            Button(action: onContinue) {
                Text(remaining > 0 ? "Continue in \(remaining)" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(remaining > 0)
            .keyboardShortcut(remaining > 0 ? nil : .defaultAction)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(tick) { _ in
            if remaining > 0 { remaining -= 1 }
        }
    }

    private struct FeatureRow: View {
        let symbol: String
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(width: 22, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
        }
    }
}

#Preview {
    OnboardingView(onFinish: {}, onOpenSettings: {})
}
