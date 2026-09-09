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
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    VornyxHeader().environmentObject(VornyxViewModel())
}
