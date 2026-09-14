//
//  LocalSendLiveActivity.swift
//  VornyxNotch
//
//  LocalSend in the closed notch: an offer to answer, or a transfer moving.
//

import SwiftUI

/// Name on the left of the cut-out, and on the right either the two answers to
/// an offer or how far a transfer has got - the shape the battery, AirPods and
/// timer banners share.
///
/// The answers are here and not only in the open notch because an offer
/// usually arrives while you are doing something else. The phone on the other
/// end waits for as long as it takes, and a banner you have to open the notch
/// to act on would leave it waiting longer.
struct LocalSendLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var localSend = LocalSendManager.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: localSend.pendingRequest != nil)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                trailing
            }
            .frame(width: 110, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var trailing: some View {
        if localSend.pendingRequest != nil {
            circleButton("xmark", prominent: false, help: "Decline") {
                localSend.declinePendingRequest()
            }
            circleButton("checkmark", prominent: true, help: "Accept") {
                localSend.acceptPendingRequest()
            }
        } else if let fraction {
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.effectiveAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.3), value: fraction)
            }
            .frame(width: 16, height: 16)
        } else if showsMessage {
            if localSend.message?.url != nil {
                circleButton("arrow.up.right", prominent: true, help: "Open") {
                    localSend.openMessageLink()
                }
            }
            circleButton("doc.on.doc", prominent: localSend.message?.url == nil, help: "Copy") {
                localSend.copyMessage()
            }
        } else if waiting {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .symbolEffect(.variableColor.iterative, options: .repeating)
        }
    }

    private func circleButton(
        _ symbol: String, prominent: Bool, help: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(prominent ? Color.effectiveAccent : .white.opacity(0.16)))
                .contentShape(Circle())
        }
        .springyTile(hoverScale: 1.12, pressScale: 0.9, hoverBrightness: 0.12)
        .help(help)
    }

    // MARK: - What to say

    private var title: String {
        if let request = localSend.pendingRequest {
            return request.sender.alias
        }
        if let incoming = localSend.incoming {
            return incoming.senderName
        }
        if showsMessage, let message = localSend.message {
            return message.text
        }
        return localSend.outgoing?.device.alias ?? "LocalSend"
    }

    private var symbol: String {
        if localSend.pendingRequest != nil { return "arrow.down.circle.fill" }
        if let incoming = localSend.incoming {
            switch incoming.phase {
            case .receiving: return "arrow.down.circle"
            case .finished: return "checkmark.circle.fill"
            case .cancelled: return "xmark.circle.fill"
            }
        }
        if showsMessage {
            return localSend.message?.url == nil ? "text.bubble.fill" : "link"
        }
        switch localSend.outgoing?.phase {
        case .waitingForAcceptance: return "hourglass"
        case .sending: return "arrow.up.circle"
        case .finished: return "checkmark.circle.fill"
        default: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        if localSend.pendingRequest != nil || showsMessage { return .effectiveAccent }
        if localSend.incoming?.phase == .finished || localSend.outgoing?.phase == .finished { return .green }
        if let phase = localSend.outgoing?.phase, localSend.incoming == nil {
            switch phase {
            case .declined, .busy, .failed: return .orange
            case .cancelled: return .white.opacity(0.5)
            default: break
            }
        }
        return .white
    }

    private var fraction: Double? {
        if let incoming = localSend.incoming, incoming.phase == .receiving { return incoming.fraction }
        if let outgoing = localSend.outgoing, outgoing.phase == .sending { return outgoing.fraction }
        return nil
    }

    /// A message only takes the banner when nothing with a transfer does.
    private var showsMessage: Bool {
        localSend.message != nil && localSend.pendingRequest == nil
            && localSend.incoming == nil && localSend.outgoing == nil
    }

    private var waiting: Bool {
        localSend.incoming == nil && localSend.outgoing?.phase == .waitingForAcceptance
    }
}
