//
//  DashboardView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// The month on the left, website shortcuts in the middle, AI on the right.
struct DashboardView: View {
    @EnvironmentObject var vm: VornyxViewModel
    @Default(.aiEnabled) private var aiEnabled

    @Default(.dashboardLeftPage) private var storedPage

    /// The page being drawn, mirrored from the stored one: a `@Default` change
    /// arrives outside the `withAnimation` transaction, so it cannot animate.
    @State private var leftPage: DashboardLeftPage = Defaults[.dashboardLeftPage]

    @State private var selectedDate = Date()
    /// Which way the last page change went.
    @State private var pageDirection: Int = 1

    private let gridWidth: CGFloat = 168
    private let agendaWidth: CGFloat = 150
    private let shortcutsWidth: CGFloat = 190

    /// The zone the swipe and the dots belong to.
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
        // Fill the notch's height rather than asking for the content's ideal one.
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
                case .timer:
                    TimerView().transition(pageTransition)
                case .stats:
                    StatsView().transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Keeps the outgoing page inside its own column, open at the bottom
            // by the amount the weather's shower runs past the page.
            .clipShape(ColumnClip(bottomBleed: WeatherPrecipitationStyle.bottomBleed))
            .animation(VornyxViewCoordinator.tabChangeAnimation, value: leftPage)

            pageDots
        }
        .frame(width: leftZoneWidth)
        // Pointer-scoped, so a sideways swipe only pages here.
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

    /// The left zone's clip: exact at the sides, loose at the bottom.
    private struct ColumnClip: Shape {
        let bottomBleed: CGFloat

        func path(in rect: CGRect) -> Path {
            Path(CGRect(
                x: rect.minX, y: rect.minY,
                width: rect.width, height: rect.height + bottomBleed
            ))
        }
    }

    /// A dot per page. Clickable as well as swipeable.
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(DashboardLeftPage.allCases, id: \.self) { page in
                Button {
                    go(to: page)
                } label: {
                    Circle()
                        .fill(.white.opacity(page == leftPage ? 0.75 : 0.22))
                        .frame(width: 5, height: 5)
                        .contentShape(Circle().inset(by: -5))
                }
                // A 5pt dot needs a far bigger lift than a tile to be seen moving.
                .springyTile(hoverScale: 1.6, pressScale: 0.8, hoverBrightness: 0.3)
                .help(page.name)
            }
        }
        .animation(.smooth(duration: 0.2), value: leftPage)
        .padding(.bottom, 2)
    }

    /// Stops at the ends rather than wrapping.
    private func step(by offset: Int) {
        let pages = DashboardLeftPage.allCases
        guard let index = pages.firstIndex(of: leftPage) else { return }
        let next = (index + offset).clamped(to: 0...(pages.count - 1))
        guard next != index else { return }
        go(to: pages[next])
    }

    /// Straight to a page, sliding from whichever side it lives on.
    private func go(to page: DashboardLeftPage) {
        let pages = DashboardLeftPage.allCases
        guard page != leftPage,
              let from = pages.firstIndex(of: leftPage),
              let to = pages.firstIndex(of: page)
        else { return }

        pageDirection = to > from ? 1 : -1
        withAnimation(VornyxViewCoordinator.tabChangeAnimation) {
            leftPage = page
        }
        storedPage = page
        if page == .weather { WeatherManager.shared.refreshIfStale() }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: pageDirection > 0 ? .trailing : .leading),
            removal: .move(edge: pageDirection > 0 ? .leading : .trailing)
        )
        .combined(with: .opacity)
    }

    /// A column separator, brighter in the middle than at the ends.
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
