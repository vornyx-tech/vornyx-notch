//
//  DashboardView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// One tab holding the three things you glance at rather than work in:
/// the month on the left, website shortcuts in the middle, AI on the right.
struct DashboardView: View {
    @EnvironmentObject var vm: VornyxViewModel
    @Default(.aiEnabled) private var aiEnabled

    @State private var selectedDate = Date()

    private let gridWidth: CGFloat = 168
    private let agendaWidth: CGFloat = 150
    private let shortcutsWidth: CGFloat = 190

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MonthCalendarView(selectedDate: $selectedDate)
                .frame(width: gridWidth)

            DayAgendaView(date: selectedDate)
                .frame(width: agendaWidth)

            divider

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Shortcuts")
                ShortcutsGridView()
                Spacer(minLength: 0)
            }
            .frame(width: shortcutsWidth)

            divider

            VStack(alignment: .leading, spacing: 6) {
                if aiEnabled {
                    AIChatView()
                        .environmentObject(vm)
                } else {
                    aiDisabled
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .kerning(0.6)
    }

    private var aiDisabled: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("AI is off")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Turn on in Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
