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

    @Default(.dashboardLeftPage) private var storedPage

    /// The page being drawn, mirrored from the stored one.
    ///
    /// Animating the stored value directly does not slide: a `@Default` change
    /// arrives through its own publisher, outside the transaction `withAnimation`
    /// set up, so the swap lands instantly and the transition never runs. Local
    /// state moves under the animation; the setting follows behind it.
    @State private var leftPage: DashboardLeftPage = Defaults[.dashboardLeftPage]

    @State private var selectedDate = Date()
    /// Which way the last page change went, so the incoming page slides in from
    /// the side you swiped towards.
    @State private var pageDirection: Int = 1

    private let gridWidth: CGFloat = 168
    private let agendaWidth: CGFloat = 150
    private let shortcutsWidth: CGFloat = 190

    /// The month and the agenda are one page, and the weather is the other, so
    /// the zone they share is what the swipe and the dots belong to.
    private var leftZoneWidth: CGFloat { gridWidth + 12 + agendaWidth }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leftZone

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
        // Fill the notch's height rather than asking for the content's ideal
        // one. `fixedSize(vertical:)` here would hand the chat's ScrollView its
        // full transcript height: the tab would grow past the notch silhouette
        // and past the hover region, and the transcript would never scroll.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - The paged left-hand zone

    private var leftZone: some View {
        VStack(spacing: 4) {
            ZStack {
                switch leftPage {
                case .calendar:
                    calendarPage.transition(pageTransition)
                case .weather:
                    WeatherView().transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Keeps the outgoing page inside its own column: without this it
            // slides out across the divider and over the shortcuts.
            .clipped()
            .animation(VornyxViewCoordinator.tabChangeAnimation, value: leftPage)

            pageDots
        }
        .frame(width: leftZoneWidth)
        // Pointer-scoped, so a sideways swipe only pages here - over the
        // shortcuts or the chat it goes back to meaning nothing.
        .horizontalSwipe { direction in
            step(by: direction == .right ? 1 : -1)
        }
    }

    private var calendarPage: some View {
        HStack(alignment: .top, spacing: 12) {
            MonthCalendarView(selectedDate: $selectedDate)
                .frame(width: gridWidth)

            DayAgendaView(date: selectedDate)
                .frame(width: agendaWidth)
        }
    }

    /// Two dots under the zone, the way a paged view says how many there are
    /// and which one you are on. Clickable as well as swipeable - a swipe is
    /// not discoverable on its own.
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(DashboardLeftPage.allCases, id: \.self) { page in
                Button {
                    guard page != leftPage else { return }
                    step(by: page == .weather ? 1 : -1)
                } label: {
                    Circle()
                        .fill(.white.opacity(page == leftPage ? 0.75 : 0.22))
                        .frame(width: 5, height: 5)
                        .contentShape(Circle().inset(by: -5))
                }
                .buttonStyle(.plain)
                .help(page == .weather ? "Weather" : "Calendar")
            }
        }
        .animation(.smooth(duration: 0.2), value: leftPage)
        .padding(.bottom, 2)
    }

    /// Stops at the ends rather than wrapping, so a run of swipes cannot spin
    /// the pair round and round - the same rule the tabs follow.
    private func step(by offset: Int) {
        let pages = DashboardLeftPage.allCases
        guard let index = pages.firstIndex(of: leftPage) else { return }
        let next = (index + offset).clamped(to: 0...(pages.count - 1))
        guard next != index else { return }

        pageDirection = offset
        withAnimation(VornyxViewCoordinator.tabChangeAnimation) {
            leftPage = pages[next]
        }
        storedPage = pages[next]
        if pages[next] == .weather { WeatherManager.shared.refreshIfStale() }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: pageDirection > 0 ? .trailing : .leading),
            removal: .move(edge: pageDirection > 0 ? .leading : .trailing)
        )
        .combined(with: .opacity)
    }

    /// A column separator.
    ///
    /// Brighter in the middle than at the ends: a hard line running the full
    /// height reads as a border and boxes the columns in, while a line that
    /// fades out at both ends reads as a separation. At a flat 7% white it was
    /// too faint to do either.
    private var divider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.04),
                        .white.opacity(0.20),
                        .white.opacity(0.04),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
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
