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
                if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.shelfEnabled] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        if Defaults[.showCalendar] && Defaults[.calendarAsSeparateTab] {
                            tabIconButton(icon: "calendar", target: .calendar)
                        }
                        if Defaults[.showMirror] {
                            if Defaults[.mirrorDisplayMode] == .tab {
                                tabIconButton(icon: "web.camera", target: .camera)
                            } else {
                                Button(action: {
                                    vm.toggleCameraPreview()
                                }) {
                                    Capsule()
                                        .fill(.black)
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
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
        .contentShape(Rectangle())
        .horizontalSwipe { direction in
            guard vm.notchState == .open else { return }
            coordinator.stepTab(by: direction == .right ? 1 : -1)
        }
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
