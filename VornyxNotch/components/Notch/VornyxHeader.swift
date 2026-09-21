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
    @State private var audioMenuHovering = false
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
            // The same curve the notch resizes on, so the icons travel with
            // the edge instead of jumping to where it will be.
            .animation(notchResizeAnimation, value: sideWidth)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            // Always in the row, and only its fill follows the notch state.
            // Removed on close, the gap vanished in the first frame of the
            // animation, the row closed up, and the tab icons jumped towards
            // the middle while they were still fading out.
            Rectangle()
                .fill(fillsCutOut ? .black : .clear)
                .frame(width: vm.closedNotchSize.width)
                .mask {
                    NotchShape()
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
            .animation(notchResizeAnimation, value: sideWidth)
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
    /// Black behind the hardware cut-out while open, on a screen that has one.
    private var fillsCutOut: Bool {
        let top = NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0
        return vm.notchState == .open && top > 0
    }

    private var sideWidth: CGFloat {
        let outerInset = cornerRadiusInsets.opened.top
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
    /// The sound menu, laid out like the one in Control Center: the connected
    /// pair and its levels first, then where the sound goes, then the way to
    /// the system's own settings.
    ///
    /// Listening mode, spatial audio and conversation awareness are missing on
    /// purpose. macOS keeps them behind entitlements only Apple's own apps are
    /// signed with; the calls that look like they set them change a value in
    /// this process and never reach the pair.
    private var audioOutputMenu: some View {
        Menu {
            if let pair = pods.device {
                Section {
                    Label(pair.name, systemImage: pair.model.symbol)
                    Text(batterySummary(pair))
                }
            }

            Section("Output") {
                ForEach(audio.devices) { device in
                    Button {
                        audio.select(device)
                    } label: {
                        // The tick is drawn rather than set, because a menu built
                        // from a non-key panel does not get the system's own.
                        Label(
                            device.id == audio.currentID ? "✓  \(device.name)" : "     \(device.name)",
                            systemImage: audio.symbol(for: device)
                        )
                    }
                }
                if audio.devices.isEmpty {
                    Text("No output devices")
                }
            }

            Divider()
            Button("Sound Settings…") {
                openSystemSettings("x-apple.systempreferences:com.apple.preference.sound")
            }
            Button("Bluetooth Settings…") {
                openSystemSettings("x-apple.systempreferences:com.apple.preferences.Bluetooth")
            }
        } label: {
            Image(systemName: audio.current.map(audio.symbol(for:)) ?? "speaker.wave.2.fill")
                .foregroundStyle(.white.opacity(0.6))
                .imageScale(.small)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: headerIconSize.width, height: headerIconSize.height)
        // A menu takes no button style, so the lift the icon buttons beside it
        // get from `springyTile` is given to it directly.
        .scaleEffect(audioMenuHovering ? 1.08 : 1)
        .brightness(audioMenuHovering ? 0.12 : 0)
        .animation(.spring(response: 0.26, dampingFraction: 0.7), value: audioMenuHovering)
        .onHover { audioMenuHovering = $0 }
        .help(audio.current.map { "Output: \($0.name)" } ?? "Sound output")
        .onAppear { audio.start() }
    }

    private func batterySummary(_ pair: AirPodsBattery) -> String {
        var parts: [String] = []
        if let left = pair.left { parts.append("L \(left)%") }
        if let right = pair.right { parts.append("R \(right)%") }
        if let caseLevel = pair.caseLevel { parts.append("Case \(caseLevel)%") }
        if let single = pair.single { parts.append("\(single)%") }
        return parts.joined(separator: "   ")
    }

    private func openSystemSettings(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
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
                .fill(.clear)
                .frame(width: headerIconSize.width, height: headerIconSize.height)
                .background {
                    if isActive { activeIconCapsule }
                }
                .overlay {
                    Image(systemName: icon)
                        .foregroundStyle(isActive ? Color.effectiveAccent : .white.opacity(0.6))
                        .imageScale(.small)
                }
                .contentShape(Capsule())
        }
        // No `.plain` in front of this: a button style nearer the button wins,
        // and `.plain` there left the springy hover with nothing to do.
        .springyTile(hoverScale: 1.08, pressScale: 0.92, hoverBrightness: 0.12)
        .animation(.smooth(duration: 0.18), value: isActive)
    }

    /// Matches `TabButton`'s 26pt height, so both ends of the header sit on the
    /// same line.
    /// The highlight behind an active trailing icon. Clear glass tinted with
    /// the accent while Liquid Glass is on - the same material as the tab pill,
    /// so the two groups in the header are made of one thing - and the accent
    /// wash it has always been when it is off.
    @ViewBuilder
    private var activeIconCapsule: some View {
        if #available(macOS 26.0, *), NotchGlass.isActive {
            Capsule()
                .fill(.clear)
                .glassEffect(.clear.tint(Color.effectiveAccent.opacity(0.55)), in: Capsule())
        } else {
            Capsule()
                .fill(Color.effectiveAccent.opacity(0.30))
        }
    }

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
