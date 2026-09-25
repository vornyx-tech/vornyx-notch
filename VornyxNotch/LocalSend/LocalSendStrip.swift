//
//  LocalSendStrip.swift
//  VornyxNotch
//
//  The row of LocalSend devices under the open notch.
//

import AppKit
import SwiftUI

/// Devices, files waiting to go to them, and whatever transfer is in flight.
///
/// A drag over the notch turns the row into one wide drop area - aiming at a
/// small tile while holding a file does not work with more than a couple of
/// devices. What is dropped stays pinned, like on the shelf, until a device is
/// picked and Send pressed, or it goes in the trash.
///
/// Always under the shelf; on other tabs it appears while something is dragged
/// over the notch or files are pinned, stretching it down the way the camera
/// does. Always one row, so the notch never changes height between states.
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
    /// A drag from outside is over the notch.
    @State private var showsDropArea = false
    @State private var dropAreaLinger: Task<Void, Never>?

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
            } else if showsDropArea {
                dropArea
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if !localSend.staged.isEmpty {
                stagedRow
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
        .animation(.smooth(duration: 0.2), value: showsDropArea)
        .animation(.smooth(duration: 0.2), value: localSend.staged.isEmpty)
        .onChange(of: vm.anyDropZoneTargeting) { _, dragging in updateDropArea(dragging: dragging) }
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

    /// Where text and pinned files go: the picked device, or the only one
    /// there is.
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
                    Text("Drag files here to send")
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

/// A device to pick. Files no longer go by dropping on a tile - the whole row
/// becomes a drop area for that - so a tile only ever needs to be clicked.
private struct DeviceTile: View {
    let device: LocalSendDevice
    let isSelected: Bool
    var width: CGFloat = 104
    let toggle: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 10), style: .continuous)

        Button(action: toggle) {
            VStack(spacing: 6) {
                Image(systemName: device.symbol)
                    .font(.system(size: 20, weight: .medium))
                Text(device.alias)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.8))
            .padding(.horizontal, 8)
            .frame(width: width, height: localSendStripHeight - 24)
            // The accent tint marks the selection; the rest are frosted glass.
            .notchSurface(
                shape, fill: isSelected ? 0.14 : 0.07, stroke: 0,
                tint: isSelected && !NotchGlass.isActive ? Color.effectiveAccent.opacity(0.35) : nil,
                glassTint: isSelected ? Color.effectiveAccent.opacity(0.6) : nil,
                frosted: !isSelected)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(shape.strokeBorder(.white.opacity(NotchGlass.isActive ? 0 : 0.08), lineWidth: 1))
            .contentShape(shape)
        }
        .springyTile(hoverScale: 1.04, pressScale: 0.95, hoverBrightness: 0.08)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .help("\(device.alias) - \(device.host)")
    }
}

// MARK: - Dropping and pinned files

extension LocalSendStrip {
    /// Shows the drop area as soon as a drag from outside arrives, and takes
    /// it away a beat after the last one leaves: the flag blinks off for a
    /// frame as the pointer passes between drop targets.
    fileprivate func updateDropArea(dragging: Bool) {
        dropAreaLinger?.cancel()
        if dragging {
            // A pinned file on its way to the trash is not a new drop.
            guard localSend.draggingStaged == nil else { return }
            showsDropArea = true
            return
        }
        dropAreaLinger = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            showsDropArea = false
        }
    }

    /// The whole row, one target.
    fileprivate var dropArea: some View {
        LocalSendDropArea(pinnedCount: localSend.staged.count) { providers in
            dropAreaLinger?.cancel()
            showsDropArea = false
            Task { @MainActor in
                let urls = await LocalSendDrop.fileURLs(from: providers)
                if !urls.isEmpty {
                    localSend.stage(urls)
                } else if let text = await LocalSendDrop.text(from: providers), let target = textTarget {
                    // No file in the drag: text or a link goes as a message.
                    localSend.sendText(text, to: target)
                }
            }
        }
        .padding(8)
    }

    /// Pinned files, the devices to pick from, Send and the trash.
    fileprivate var stagedRow: some View {
        let target = textTarget

        return HStack(spacing: 10) {
            FadingHorizontalScroll {
                HStack(spacing: 6) {
                    ForEach(localSend.staged, id: \.self) { url in
                        StagedFileTile(url: url)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 210)
            .fixedSize(horizontal: localSend.staged.count <= 2, vertical: false)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1, height: localSendStripHeight - 36)

            if localSend.devices.isEmpty {
                HStack(spacing: 8) {
                    if localSend.isScanning { ProgressView().controlSize(.mini) }
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
                                isSelected: device.fingerprint == target?.fingerprint,
                                width: 88,
                                toggle: { toggleSelection(device) })
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                guard let target else { return }
                localSend.sendStaged(to: target)
                selectedFingerprint = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Send")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .notchSurface(Capsule(), stroke: 0, tint: Color.effectiveAccent.opacity(0.9))
                .contentShape(Capsule())
            }
            .springyTile(hoverScale: 1.05, pressScale: 0.94, hoverBrightness: 0.1)
            .disabled(target == nil)
            .opacity(target == nil ? 0.5 : 1)
            .help(target.map {
                "Send \(localSend.staged.count) file\(localSend.staged.count == 1 ? "" : "s") to \($0.alias)"
            } ?? "Pick a device first")

            StagedTrash()
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }
}

/// One wide target for a drag, instead of a tile per device.
private struct LocalSendDropArea: View {
    @EnvironmentObject var vm: VornyxViewModel
    let pinnedCount: Int
    let onDrop: ([NSItemProvider]) -> Void

    @State private var targeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 8), style: .continuous)

        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 22, weight: .medium))
                .symbolEffect(.bounce, value: targeted)
            VStack(alignment: .leading, spacing: 2) {
                Text(targeted ? "Let go to pin it" : "Drop here to send with LocalSend")
                    .font(.system(size: 13, weight: .semibold))
                Text(pinnedCount > 0
                     ? "Joins the \(pinnedCount) already pinned. Pick a device next."
                     : "Then pick a device and press Send.")
                    .font(.system(size: 10))
                    .opacity(0.6)
            }
        }
        .foregroundStyle(.white.opacity(targeted ? 1 : 0.8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .notchSurface(
            shape, fill: targeted ? 0.12 : 0.06, stroke: 0,
            glassTint: targeted ? Color.effectiveAccent.opacity(0.35) : nil)
        .overlay(
            shape.strokeBorder(
                targeted ? Color.effectiveAccent.opacity(0.95) : .white.opacity(0.25),
                style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, lineCap: .round, dash: [6, 5])))
        .scaleEffect(targeted ? 1.01 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .contentShape(shape)
        .onDrop(of: [.fileURL, .url, .data, .utf8PlainText, .plainText], isTargeted: targetBinding) { providers in
            // Counts as a real drop, so the notch does not close under it.
            vm.dropEvent = true
            onDrop(providers)
            return true
        }
    }

    /// Mirrored into the view model, so hovering here still counts as
    /// hovering the notch.
    private var targetBinding: Binding<Bool> {
        Binding(
            get: { targeted },
            set: { value in
                targeted = value
                vm.dropZoneTargeting = value
            })
    }
}

/// A pinned file: its thumbnail and name. Drag it to the trash to unpin it.
private struct StagedFileTile: View {
    let url: URL

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 28, height: 28)

            // Two lines, so a name like "Vornyx Notch v1.1.dmg" still reads.
            Text(url.lastPathComponent)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
        .frame(width: 96, height: localSendStripHeight - 24)
        .notchSurface(
            RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 10), style: .continuous),
            fill: 0.06, stroke: 0, frosted: true)
        .contentShape(Rectangle())
        .help(url.lastPathComponent)
        .onDrag {
            LocalSendManager.shared.draggingStaged = url
            // SwiftUI says nothing when a drag ends, so watch the button.
            Task { @MainActor in
                while NSEvent.pressedMouseButtons & 1 != 0 {
                    try? await Task.sleep(for: .milliseconds(120))
                }
                // Leave the trash's drop handler time to read it first.
                try? await Task.sleep(for: .milliseconds(300))
                LocalSendManager.shared.draggingStaged = nil
            }
            return NSItemProvider(object: url as NSURL)
        }
        .task(id: url) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: url, size: CGSize(width: 64, height: 64))
        }
    }
}

/// Unpins one file dropped on it, or all of them on a double-click.
private struct StagedTrash: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var localSend = LocalSendManager.shared

    @State private var targeted = false

    var body: some View {
        Image(systemName: targeted ? "trash.fill" : "trash")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(targeted ? .white : .white.opacity(0.7))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 30, height: 30)
            .notchSurface(Circle(), fill: 0.1, stroke: 0, tint: targeted ? Color.red.opacity(0.85) : nil)
            .scaleEffect(targeted ? 1.18 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: targeted)
            .contentShape(Circle())
            .onTapGesture(count: 2) { localSend.clearStaged() }
            .help("Drag a file here to unpin it. Double-click to unpin all.")
            .onDrop(of: [.fileURL], isTargeted: targetBinding) { providers in
                vm.dropEvent = true
                if let dragged = localSend.draggingStaged {
                    localSend.unstage(dragged)
                    localSend.draggingStaged = nil
                    return true
                }
                // A drag that did not start here: unpin it only if it is pinned.
                Task { @MainActor in
                    for provider in providers {
                        if let url = await provider.extractFileURL() { localSend.unstage(url) }
                    }
                }
                return true
            }
    }

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
