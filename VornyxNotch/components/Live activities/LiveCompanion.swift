//
//  LiveCompanion.swift
//  VornyxNotch
//
//  A second live activity sharing the closed notch with the music.
//

import Defaults
import SwiftUI

/// What rides along with the music, the way the Dynamic Island keeps two
/// activities up at once: its symbol joins on the far left of the notch, and
/// its one number on the far right, the same width both sides so the camera
/// stays in the middle.
///
/// One at a time - a transfer moving, then a Focus that has just changed,
/// then a countdown, the hotspot, a VPN.
enum LiveCompanion: Equatable {
    case localSend(upload: Bool, fraction: Double)
    case timer
    case hotspot
    case vpn(ConnectedVPN)
    case focus(FocusMode, on: Bool)

    /// The companion, if anything live wants to ride along.
    @MainActor
    static var current: LiveCompanion? {
        let localSend = LocalSendManager.shared
        if Defaults[.localSendEnabled] {
            if let outgoing = localSend.outgoing, !outgoing.isOver, !outgoing.isMessage {
                return .localSend(upload: true, fraction: outgoing.fraction)
            }
            if let incoming = localSend.incoming, incoming.phase == .receiving {
                return .localSend(upload: false, fraction: incoming.fraction)
            }
        }
        // A Focus that just changed lasts seconds, so for those seconds it
        // goes before the ones that stay up for hours - otherwise, with the
        // hotspot or a VPN already beside the music, it was never seen.
        let indicators = IndicatorsManager.shared
        // Only for a while after it comes on: a Focus lasts hours, and the
        // notch is not the place to say so all that time.
        let preview = BannerPreview.shared.focus
        if indicators.focusJustOn || preview != nil, Defaults[.focusLiveActivity] {
            let on = preview?.on ?? indicators.indicators.focus
            // The last mode seen is right only for Off; for On it could be
            // hours old.
            let mode = preview?.mode ?? (on ? indicators.focusMode : indicators.lastFocusMode) ?? .other
            return .focus(mode, on: on)
        }
        let countdown = CountdownManager.shared
        if countdown.isActive, Defaults[.timerLiveActivity] { return .timer }
        if (HotspotManager.shared.isActive || BannerPreview.shared.hotspot), Defaults[.hotspotLiveActivity] {
            return .hotspot
        }
        if let vpn = VPNManager.shared.connected, Defaults[.vpnLiveActivity] { return .vpn(vpn) }
        return nil
    }

    /// A LocalSend transfer is shown here rather than in its own banner, which
    /// would push the music out. Offers and messages keep the banner: they
    /// have buttons to press.
    @MainActor
    static var takesLocalSend: Bool {
        if case .localSend = current { return true }
        return false
    }
}

/// The companion's symbol, for the notch's far left.
struct LiveCompanionSymbol: View {
    let companion: LiveCompanion
    let side: CGFloat

    var body: some View {
        Group {
            switch companion {
            case .localSend(let upload, _):
                Image(systemName: upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)
            case .timer:
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CountdownManager.color)
            case .hotspot:
                HotspotSymbol(side: side)
            case .vpn(let vpn):
                if let icon = VPNManager.icon(for: vpn) {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: side - 4, height: side - 4)
                } else {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.2))
                }
            case .focus(let mode, let on):
                Image(systemName: mode.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? mode.tint : .white.opacity(0.45))
            }
        }
        .frame(width: side, height: side)
    }
}

/// The companion's one number, for the notch's far right.
struct LiveCompanionValue: View {
    let companion: LiveCompanion
    @ObservedObject private var countdown = CountdownManager.shared

    var body: some View {
        Group {
            switch companion {
            case .localSend(_, let fraction):
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(.blue)
            case .timer:
                Text(countdown.label)
                    .foregroundStyle(CountdownManager.color)
                    .contentTransition(.numericText(countsDown: true))
            case .hotspot:
                HotspotDuration()
            case .vpn(let vpn):
                if let since = vpn.connectedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(VPNLiveActivity.elapsed(from: since, to: context.date))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.2))
                } else {
                    Text("On").foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.2))
                }
            case .focus(let mode, let on):
                Text(on ? "On" : "Off").foregroundStyle(on ? mode.tint : .white.opacity(0.45))
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .fixedSize()
    }
}
