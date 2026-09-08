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

    /// Day-of-month numbers in the visible month that have events.
    private var busyDays: Set<Int> {
        Set(
            calendarManager.monthEvents
                .filter { calendar.isDate($0.start, equalTo: today, toGranularity: .month) }
                .map { calendar.component(.day, from: $0.start) }
        )
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(today, format: .dateTime.month(.wide))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text(today, format: .dateTime.year())
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 1)

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
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

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let inMonth = calendar.isDate(day, equalTo: today, toGranularity: .month)
        let number = calendar.component(.day, from: day)
        let busy = inMonth && busyDays.contains(number)

        Button {
            withAnimation(.smooth(duration: 0.15)) { selectedDate = day }
        } label: {
            ZStack {
                if isToday {
                    Circle().fill(Color.effectiveAccent)
                } else if isSelected {
                    Circle().strokeBorder(Color.effectiveAccent.opacity(0.8), lineWidth: 1.5)
                }

                Text("\(number)")
                    .font(.system(size: 10, weight: isToday ? .bold : (inMonth ? .medium : .regular)))
                    .foregroundStyle(
                        isToday ? .white : (inMonth ? Color.white : Color.white.opacity(0.25))
                    )
                    .monospacedDigit()
            }
            .frame(width: 18, height: 18)
            .overlay(alignment: .bottom) {
                if busy && !isToday {
                    Circle()
                        .fill(Color.effectiveAccent.opacity(0.9))
                        .frame(width: 3, height: 3)
                        .offset(y: 3)
                }
            }
            .frame(height: 21)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                if !events.isEmpty {
                    Text("\(events.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if events.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 9))
                    Text("Nothing scheduled")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(events) { event in
                            row(event)
                        }
                    }
                }
                .scrollIndicators(.never)
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

    private func row(_ event: EventModel) -> some View {
        Button {
            if let url = event.calendarAppURL() { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 5) {
                Capsule()
                    .fill(event.accentColor)
                    .frame(width: 2.5)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(event.isAllDay
                         ? "All-day"
                         : event.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .opacity(event.eventStatus == .ended ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
