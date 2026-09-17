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
/// Always there under the shelf, so it can be found at all - a drop target that
/// only exists mid-drag is one nobody discovers. On other tabs it appears while
/// something is dragged over the notch, stretching it down the way the camera
/// does. One row, whichever of those it is showing, so the notch never changes
/// height between them.
struct LocalSendStrip: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var localSend = LocalSendManager.shared

    @State private var composing = false
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
        .frame(height: localSendStripHeight)
        .frame(maxWidth: .infinity)
        .notchSurface(
            RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous),
            fill: 0.05, stroke: 0.07)
        .animation(.smooth(duration: 0.25), value: localSend.pendingRequest?.id)
        .animation(.smooth(duration: 0.25), value: localSend.incoming?.sessionID)
        .animation(.smooth(duration: 0.25), value: localSend.outgoing?.id)
        .animation(.smooth(duration: 0.25), value: localSend.message?.id)
        .animation(.smooth(duration: 0.2), value: composing)
        // Devices may have come and gone since it was last on screen, and there
        // is no periodic announcement to rely on - but not on every glance.
        .onAppear { localSend.refreshIfStale() }
    }

    // MARK: - Devices

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
                if case .failed(let error) = localSend.availability {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(1)
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
                    if localSend.isScanning {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    if case .failed = localSend.availability {
                        Text("LocalSend offline")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    } else {
                        Text(localSend.isScanning
                             ? "Looking for devices..."
                             : "Nothing found. Open LocalSend on the other device.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(localSend.devices) { device in
                            DeviceTile(device: device)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .scrollableNotchContent()
            }

            if case .failed = localSend.availability {
                Button {
                    localSend.restart()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .notchSurface(Circle(), fill: 0.1, stroke: 0)
                }
                .springyTile(hoverScale: 1.08, pressScale: 0.92, hoverBrightness: 0.12)
                .help("Restart LocalSend")
            } else {
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
                .help("Send text to a device")

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
        }
        // More room on the left than the right: the label is text, and text
        // this close to the strip's rounded corner looks jammed against it,
        // where the round refresh button on the right sits fine at 12.
        .padding(.leading, 20)
        .padding(.trailing, 12)
    }
}

// MARK: - Sending text

extension LocalSendStrip {
    /// Type, then pick who gets it. Return sends straight away when there is
    /// only one device to pick.
    fileprivate var composeRow: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(spacing: 10) {
            TextField("Text to send", text: $draft, axis: .horizontal)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($draftFocused)
                .onSubmit {
                    guard localSend.devices.count == 1, let only = localSend.devices.first else { return }
                    sendDraft(to: only)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .notchSurface(Capsule(), fill: 0.08, stroke: 0)
                .frame(maxWidth: .infinity)

            if localSend.devices.isEmpty {
                Text("No devices found")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(localSend.devices) { device in
                            Button {
                                sendDraft(to: device)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: device.symbol)
                                    Text(device.alias)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(StripButtonStyle(prominent: true))
                            .disabled(empty)
                            .opacity(empty ? 0.45 : 1)
                        }
                    }
                }
                .scrollIndicators(.never)
                .scrollableNotchContent()
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: 300)
            }

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
        }
        .padding(.horizontal, 12)
        .onAppear {
            // Opened by a click, so taking the keyboard is expected here - the
            // chat composer, which appears on its own, deliberately waits.
            VornyxNotchSkyLightWindow.setKeyboardInputEnabled(true)
            DispatchQueue.main.async { draftFocused = true }
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

    @State private var targeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 10), style: .continuous)

        VStack(spacing: 6) {
            Image(systemName: device.symbol)
                .font(.system(size: 20, weight: .medium))
                .symbolEffect(.bounce, value: targeted)
            Text(device.alias)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        // White on the accent glass: accent-coloured type on accent-tinted glass
        // would all but disappear.
        .foregroundStyle(targeted && !NotchGlass.isActive ? Color.effectiveAccent : .white.opacity(0.92))
        .padding(.horizontal, 8)
        .frame(width: 104, height: localSendStripHeight - 24)
        // Tinted in the accent colour, so the devices you can send to stand
        // out from the grey panels around them - and deeper while a drop
        // hovers over one, so it is plain which device will get it.
        .notchSurface(
            shape, fill: targeted ? 0.14 : 0.07, stroke: 0,
            // The same glass as every other surface, with the accent colour as
            // its tint - strong enough to actually see, the way the Send text
            // button's is. At a fifth, the colour vanished into the glass.
            glassTint: Color.effectiveAccent.opacity(targeted ? 0.8 : 0.55))
        .overlay(
            shape.strokeBorder(
                targeted ? Color.effectiveAccent.opacity(0.95) : .white.opacity(NotchGlass.isActive ? 0 : 0.08),
                style: targeted
                    ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
                    : StrokeStyle(lineWidth: 1)))
        .scaleEffect(targeted ? 1.05 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .help("\(device.alias) - \(device.host)")
        .onDrop(of: [.fileURL, .url, .data, .utf8PlainText, .plainText], isTargeted: targetBinding) { providers in
            // Counts as a real drop, so the notch does not close under the send.
            vm.dropEvent = true
            Task { @MainActor in
                let urls = await LocalSendDrop.fileURLs(from: providers)
                // No file in the drag: selected text, or a link dragged out of
                // a browser, goes as a message instead.
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
    /// as hovering the notch and the notch does not close out from under it.
    private var targetBinding: Binding<Bool> {
        Binding(
            get: { targeted },
            set: { value in
                targeted = value
                vm.dropZoneTargeting = value
            })
    }
}

/// Turns whatever was dropped into files on disk.
enum LocalSendDrop {
    /// File URLs where the drag carried them; otherwise whatever the shelf's
    /// own drop handling can turn into a file - an image dragged out of a
    /// browser, say, which only arrives as data.
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
/// Lifts and brightens under the pointer, so it is plain what is clickable.
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
