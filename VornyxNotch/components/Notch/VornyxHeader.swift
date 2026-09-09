//
//  VornyxHeader.swift
//  VornyxNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct VornyxHeader: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = VornyxViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                // Show the pill whenever there is more than one tab in it -
                // the shelf may be off while the clipboard is on.
                if tabs.count > 1 && (!tvm.isEmpty || coordinator.alwaysShowTabs
                                      || !Defaults[.shelfEnabled]) {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(width: sideWidth, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        tabIconButton(icon: "rectangle.3.group.fill", target: .dashboard)
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(vm.isCameraExpanded
                                          ? Color(nsColor: .secondarySystemFill) : .black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "web.camera")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showBatteryIndicator] {
                            VornyxBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(width: sideWidth, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
        .contentShape(Rectangle())
        .horizontalSwipe(threshold: swipeThreshold) { direction in
            guard vm.notchState == .open else { return }
            coordinator.stepTab(by: direction == .right ? 1 : -1)
        }
    }

    /// How far you must swipe to turn a page. Follows the gesture sensitivity
    /// setting, so "Very low" means a deliberate swipe rather than a flick -
    /// and, with the one-page-per-gesture latch, exactly one tab per swipe.
    private var swipeThreshold: CGFloat {
        max(24, Defaults[.gestureSensitivity] / 4)
    }

    /// Space available either side of the physical notch.
    ///
    /// The middle of the header is reserved for the real notch cut-out. Letting
    /// the two icon groups share the remaining width with maxWidth: .infinity
    /// meant that once they outgrew it they spilled inwards, putting icons
    /// underneath the cut-out where they cannot be seen or clicked.
    private var sideWidth: CGFloat {
        let outerInset = Defaults[.cornerRadiusScaling]
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.opened.bottom
        let content = openNotchWidth(for: coordinator.currentView) - 2 * outerInset - 24
        return max(70, (content - vm.closedNotchSize.width) / 2)
    }

    /// A trailing header icon that switches the notch to `target`, and back to
    /// home when it is already showing.
    @ViewBuilder
    private func tabIconButton(icon: String, target: NotchViews) -> some View {
        let isActive = coordinator.currentView == target
        Button {
            withAnimation(VornyxViewCoordinator.tabChangeAnimation) {
                coordinator.currentView = isActive ? .home : target
            }
        } label: {
            Capsule()
                .fill(isActive ? Color(nsColor: .secondarySystemFill) : .black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: icon)
                        .foregroundColor(.white)
                        .padding()
                        .imageScale(.medium)
                }
        }
        .buttonStyle(PlainButtonStyle())
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    VornyxHeader().environmentObject(VornyxViewModel())
}
