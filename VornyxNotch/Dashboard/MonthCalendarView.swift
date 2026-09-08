//
//  MonthCalendarView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// A plain month grid: weekday initials across the top, the current month's
/// days in bold, the days either side of it dimmed, today in a filled circle.
///
/// Only ever the current month - the notch is a glance surface, not a place to
/// plan next March.
struct MonthCalendarView: View {
    @ObservedObject private var calendarManager = CalendarManager.shared

    var showsEventDots: Bool = true

    @State private var today = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var calendar: Calendar {
        var calendar = Calendar.current
        // Weeks run Monday-first, matching the M T W T F S S header.
        calendar.firstWeekday = 2
        return calendar
    }

    /// Six weeks of days, so the grid never changes height month to month.
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

    /// Days in the visible month that have something scheduled.
    private var daysWithEvents: Set<Int> {
        guard showsEventDots else { return [] }
        return Set(
            calendarManager.events
                .filter { calendar.isDate($0.start, equalTo: today, toGranularity: .month) }
                .map { calendar.component(.day, from: $0.start) }
        )
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            LazyVGrid(columns: columns, spacing: 3) {
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
            Task { await calendarManager.updateCurrentDate(.now) }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: today, toGranularity: .month)
        let number = calendar.component(.day, from: day)
        let hasEvents = inMonth && daysWithEvents.contains(number)

        ZStack {
            if isToday {
                Circle()
                    .fill(Color.effectiveAccent)
                    .frame(width: 20, height: 20)
            }

            Text("\(number)")
                .font(.system(size: 11, weight: isToday ? .bold : (inMonth ? .medium : .regular)))
                .foregroundStyle(
                    isToday ? .white : (inMonth ? Color.white : Color.white.opacity(0.28))
                )
                .monospacedDigit()
        }
        .frame(height: 20)
        .overlay(alignment: .bottom) {
            if hasEvents && !isToday {
                Circle()
                    .fill(Color.effectiveAccent.opacity(0.9))
                    .frame(width: 3, height: 3)
                    .offset(y: 2)
            }
        }
    }
}
