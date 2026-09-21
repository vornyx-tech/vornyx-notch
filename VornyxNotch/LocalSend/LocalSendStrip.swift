//
//  LocalSendStrip.swift
//  VornyxNotch
//
//  The row of LocalSend devices under the open notch.
//

import AppKit
import SwiftUI

/// Devices to drop onto, and whatever transfer is in flight.
///
/// Always under the shelf; on other tabs it appears while something is dragged
/// over the notch, stretching it down the way the camera does. Always one row,
/// so the notch never changes height between the two.
struct LocalSendStrip: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var localSend = LocalSendManager.shared
    @ObservedObject private var coordinator = VornyxViewCoordinator.shared

    @State private var composing = false
    /// The device text goes to, by fingerprint. Files go to whichever tile
    /// they are dropped on.
    @State private var selectedFingerprint: String?
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    var body: some View {
        ZStack {
            if let request = localSend.pendingRequest {
                RequestRow(request: request)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if let incoming = localSend.incoming {
                IncomingRow(incoming: incoming)
                    .transition(.opacity)
            } else if let outgoing = localSend.outgoing {
                OutgoingRow(outgoing: outgoing)
                    .transition(.opacity)
            } else if let message = localSend.message {
                MessageRow(message: message)
                    .transition(.opacity)
            } else if composing {
                composeRow
                    .transition(.opacity)
            } else {
                devicesRow
                    .transition(.opacity)
            }
        }
        .frame(height: localSendStripHeight + coordinator.localSendComposeGrowth)
        .frame(maxWidth: .infinity)
        .notchSurface(
            RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous),
            fill: 0.05, stroke: 0.07)
        .animation(.smooth(duration: 0.25), value: localSend.pendingRequest?.id)
        .animation(.smooth(duration: 0.25), value: localSend.incoming?.sessionID)
        .animation(.smooth(duration: 0.25), value: localSend.outgoing?.id)
        .animation(.smooth(duration: 0.25), value: localSend.message?.id)
        .animation(.smooth(duration: 0.2), value: composing)
        // Closing the composer gives the stretched height back.
        .onChange(of: composing) { _, open in
            if !open { setComposeGrowth(0) }
        }
        .onDisappear { coordinator.localSendComposeGrowth = 0 }
        // There is no periodic announcement to rely on, but not on every glance.
        .onAppear { localSend.refreshIfStale() }
    }

    // MARK: - Devices

    /// The picked device, while it is still around.
    private var selectedDevice: LocalSendDevice? {
        localSend.devices.first { $0.fingerprint == selectedFingerprint }
    }

    /// Where text goes: the picked device, or the only one there is.
    private var textTarget: LocalSendDevice? {
        selectedDevice ?? (localSend.devices.count == 1 ? localSend.devices.first : nil)
    }

    private func toggleSelection(_ device: LocalSendDevice) {
        selectedFingerprint = selectedFingerprint == device.fingerprint ? nil : device.fingerprint
    }

    /// Not running, and not on its way up either.
    private var isDown: Bool {
        !localSend.isRunning && !localSend.isRestarting && localSend.availability != .starting
    }

    private var emptyStatus: LocalizedStringKey {
        if localSend.isRestarting || localSend.availability == .starting { return "Restarting LocalSend..." }
        if !localSend.isRunning { return "LocalSend offline" }
        return localSend.isScanning
            ? "Looking for devices..."
            : "Nothing found. Open LocalSend on the other device."
    }

    private var devicesRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.effectiveAccent)
                    Text("LocalSend")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                if case .failed(let error) = localSend.availability, !localSend.isRestarting {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(1)
                        .help(error)
                } else {
                    Text(vm.anyDropZoneTargeting ? "Drop on a device" : "Drag files onto a device")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .frame(width: 108, alignment: .leading)

            if localSend.devices.isEmpty {
                HStack(spacing: 8) {
                    if localSend.isScanning || localSend.isRestarting {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(emptyStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            } else {
                FadingHorizontalScroll {
                    HStack(spacing: 8) {
                        ForEach(localSend.devices) { device in
                            DeviceTile(
                                device: device,
                                isSelected: device.fingerprint == selectedDevice?.fingerprint,
                                toggle: { toggleSelection(device) })
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Nothing to send text through while it is down.
            if localSend.isRunning {
                Button {
                    composing = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Send text")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .notchSurface(Capsule(), stroke: 0, tint: Color.effectiveAccent.opacity(0.9))
                    .contentShape(Capsule())
                }
                .springyTile(hoverScale: 1.05, pressScale: 0.94, hoverBrightness: 0.1)
                // The device is picked on the tiles first.
                .disabled(textTarget == nil)
                .opacity(textTarget == nil ? 0.5 : 1)
                .help(textTarget.map { "Send text to \($0.alias)" } ?? "Select a device to send text to")

                Button {
                    localSend.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(localSend.isScanning ? 0.3 : 0.7))
                        .rotationEffect(.degrees(localSend.isScanning ? 360 : 0))
                        .animation(
                            localSend.isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                            value: localSend.isScanning)
                        .frame(width: 30, height: 30)
                        .notchSurface(Circle(), fill: 0.1, stroke: 0)
                }
                .springyTile(hoverScale: 1.08, pressScale: 0.92, hoverBrightness: 0.12)
                .disabled(localSend.isScanning)
                .help("Look for devices")
            }

            // Always there: LocalSend can go deaf after sleep or a network
            // change while still counting as running, and a refresh then finds
            // nobody however often it is pressed.
            Button {
                localSend.restart()
            } label: {
                Image(systemName: "restart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(localSend.isRestarting ? 0.3 : (isDown ? 1 : 0.7)))
                    .frame(width: 30, height: 30)
                    .notchSurface(
                        Circle(), fill: 0.1, stroke: 0,
                        tint: isDown ? Color.effectiveAccent.opacity(0.9) : nil)
            }
            .springyTile(hoverScale: 1.08, pressScale: 0.92, hoverBrightness: 0.12)
            .disabled(localSend.isRestarting || localSend.availability == .starting)
            .help("Restart LocalSend")
        }
        // More room on the left, where the label is text against a rounded corner.
        .padding(.leading, 20)
        .padding(.trailing, 12)
    }
}

// MARK: - Sending text

extension LocalSendStrip {
    /// Type and send, to the device picked on the tiles. Long text stretches
    /// the field, and the notch with it, down a few lines.
    fileprivate var composeRow: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let target = textTarget

        return HStack(alignment: .bottom, spacing: 10) {
            if let target {
                Image(systemName: target.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 26, height: 32)
                    .help("To \(target.alias)")
            }

            TextField(
                target.map { LocalizedStringKey("Text to \($0.alias)") } ?? "Text to send",
                text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1...6)
                .focused($draftFocused)
                .onSubmit {
                    guard !empty, let target else { return }
                    sendDraft(to: target)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                // Round ends on one line, still a sensible shape on six.
                .notchSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), fill: 0.08, stroke: 0)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    setComposeGrowth(height + localSendComposeMargin - localSendStripHeight)
                }

            Button {
                guard let target else { return }
                sendDraft(to: target)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .notchSurface(Circle(), stroke: 0, tint: Color.effectiveAccent.opacity(0.9))
            }
            .springyTile(hoverScale: 1.08, pressScale: 0.92, hoverBrightness: 0.12)
            .disabled(empty || target == nil)
            .opacity(empty || target == nil ? 0.4 : 1)
            .help(target.map { "Send to \($0.alias)" } ?? "Select a device first")
            .padding(.bottom, 3)

            Button {
                draft = ""
                composing = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 26, height: 26)
                    .notchSurface(Circle(), fill: 0.08, stroke: 0)
            }
            .springyTile(hoverScale: 1.08, pressScale: 0.92, hoverBrightness: 0.12)
            .help("Cancel")
            .padding(.bottom, 3)
        }
        .padding(.horizontal, 12)
        .onAppear {
            // Opened by a click, so taking the keyboard is expected here.
            VornyxNotchSkyLightWindow.setKeyboardInputEnabled(true)
            DispatchQueue.main.async { draftFocused = true }
        }
    }

    /// Stretch the strip, within its allowance. Rounded to whole points and only
    /// moved on a real change, so the notch's spring is not set going again.
    fileprivate func setComposeGrowth(_ growth: CGFloat) {
        let clamped = min(max(0, growth), localSendComposeMaxGrowth).rounded()
        guard abs(clamped - coordinator.localSendComposeGrowth) >= 1 else { return }
        withAnimation(.smooth(duration: 0.25)) {
            coordinator.localSendComposeGrowth = clamped
        }
    }

    fileprivate func sendDraft(to device: LocalSendDevice) {
        localSend.sendText(draft, to: device)
        draft = ""
        composing = false
    }
}

// MARK: - Device tile

private struct DeviceTile: View {
    @EnvironmentObject var vm: VornyxViewModel
    let device: LocalSendDevice
    let isSelected: Bool
    let toggle: () -> Void

    @State private var targeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 10), style: .continuous)
        // A drop hovering counts as picked for as long as it hovers.
        let lit = isSelected || targeted

        Button(action: toggle) {
            VStack(spacing: 6) {
                Image(systemName: device.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .symbolEffect(.bounce, value: targeted)
                Text(device.alias)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // White on the accent glass.
            .foregroundStyle(targeted && !NotchGlass.isActive ? Color.effectiveAccent : .white.opacity(lit ? 0.95 : 0.8))
            .padding(.horizontal, 8)
            .frame(width: 104, height: localSendStripHeight - 24)
            // The accent tint marks the selection; the rest are frosted glass.
            .notchSurface(
                shape, fill: lit ? 0.14 : 0.07, stroke: 0,
                tint: lit && !NotchGlass.isActive ? Color.effectiveAccent.opacity(0.35) : nil,
                glassTint: lit ? Color.effectiveAccent.opacity(targeted ? 0.8 : 0.6) : nil,
                frosted: !lit)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(
                shape.strokeBorder(
                    targeted ? Color.effectiveAccent.opacity(0.95) : .white.opacity(NotchGlass.isActive ? 0 : 0.08),
                    style: targeted
                        ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
                        : StrokeStyle(lineWidth: 1)))
            .contentShape(shape)
        }
        .springyTile(hoverScale: 1.04, pressScale: 0.95, hoverBrightness: 0.08)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .scaleEffect(targeted ? 1.05 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .help("\(device.alias) - \(device.host)")
        .onDrop(of: [.fileURL, .url, .data, .utf8PlainText, .plainText], isTargeted: targetBinding) { providers in
            // Counts as a real drop, so the notch does not close under the send.
            vm.dropEvent = true
            Task { @MainActor in
                let urls = await LocalSendDrop.fileURLs(from: providers)
                // No file in the drag: text or a link goes as a message instead.
                if urls.isEmpty, let text = await LocalSendDrop.text(from: providers) {
                    LocalSendManager.shared.sendText(text, to: device)
                } else {
                    LocalSendManager.shared.send(urls, to: device)
                }
            }
            return true
        }
    }

    /// Mirrored into the view model, so a drag hovering a device still counts
    /// as hovering the notch.
    private var targetBinding: Binding<Bool> {
        Binding(
            get: { targeted },
            set: { value in
                targeted = value
                vm.dropZoneTargeting = value
            })
    }
}

/// A sideways scrolling row that fades out at an edge with more of it past
/// that edge, and only at such an edge.
private struct FadingHorizontalScroll<Content: View>: View {
    @ViewBuilder let content: Content

    private let fade: CGFloat = 22
    /// Room past the row's own edges for a tile growing under the pointer or a
    /// drop, which the scroll view's clip would otherwise shave flat.
    private let bleed: CGFloat = 6
    private let space = "fadingHorizontalScroll"

    @State private var width: CGFloat = 0
    @State private var frame: CGRect = .zero

    var body: some View {
        let before = frame.minX < -0.5
        let after = frame.maxX > width + 0.5

        ScrollView(.horizontal) {
            content
                .padding(.horizontal, bleed)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frame = $0 }
        }
        .coordinateSpace(.named(space))
        .scrollIndicators(.never)
        .scrollableNotchContent()
        // The scroll view's own width, which the content's frame is measured against.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .mask(
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.white.opacity(before ? 0 : 1), .white],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
                Rectangle().fill(.white)
                LinearGradient(
                    colors: [.white, .white.opacity(after ? 0 : 1)],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
            }
            .animation(.smooth(duration: 0.2), value: before)
            .animation(.smooth(duration: 0.2), value: after)
        )
        // Given back outside, so the tiles sit where they did. After the mask,
        // which is laid out in the frame of what it masks.
        .padding(.horizontal, -bleed)
    }
}

/// Turns whatever was dropped into files on disk.
enum LocalSendDrop {
    /// File URLs where the drag carried them, otherwise whatever the shelf's
    /// own drop handling can turn into a file.
    @MainActor
    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        var leftovers: [NSItemProvider] = []
        for provider in providers {
            if let url = await provider.extractFileURL() {
                urls.append(url)
            } else {
                leftovers.append(provider)
            }
        }
        if !leftovers.isEmpty {
            for item in await ShelfDropService.items(from: leftovers) {
                if case .file(let bookmark) = item.kind, let url = Bookmark(data: bookmark).resolve().url {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    /// Text, or a web link as text, for a drop that carried no file.
    @MainActor
    static func text(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if let text = await provider.extractText(), !text.isEmpty { return text }
            if let url = await provider.extractURL(), !url.isFileURL { return url.absoluteString }
        }
        return nil
    }
}

// MARK: - Transfer rows

private struct RequestRow: View {
    let request: LocalSendIncomingRequest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.effectiveAccent)
                .symbolEffect(.pulse)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(request.sender.alias) wants to send you")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Text(summary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button("Decline") { LocalSendManager.shared.declinePendingRequest() }
                .buttonStyle(StripButtonStyle(prominent: false))
            Button("Accept") { LocalSendManager.shared.acceptPendingRequest() }
                .buttonStyle(StripButtonStyle(prominent: true))
        }
        .padding(.horizontal, 14)
    }

    private var summary: String {
        let size = ByteCountFormatter.string(fromByteCount: request.totalSize, countStyle: .file)
        if request.files.count == 1, let file = request.files.first {
            return "\(file.fileName) - \(size)"
        }
        return String(localized: "\(request.files.count) files - \(size)")
    }
}

private struct IncomingRow: View {
    let incoming: LocalSendManager.Incoming

    var body: some View {
        switch incoming.phase {
        case .receiving:
            TransferRow(
                symbol: "arrow.down.circle.fill", tint: .effectiveAccent,
                title: String(localized: "Receiving from \(incoming.senderName)"),
                fraction: incoming.fraction, actionTitle: String(localized: "Cancel")
            ) { LocalSendManager.shared.cancelReceiving() }
        case .finished:
            TransferRow(
                symbol: "checkmark.circle.fill", tint: .green,
                title: String(localized: "Received \(incoming.receivedFiles.count) from \(incoming.senderName)"),
                subtitle: String(localized: "Saved to Downloads"),
                actionTitle: incoming.receivedFiles.isEmpty ? nil : String(localized: "Show")
            ) { NSWorkspace.shared.activateFileViewerSelecting(incoming.receivedFiles) }
        case .cancelled:
            TransferRow(
                symbol: "xmark.circle.fill", tint: .white.opacity(0.5),
                title: String(localized: "Transfer from \(incoming.senderName) stopped"),
                subtitle: incoming.receivedFiles.isEmpty
                    ? String(localized: "Nothing was saved")
                    : String(localized: "\(incoming.receivedFiles.count) saved to Downloads"))
        }
    }
}

private struct OutgoingRow: View {
    let outgoing: LocalSendManager.Outgoing

    var body: some View {
        let name = outgoing.device.alias
        switch outgoing.phase {
        case .waitingForAcceptance:
            TransferRow(
                symbol: outgoing.isMessage ? "text.bubble" : "hourglass", tint: .white.opacity(0.7),
                title: outgoing.isMessage
                    ? String(localized: "Sending text to \(name)")
                    : String(localized: "Waiting for \(name) to accept"),
                subtitle: outgoing.isMessage
                    ? String(localized: "Waiting for \(name) to open it")
                    : String(localized: "\(outgoing.fileCount) files"),
                actionTitle: String(localized: "Cancel")
            ) { LocalSendManager.shared.cancelSending() }
        case .sending:
            TransferRow(
                symbol: "arrow.up.circle.fill", tint: .effectiveAccent,
                title: String(localized: "Sending to \(name)"),
                fraction: outgoing.fraction, actionTitle: String(localized: "Cancel")
            ) { LocalSendManager.shared.cancelSending() }
        case .finished:
            TransferRow(
                symbol: "checkmark.circle.fill", tint: .green,
                title: outgoing.isMessage
                    ? String(localized: "Text sent to \(name)")
                    : String(localized: "Sent to \(name)"))
        case .declined:
            TransferRow(symbol: "xmark.circle.fill", tint: .orange, title: String(localized: "\(name) declined"))
        case .busy:
            TransferRow(
                symbol: "exclamationmark.circle.fill", tint: .orange,
                title: String(localized: "\(name) is busy"),
                subtitle: String(localized: "It is in the middle of another transfer"))
        case .cancelled:
            TransferRow(symbol: "xmark.circle.fill", tint: .white.opacity(0.5), title: String(localized: "Cancelled"))
        case .failed(let message):
            TransferRow(
                symbol: "exclamationmark.triangle.fill", tint: .red,
                title: String(localized: "Could not send to \(name)"), subtitle: message)
        }
    }
}

private struct MessageRow: View {
    let message: LocalSendManager.Message

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: message.url == nil ? "text.bubble.fill" : "link.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.effectiveAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Message from \(message.senderName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Text(message.text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            if message.url != nil {
                Button("Open") { LocalSendManager.shared.openMessageLink() }
                    .buttonStyle(StripButtonStyle(prominent: true))
            }
            Button("Copy") { LocalSendManager.shared.copyMessage() }
                .buttonStyle(StripButtonStyle(prominent: message.url == nil))
        }
        .padding(.horizontal, 14)
    }
}

/// Icon, a line of text, then either a progress bar or a second line.
private struct TransferRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var fraction: Double? = nil
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if let fraction {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }

                if let fraction {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule()
                                .fill(tint)
                                .frame(width: max(4, proxy.size.width * fraction))
                                .animation(.smooth(duration: 0.3), value: fraction)
                        }
                    }
                    .frame(height: 5)
                } else if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(StripButtonStyle(prominent: false))
            }
        }
        .padding(.horizontal, 14)
    }
}

/// Accept, Decline, Copy, Cancel and the device buttons of the composer.
private struct StripButtonStyle: ButtonStyle {
    let prominent: Bool

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .notchSurface(
                Capsule(), fill: 0.12, stroke: 0,
                tint: prominent ? Color.effectiveAccent : nil)
            .brightness(hovering && !configuration.isPressed ? 0.1 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : (hovering ? 1.04 : 1))
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: hovering)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }
}
