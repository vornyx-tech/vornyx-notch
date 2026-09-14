//
//  ShelfItemView.swift
//  VornyxNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit

struct ShelfView: View {
    @EnvironmentObject var vm: VornyxViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // A drop that goes nowhere is silent at three separate points - here,
        // in the type handling, and in the bookmark - so each one says so.
        guard !selection.isDragging else {
            NSLog("SHELF-DROP: refused, a shelf item is mid-drag")
            return false
        }
        NSLog("SHELF-DROP: accepted \(providers.count) provider(s)")
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        // A permanent dashed outline reads as unfinished, and spends the
        // "you can drop here" signal before there is anything to drop. At rest
        // this is a plain surface; the dashes appear only while a drag is over
        // it, which is the moment they actually mean something.
        RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous)
            .fill(.clear)
            .notchSurface(
                RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous),
                fill: vm.dragDetectorTargeting ? 0.10 : 0.05, stroke: 0,
                glassTint: vm.dragDetectorTargeting ? Color.effectiveAccent.opacity(0.3) : nil)
            .overlay(
                RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous)
                    .strokeBorder(
                        vm.dragDetectorTargeting
                            ? Color.effectiveAccent.opacity(0.95)
                            : Color.white.opacity(NotchGlass.isActive ? 0 : 0.08),
                        style: vm.dragDetectorTargeting
                            ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5])
                            : StrokeStyle(lineWidth: 1)
                    )
            )
            .animation(.smooth(duration: 0.18), value: vm.dragDetectorTargeting)
            // Clearing belongs to the panel's own surface, *underneath* the
            // items. Applied after the overlay it covered them as well: an item
            // selected itself on mouse-down and this then cleared it on the
            // mouse-up of the very same click, so nothing could stay selected.
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .scrollableNotchContent()
                // The row covers the panel once there are items on it, so the
                // gap between and around them needs its own way to clear.
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { selection.clear() }
                )
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
