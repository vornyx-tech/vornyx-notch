//
//  OnboardingView.swift
//  VornyxNotch
//
//  Created by Alexander on 2025-06-23.
//

import Defaults
import SwiftUI

extension Color {
    /// Onboarding runs on its own warm accent rather than the user's, so the
    /// first thing anyone sees looks the same on every Mac.
    static let onboardingAccent = Color(red: 219 / 255, green: 205 / 255, blue: 184 / 255)
}

/// Filled button for onboarding: the warm accent needs a dark label, which the
/// system's prominent style does not give it.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Filled(configuration: configuration, compact: compact)
    }

    private struct Filled: View {
        let configuration: Configuration
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .foregroundStyle(.black.opacity(isEnabled ? 0.88 : 0.45))
                .padding(.vertical, compact ? 5 : 10)
                .padding(.horizontal, compact ? 14 : 18)
                .background {
                    Capsule().fill(
                        Color.onboardingAccent
                            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.22)
                    )
                }
                .contentShape(Capsule())
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case theme
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
                ZStack {
                    switch step {
                    case .welcome:
                        WelcomeView { advance(to: .permissions) }
                            .transition(.opacity)

                    case .permissions:
                        PermissionsChecklistView { advance(to: .theme) }
                            .transition(.opacity)

                    case .theme:
                        ThemeSelectionView { advance(to: .musicPermission) }
                            .transition(.opacity)

                    case .musicPermission:
                        // firstLaunch itself does not clear until onFinish, at
                        // the very end: it is what keeps the notch closed to
                        // hover, clicks and the toggle shortcut, and the home
                        // page empty, for the whole rest of onboarding too -
                        // not just up to here.
                        MusicControllerSelectionView(onContinue: {
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
                .padding(.bottom, 18)

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
                colors: [Color.onboardingAccent.opacity(0.38), .clear],
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

/// One dot per step, the current one stretched into a bar.
private struct OnboardingProgress: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item == step ? Color.onboardingAccent : .white.opacity(0.18))
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
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        .init(title: "AI chat", detail: "Your own Gemini key, no subscription"),
        .init(title: "LocalSend", detail: "Files across the room, never the cloud"),
        .init(title: "Weather", detail: "Today and the week, on the dashboard"),
        .init(title: "Shortcuts", detail: "The sites you keep reopening"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Also in here")
                .font(.system(size: 27, weight: .semibold))
                .padding(.top, 26)

            Text("Turn any of it off in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    if index > 0 {
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(height: 1)
                    }
                    FeatureRow(index: index + 1, title: feature.title, detail: feature.detail)
                }
            }
            .padding(.top, 24)

            Spacer(minLength: 16)

            Button(action: onContinue) {
                Text(remaining > 0 ? "Continue in \(remaining)" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
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
        let index: Int
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.onboardingAccent.opacity(0.8))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Spacer(minLength: 12)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 13)
        }
    }
}

/// Solid black or Liquid Glass, chosen once up front rather than dug out of
/// Settings later. Defaults to whichever `liquidGlassNotch` already is, so
/// Continue never needs the choice actually touched to mean something.
struct ThemeSelectionView: View {
    let onContinue: () -> Void

    @Default(.liquidGlassNotch) private var liquidGlassNotch

    private struct Theme {
        let title: String
        let asset: String
        let isLiquidGlass: Bool
    }

    private let themes: [Theme] = [
        .init(title: "Solid", asset: "ThemeSolid", isLiquidGlass: false),
        .init(title: "Liquid Glass", asset: "ThemeLiquidGlass", isLiquidGlass: true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pick a look")
                .font(.system(size: 27, weight: .semibold))
                .padding(.top, 26)

            Text("Change it later in Settings whenever you like.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 6)

            VStack(spacing: 12) {
                ForEach(themes, id: \.title) { theme in
                    ThemeOptionButton(
                        title: theme.title,
                        asset: theme.asset,
                        isSelected: liquidGlassNotch == theme.isLiquidGlass
                    ) {
                        liquidGlassNotch = theme.isLiquidGlass
                    }
                }
            }
            .padding(.top, 22)

            Spacer(minLength: 16)

            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ThemeOptionButton: View {
    let title: String
    let asset: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // The screenshots come pre-cropped, so show them whole: fit to
                // the card's width and let the height follow the image's own
                // aspect ratio. Only the corners are rounded here.
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.onboardingAccent : .white.opacity(0.7))
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.08 : 0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.onboardingAccent : .white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView(onFinish: {}, onOpenSettings: {})
}
