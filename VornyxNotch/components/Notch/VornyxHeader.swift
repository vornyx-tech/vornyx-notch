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
    @ObservedObject var audio = AudioDeviceManager.shared
    @ObservedObject var pods = AirPodsManager.shared
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
                        // Ahead of the buttons, so the lights sit nearest the
                        // middle of the notch where the eye already is.
                        IndicatorLights(size: 9)
                        if Defaults[.showAudioPicker] {
                            audioOutputMenu
                        }
                        tabIconButton(icon: "rectangle.3.group.fill", target: .dashboard)
                        if Defaults[.showMirror] {
                            headerIconButton(
                                icon: "web.camera",
                                isActive: vm.isCameraExpanded,
                                action: { vm.toggleCameraPreview() }
                            )
                        }
                        if Defaults[.settingsIconInNotch] {
                            headerIconButton(icon: "gear", isActive: false) {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                            }
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
        let content = openNotchWidth(for: coordinator.currentView, showingAirPods: pods.widgetShowing) - 2 * outerInset - 24
        return max(70, (content - vm.closedNotchSize.width) / 2)
    }

    /// A trailing header icon that switches the notch to `target`, and back to
    /// home when it is already showing.
    @ViewBuilder
    private func tabIconButton(icon: String, target: NotchViews) -> some View {
        let isActive = coordinator.currentView == target
        headerIconButton(icon: icon, isActive: isActive) {
            withAnimation(VornyxViewCoordinator.tabChangeAnimation) {
                coordinator.currentView = isActive ? .home : target
            }
        }
    }

    /// Where the sound is going, and a menu to send it somewhere else.
    ///
    /// A menu rather than a panel of our own: this is a list of names with one
    /// of them ticked, which is exactly what a menu is for, and an NSMenu opens
    /// from a non-activating panel where a popover of ours would have to fight
    /// for key status first.
    private var audioOutputMenu: some View {
        Menu {
            ForEach(audio.devices) { device in
                Button {
                    audio.select(device)
                } label: {
                    // The tick is drawn rather than set, because a menu built
                    // from a non-key panel does not get the system's own.
                    Label(
                        device.id == audio.currentID ? "✓  \(device.name)" : "     \(device.name)",
                        systemImage: device.symbol
                    )
                }
            }
            if audio.devices.isEmpty {
                Text("No output devices")
            }
        } label: {
            Image(systemName: audio.current?.symbol ?? "speaker.wave.2.fill")
                .foregroundStyle(.white.opacity(0.6))
                .imageScale(.small)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: headerIconSize.width, height: headerIconSize.height)
        .help(audio.current.map { "Output: \($0.name)" } ?? "Sound output")
        .onAppear { audio.start() }
    }

    /// The shape every trailing header icon wears.
    ///
    /// A stadium the same height as the tab pill on the other side, not a 30pt
    /// circle: a capsule is only round when it is square, and one round button
    /// beside a row of pill-shaped ones reads as a different kind of control
    /// rather than the same kind in a different place.
    ///
    /// Nothing at rest - no fill, no outline. The only thing worth drawing here
    /// is which tab you are on, and giving every button a surface spends that
    /// signal on all of them at once.
    @ViewBuilder
    private func headerIconButton(
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Capsule()
                .fill(isActive ? Color.effectiveAccent.opacity(0.30) : .clear)
                .frame(width: headerIconSize.width, height: headerIconSize.height)
                .overlay {
                    Image(systemName: icon)
                        .foregroundStyle(isActive ? Color.effectiveAccent : .white.opacity(0.6))
                        .imageScale(.small)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .springyTile(hoverScale: 1.08, pressScale: 0.92, hoverBrightness: 0.12)
        .animation(.smooth(duration: 0.18), value: isActive)
    }

    /// Matches `TabButton`'s 26pt height, so both ends of the header sit on the
    /// same line.
    private var headerIconSize: CGSize { .init(width: 34, height: 26) }

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
