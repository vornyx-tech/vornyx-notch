//
//  OnboardingView.swift
//  VornyxNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

enum OnboardingStep {
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
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .permissions
                    }
                }
                .transition(.opacity)

            case .permissions:
                PermissionsChecklistView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .musicPermission
                    }
                }
                .transition(.opacity)

            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            VornyxViewCoordinator.shared.firstLaunch = false
                            step = .features
                        }
                    }
                )
                .transition(.opacity)

            case .features:
                FeatureTourView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .finished
                    }
                }
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
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
              detail: "Ask a question in the notch and get an answer with your own Gemini key."),
        .init(symbol: "antenna.radiowaves.left.and.right",
              title: "LocalSend",
              detail: "Send files and text to any device on the network, no account and no cloud."),
        .init(symbol: "cloud.sun.fill",
              title: "Weather",
              detail: "Current conditions and the days ahead on the dashboard."),
        .init(symbol: "square.grid.2x2.fill",
              title: "Shortcuts",
              detail: "Your sites and tools a click away, next to the calendar and timer."),
    ]

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            Text("More than a player")
                .font(.title)
                .fontWeight(.bold)

            Text("All of this lives in the notch, and every part of it can be turned on or off in Settings.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(features) { feature in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 17))
                            .foregroundColor(.effectiveAccent)
                            .frame(width: 26, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.headline)
                            Text(feature.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            Button(remaining > 0 ? "Continue in \(remaining)" : "Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(remaining > 0)
                .keyboardShortcut(remaining > 0 ? nil : .defaultAction)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .onReceive(tick) { _ in
            if remaining > 0 { remaining -= 1 }
        }
    }
}

#Preview {
    FeatureTourView(onContinue: {})
}
