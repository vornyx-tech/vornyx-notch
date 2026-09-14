//
//  MonthCalendarView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// A compact month grid: weekday initials across the top, the current month's
/// days in bold, neighbouring days dimmed, today in a filled circle, and a dot
/// under any day that has something on it.
///
/// Only ever the current month - the notch is a glance surface, not somewhere
/// to plan next March.
struct MonthCalendarView: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Binding var selectedDate: Date

    @State private var today = Date()
    @State private var hoveredDay: Date?
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var calendar: Calendar {
        var calendar = Calendar.current
        // Monday-first, matching the M T W T F S S header.
        calendar.firstWeekday = 2
        return calendar
    }

    /// Always six week rows, so the grid never changes height month to month.
    private var days: [Date] {
        let calendar = calendar
        guard
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: today))
        else { return [] }

        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: monthStart)
        else { return [] }

        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The colours of what is on each day of the visible month, up to three.
    ///
    /// Colours rather than a count: the calendar a thing belongs to is the fact
    /// you actually want off a month grid - work, or personal, or a birthday -
    /// and a row of identical accent dots cannot tell you that.
    private var busyColors: [Int: [Color]] {
        var map: [Int: [Color]] = [:]
        for event in calendarManager.monthEvents
        where calendar.isDate(event.start, equalTo: today, toGranularity: .month) {
            let day = calendar.component(.day, from: event.start)
            var colors = map[day] ?? []
            guard colors.count < 3, !colors.contains(event.accentColor) else { continue }
            colors.append(event.accentColor)
            map[day] = colors
        }
        return map
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        VStack(spacing: 4) {
            header

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(isWeekend(index) ? 0.22 : 0.38))
                        .textCase(.uppercase)
                }
            }

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .onReceive(clock) { now in
            // Only redraw when the day actually rolls over.
            if !calendar.isDate(now, inSameDayAs: today) { today = now }
        }
        .onAppear {
            today = .now
            Task { await calendarManager.updateVisibleMonth(.now) }
        }
        .onChange(of: calendarManager.selectedCalendarIDs) {
            Task { await calendarManager.updateVisibleMonth(today) }
        }
    }

    /// Month in full, year as a quiet chip beside it - the year is context, not
    /// news, and giving it the same weight as the month made the two compete.
    private var header: some View {
        HStack(spacing: 5) {
            Text(today, format: .dateTime.month(.wide))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(today, format: .dateTime.year())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .notchSurface(Capsule(), fill: 0.08, stroke: 0)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 1)
    }

    /// The last two columns, whichever weekday the grid starts on.
    private func isWeekend(_ column: Int) -> Bool { column >= 5 }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let inMonth = calendar.isDate(day, equalTo: today, toGranularity: .month)
        let number = calendar.component(.day, from: day)
        let colors = inMonth ? (busyColors[number] ?? []) : []
        let hovered = hoveredDay == day

        Button {
            withAnimation(.smooth(duration: 0.15)) { selectedDate = day }
        } label: {
            ZStack {
                if isToday {
                    // Lit, not painted: the same halo the weather icon wears.
                    Circle()
                        .fill(Color.effectiveAccent)
                        .blur(radius: 6)
                        .opacity(0.6)
                    Circle().fill(Color.effectiveAccent)
                } else if isSelected {
                    Circle().fill(Color.effectiveAccent.opacity(0.16))
                    Circle().strokeBorder(Color.effectiveAccent.opacity(0.85), lineWidth: 1.5)
                } else if hovered && inMonth {
                    Circle().fill(.white.opacity(0.10))
                }

                Text("\(number)")
                    .font(.system(
                        size: 10.5,
                        weight: isToday ? .bold : (inMonth ? .medium : .regular),
                        design: .rounded
                    ))
                    .foregroundStyle(
                        isToday ? .white : (inMonth ? Color.white.opacity(0.9) : Color.white.opacity(0.2))
                    )
                    .monospacedDigit()
            }
            .frame(width: 19, height: 19)
            .overlay(alignment: .bottom) {
                // One dot per calendar the day has something in, so a glance
                // says what kind of day it is and not merely that it is busy.
                HStack(spacing: 1.5) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(isToday ? .white.opacity(0.9) : color)
                            .frame(width: 3, height: 3)
                    }
                }
                .offset(y: 3.5)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.12)) {
                if hovering { hoveredDay = day } else if hoveredDay == day { hoveredDay = nil }
            }
        }
    }
}

/// The selected day's events, beside the grid.
struct DayAgendaView: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Environment(\.openURL) private var openURL
    let date: Date

    private var events: [EventModel] {
        calendarManager.agendaEvents.filter { event in
            if event.isCompletedReminder && Defaults[.hideCompletedReminders] { return false }
            if event.isAllDay && Defaults[.hideAllDayEvents] { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header

            if needsAccess {
                accessNotice
            } else if events.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(events) { event in
                            row(event)
                        }
                    }
                }
                .scrollIndicators(.never)
                .scrollableNotchContent()
            }
        }
        .onChange(of: date) {
            Task { await calendarManager.loadAgenda(for: date) }
        }
        .onAppear {
            Task { await calendarManager.loadAgenda(for: date) }
        }
        // Calendar lists arrive after launch; refetch once they do.
        .onChange(of: calendarManager.selectedCalendarIDs) {
            Task { await calendarManager.loadAgenda(for: date) }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            if !events.isEmpty {
                Text("\(events.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
                    .frame(minWidth: 8)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.10)))
            }
        }
    }

    /// An empty day is a good outcome, so it gets a shape rather than a
    /// shrugging line of grey text.
    private var empty: some View {
        VStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 15))
                .foregroundStyle(Color.effectiveAccent.opacity(0.55))
            Text("Nothing scheduled")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// True while macOS has not granted calendar access. Without this the view
    /// reports "Nothing scheduled" for a day that is actually full, which is
    /// worse than saying nothing at all.
    private var needsAccess: Bool {
        calendarManager.calendarAuthorizationStatus != .fullAccess
    }

    private var accessNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                calendarManager.calendarAuthorizationStatus == .denied
                    ? "Calendar access denied" : "Calendar access needed",
                systemImage: "lock"
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)

            Button(
                calendarManager.calendarAuthorizationStatus == .denied
                    ? "Open Settings" : "Allow"
            ) {
                if calendarManager.calendarAuthorizationStatus == .denied {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    Task {
                        await calendarManager.checkCalendarAuthorization()
                        await calendarManager.checkReminderAuthorization()
                        await calendarManager.loadAgenda(for: date)
                    }
                }
            }
            .controlSize(.small)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    /// An event as a tile in its calendar's own colour, rather than a line of
    /// text with a stripe next to it.
    ///
    /// What is happening *now* is the one thing worth finding instantly, so it
    /// is the only row that gets a filled edge and a label.
    private func row(_ event: EventModel) -> some View {
        let status = event.eventStatus
        let live = status == .inProgress
        let radius = nestedCornerRadius(inset: 6, cap: 9)

        return Button {
            if let url = event.calendarAppURL() { openURL(url) }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Capsule()
                    .fill(event.accentColor)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(event.isAllDay
                             ? "All-day"
                             : event.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()

                        if live {
                            Text("NOW")
                                .font(.system(size: 7, weight: .black))
                                .kerning(0.4)
                                .foregroundStyle(.black.opacity(0.8))
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(event.accentColor))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.trailing, 4)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(event.accentColor.opacity(live ? 0.20 : 0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(event.accentColor.opacity(live ? 0.55 : 0), lineWidth: 1)
            )
            .opacity(status == .ended ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        // A full-width row: barely any lift, or it would crowd the rows around it.
        .springyTile(hoverScale: 1.02, pressScale: 0.98, hoverBrightness: 0.06)
    }
}
