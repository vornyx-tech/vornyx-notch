//
//  IndicatorLights.swift
//  VornyxNotch
//
//  The camera, microphone, Focus and Caps Lock lights.
//

import Defaults
import SwiftUI

/// A row of small lights, shown only for what is actually on.
///
/// Deliberately dots rather than a banner: these are states you want to be able
/// to check without being interrupted, and something that takes over the notch
/// every time you unmute would be intolerable. Nothing on means nothing drawn.
struct IndicatorLights: View {
    @ObservedObject private var monitor = IndicatorsManager.shared

    /// Bigger in the open notch, where there is room and the header is calm.
    var size: CGFloat = 7

    var body: some View {
        HStack(spacing: 4) {
            ForEach(lights, id: \.symbol) { light in
                Image(systemName: light.symbol)
                    .font(.system(size: size, weight: .black))
                    .foregroundStyle(light.tint)
                    .transition(.scale.combined(with: .opacity))
                    .help(light.help)
            }
        }
        .animation(.smooth(duration: 0.2), value: monitor.indicators)
    }

    private struct Light {
        let symbol: String
        let tint: Color
        let help: String
    }

    /// Order is fixed rather than by arrival, so a light never moves under the
    /// pointer as another one comes and goes.
    private var lights: [Light] {
        let state = monitor.indicators
        var lights: [Light] = []

        if state.camera {
            lights.append(.init(symbol: "video.fill", tint: .green, help: "Camera in use"))
        }
        if state.microphone {
            lights.append(.init(symbol: "mic.fill", tint: .orange, help: "Microphone in use"))
        }
        if state.focus {
            lights.append(.init(symbol: "moon.fill", tint: .purple, help: "Focus is on"))
        }
        if state.capsLock {
            lights.append(.init(
                symbol: "capslock.fill",
                tint: Color.effectiveAccent,
                help: "Caps Lock is on"
            ))
        }
        return lights
    }
}
