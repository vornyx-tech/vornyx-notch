//
//  TabSelectionView.swift
//  VornyxNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
    /// False when `icon` names an asset instead of an SF Symbol.
    var isSystemImage: Bool = true
}

/// The pill of tabs on the left of the header. Ordered the same way
/// `VornyxViewCoordinator.orderedTabs` is, so swiping matches what you see.
@MainActor
var tabs: [TabModel] {
    var tabs = [
        TabModel(label: "Home", icon: "VornyxLogo", view: .home, isSystemImage: false)
    ]
    if Defaults[.shelfEnabled] {
        tabs.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
    }
    if Defaults[.clipboardEnabled] {
        tabs.append(TabModel(label: "Clipboard", icon: "doc.on.clipboard.fill", view: .clipboard))
    }
    // The dashboard lives with the trailing icons, not in this pill - see
    // VornyxHeader. Four tabs here crowded the pill and squashed the logo.
    return tabs
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = VornyxViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(
                        label: tab.label,
                        icon: tab.icon,
                        isSystemImage: tab.isSystemImage,
                        selected: coordinator.currentView == tab.view
                    ) {
                        withAnimation(VornyxViewCoordinator.tabChangeAnimation) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    // The accent, matching the trailing icons: which tab you
                    // are on is the one thing the header has to say, and a grey
                    // fill said it about as loudly as no fill at all.
                    .foregroundStyle(
                        tab.view == coordinator.currentView
                            ? Color.effectiveAccent : Color.white.opacity(0.6)
                    )
                    // Exactly one capsule exists, and it belongs to the
                    // selected tab: `matchedGeometryEffect` slides it from the
                    // old tab to the new one. Rendering it on every tab and
                    // hiding the rest - with `opacity` or `hidden()` - leaves
                    // several live sources sharing one id, and the capsule ends
                    // up stranded on whichever tab SwiftUI happened to pick.
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(Color.effectiveAccent.opacity(0.30))
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        }
                    }
            }
        }
        // No clip. There is nothing to contain - the only background is the
        // selected tab's own capsule, which is exactly its own size - and an
        // outer capsule shaves the sliding one as it crosses the ends, which is
        // what cut the corner off it mid-animation.
        //
        // Fixed size so the header's side frame cannot squeeze the pill either:
        // that frame narrows as the notch changes width between tabs, and the
        // opacity and blur wrapped around it composite to their bounds, so a
        // moment of being too narrow crops the row rather than overflowing it.
        .fixedSize()
    }
}

#Preview {
    VornyxHeader().environmentObject(VornyxViewModel())
}
