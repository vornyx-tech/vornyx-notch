//
//  FileShareView.swift
//  VornyxNotch
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct FileShareView: View {
    @EnvironmentObject private var vm: VornyxViewModel
    @StateObject private var quickShare = QuickShareService.shared
    @Default(.quickShareProvider) var quickShareProvider: String

    @State private var hostView: NSView?
    @State private var interactionNonce: UUID = .init()
    @State private var isProcessing = false
    
    @State private var hovering = false

    private var selectedProvider: QuickShareProvider {
        quickShare.availableProviders.first(where: { $0.id == quickShareProvider }) ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
    }

    var body: some View {
        dropArea
            // It opens the share picker when clicked, so it answers the
            // pointer the way the buttons do.
            .brightness(hovering ? 0.06 : 0)
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
            .background(NSViewHost(view: $hostView))
            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data, .image], isTargeted: $vm.dropZoneTargeting) { providers in
                interactionNonce = .init()
                vm.dropEvent = true
                Task { await handleDrop(providers) }
                return true
            }
            .onTapGesture {
                Task {
                    await handleClick()
                }
            }
    }

    private var dropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous)
                .fill(.clear)
                .notchSurface(
                    RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous),
                    fill: vm.dropZoneTargeting ? 0.10 : 0.05, stroke: 0,
                    glassTint: vm.dropZoneTargeting ? Color.effectiveAccent.opacity(0.3) : nil)
                .overlay(
                    RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous)
                        .strokeBorder(
                            vm.dropZoneTargeting
                                ? Color.effectiveAccent.opacity(0.95)
                                : Color.white.opacity(NotchGlass.isActive ? 0 : 0.08),
                            style: vm.dropZoneTargeting
                                ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5])
                                : StrokeStyle(lineWidth: 1)
                        )
                )
                .animation(.smooth(duration: 0.18), value: vm.dropZoneTargeting)

            // Content
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(
                            vm.dropZoneTargeting ? 0.11 : 0.09
                        ))
                        .frame(width: 55, height: 55)
                    Image(systemName: "square.and.arrow.up")
                    Group {
                        if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .frame(width: 34, height: 34)
                        .foregroundStyle(
                            vm.dropZoneTargeting ? Color.accentColor : Color.gray
                        )
                        .scaleEffect(
                            vm.dropZoneTargeting ? 1.06 : 1.0
                        )
                        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: vm.dropZoneTargeting)
                }

                Text(selectedProvider.id)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))

            }
            .padding(18)
            
            // Loading overlay
            if isProcessing || quickShare.isPickerOpen {
                RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous)
                    .fill(.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous))
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) async {
        isProcessing = true
        defer { isProcessing = false }
        await quickShare.shareDroppedFiles(providers, using: selectedProvider, from: hostView)
    }
    
    private func handleClick() async {
        await quickShare.showFilePicker(for: selectedProvider, from: hostView)
    }
}

// MARK: - Host NSView extractor for anchoring share sheet

private struct NSViewHost: NSViewRepresentable {
    @Binding var view: NSView?
    
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { self.view = v }
        return v
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.view = nsView }
    }
}
