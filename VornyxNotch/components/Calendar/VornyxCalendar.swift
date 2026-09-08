//
//  VornyxCalendar.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

// MARK: - Shared helpers

enum CalendarStyle {
    /// The narrow slot beside the player on the home page.
    case compact
    /// The full width of the notch, as its own tab.
    case expanded
}

extension EventModel {
    var accentColor: Color { Color(calendar.color) }

    var isCompletedReminder: Bool {
        if case .reminder(let completed) = type { return completed }
        return false
    }
}

/// Applies the user's event filters in one place.
func visibleEvents(_ events: [EventModel]) -> [EventModel] {
    events.filter { event in
        if event.isCompletedReminder && Defaults[.hideCompletedReminders] { return false }
        if event.isAllDay && Defaults[.hideAllDayEvents] { return false }
        return true
    }
}

// MARK: - Day timeline

/// A horizontal ribbon of the day with events laid out at their real times.
///
/// The notch is wide and short, which is the wrong shape for a scrolling list
/// but exactly the right shape for a timeline: a whole day fits across it and
/// the shape of your afternoon is readable at a glance.
struct DayTimeline: View {
    let events: [EventModel]
    let date: Date
    let now: Date
    var height: CGFloat = 26
    var showsHourLabels: Bool = true

    private var timed: [EventModel] { events.filter { !$0.isAllDay } }

    /// The window the ribbon spans. Anchored to a normal working day, then
    /// widened so nothing ever falls off the ends.
    private var bounds: (start: Date, end: Date) {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        var start = cal.date(byAdding: .hour, value: 8, to: startOfDay) ?? startOfDay
        var end = cal.date(byAdding: .hour, value: 20, to: startOfDay) ?? startOfDay

        for event in timed {
            start = min(start, event.start)
            end = max(end, event.end)
        }
        if cal.isDate(now, inSameDayAs: date) {
            start = min(start, now)
            end = max(end, now)
        }
        if end <= start { end = start.addingTimeInterval(3600) }
        return (start, end)
    }

    private func fraction(of instant: Date) -> CGFloat {
        let (start, end) = bounds
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return CGFloat(instant.timeIntervalSince(start) / span).clamped(to: 0...1)
    }

    /// Hour ticks, thinned out so labels never collide on a narrow ribbon.
    private func ticks(for width: CGFloat) -> [Date] {
        let cal = Calendar.current
        let (start, end) = bounds
        let hours = max(1, Int(end.timeIntervalSince(start) / 3600))
        let step = max(1, Int(ceil(Double(hours) / max(1, Double(Int(width / 46))))))

        var result: [Date] = []
        var cursor = cal.date(bySetting: .minute, value: 0, of: start) ?? start
        if cursor < start { cursor = cursor.addingTimeInterval(3600) }
        while cursor <= end {
            result.append(cursor)
            cursor = cal.date(byAdding: .hour, value: step, to: cursor) ?? end.addingTimeInterval(1)
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: height / 3, style: .continuous)
                    .fill(.white.opacity(0.05))

                ForEach(ticks(for: width), id: \.self) { tick in
                    Rectangle()
                        .fill(.white.opacity(0.07))
                        .frame(width: 1, height: height)
                        .offset(x: fraction(of: tick) * width)
                }

                ForEach(timed) { event in
                    let x = fraction(of: event.start) * width
                    let w = max(3, (fraction(of: event.end) - fraction(of: event.start)) * width)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(event.accentColor.opacity(event.eventStatus == .ended ? 0.35 : 0.9))
                        .frame(width: w, height: height - 8)
                        .offset(x: x, y: 4)
                        .help("\(event.title) · \(event.start.formatted(date: .omitted, time: .shortened))")
                }

                if Calendar.current.isDate(now, inSameDayAs: date) {
                    NowMarker(height: height)
                        .offset(x: fraction(of: now) * width - 1)
                }
            }
            .frame(height: height)
            .overlay(alignment: .bottomLeading) {
                if showsHourLabels {
                    ZStack(alignment: .topLeading) {
                        ForEach(ticks(for: width), id: \.self) { tick in
                            Text(tick, format: .dateTime.hour())
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                                .offset(x: fraction(of: tick) * width + 2, y: height + 2)
                        }
                    }
                }
            }
        }
        .frame(height: showsHourLabels ? height + 14 : height)
    }
}

private struct NowMarker: View {
    let height: CGFloat
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color.effectiveAccent)
                .frame(width: 2, height: height)
            Circle()
                .fill(Color.effectiveAccent)
                .frame(width: 5, height: 5)
                .offset(y: -2)
                .shadow(color: Color.effectiveAccent.opacity(0.9), radius: pulse ? 4 : 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Pieces

/// The date, big, on the left.
private struct DateBadge: View {
    let date: Date
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(date, format: .dateTime.weekday(.abbreviated))
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .textCase(.uppercase)
            Text(date, format: .dateTime.day())
                .font(.system(size: compact ? 26 : 34, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(date, format: .dateTime.month(.abbreviated))
                .font(.system(size: compact ? 9 : 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .fixedSize()
    }
}

/// One event as a coloured row: bar, title, time.
private struct EventRow: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let event: EventModel
    var compact: Bool = false

    var body: some View {
        Button {
            if let url = event.calendarAppURL() { openURL(url) }
        } label: {
            HStack(spacing: 6) {
                if event.type.isReminder {
                    ReminderToggle(
                        isOn: Binding(
                            get: { event.isCompletedReminder },
                            set: { done in
                                Task {
                                    await calendarManager.setReminderCompleted(
                                        reminderID: event.id, completed: done)
                                }
                            }
                        ),
                        color: event.accentColor
                    )
                } else {
                    Capsule()
                        .fill(event.accentColor)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(Defaults[.showFullEventTitles] ? 2 : 1)
                    Text(timeLabel)
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .opacity(event.isCompletedReminder || event.eventStatus == .ended ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timeLabel: String {
        if event.isAllDay { return "All-day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        if event.type.isReminder { return start }
        return "\(start) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

/// "In 25 min · Standup" - the single most useful line on the whole view.
private struct UpNext: View {
    let event: EventModel?
    let now: Date
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let event {
                Circle()
                    .fill(event.accentColor)
                    .frame(width: 6, height: 6)
                Text(relative(to: event))
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(Color.effectiveAccent)
                Text(event.title)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.secondary)
                Text("Nothing left today")
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func relative(to event: EventModel) -> String {
        if event.eventStatus == .inProgress { return "Now" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 1 { return "Now" }
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "in \(hours)h" : "in \(hours)h \(minutes % 60)m" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }
}

/// A week of days you can jump between, in the expanded layout.
private struct WeekStrip: View {
    @Binding var selectedDate: Date
    let today: Date

    private var days: [Date] {
        let cal = Calendar.current
        let start = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        ) ?? selectedDate
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                let isToday = Calendar.current.isDate(day, inSameDayAs: today)

                Button {
                    withAnimation(.smooth(duration: 0.2)) { selectedDate = day }
                } label: {
                    VStack(spacing: 1) {
                        Text(day, format: .dateTime.weekday(.narrow))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(day, format: .dateTime.day())
                            .font(.system(size: 11, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isSelected ? .black : (isToday ? Color.effectiveAccent : .white))
                            .monospacedDigit()
                    }
                    .frame(width: 22, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color.effectiveAccent : .white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Calendar

struct CalendarView: View {
    var style: CalendarStyle = .compact

    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @State private var now = Date()

    /// One tick a minute keeps the now-marker and the countdown honest without
    /// redrawing the notch constantly.
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var events: [EventModel] { visibleEvents(calendarManager.events) }
    private var allDay: [EventModel] { events.filter(\.isAllDay) }

    private var upNext: EventModel? {
        events.first { !$0.isAllDay && $0.end > now && !$0.isCompletedReminder }
            ?? events.first { !$0.isAllDay && !$0.isCompletedReminder }
    }

    var body: some View {
        Group {
            switch style {
            case .compact: compactLayout
            case .expanded: expandedLayout
            }
        }
        .onReceive(clock) { now = $0 }
        .onChange(of: selectedDate) {
            Task { await calendarManager.updateCurrentDate(selectedDate) }
        }
        .onChange(of: vm.notchState) { _, _ in reset() }
        .onAppear { reset() }
    }

    private func reset() {
        now = .now
        selectedDate = .now
        Task { await calendarManager.updateCurrentDate(.now) }
    }

    // MARK: Compact

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                DateBadge(date: selectedDate, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(eventSummary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    UpNext(event: upNext, now: now, compact: true)
                }
            }

            DayTimeline(
                events: events, date: selectedDate, now: now,
                height: 14, showsHourLabels: false
            )

            if let next = upNext {
                EventRow(event: next, compact: true)
            } else if let first = events.first {
                EventRow(event: first, compact: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Expanded

    private var expandedLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                DateBadge(date: selectedDate)
                Spacer(minLength: 0)
                WeekStrip(selectedDate: $selectedDate, today: now)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(eventSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    UpNext(event: upNext, now: now)
                        .frame(maxWidth: 240, alignment: .trailing)
                }

                DayTimeline(events: events, date: selectedDate, now: now)

                if !allDay.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(allDay.prefix(3)) { event in
                            Text(event.title)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(event.accentColor.opacity(0.28))
                                )
                                .foregroundStyle(.white)
                        }
                    }
                }

                if events.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(events.filter { !$0.isAllDay }) { event in
                                EventRow(event: event)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(Color.effectiveAccent)
            Text(Calendar.current.isDateInToday(selectedDate)
                 ? "Nothing scheduled today" : "Nothing scheduled")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var eventSummary: String {
        let count = events.count
        if count == 0 { return "Free" }
        return count == 1 ? "1 event" : "\(count) events"
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 12, height: 12)
                if isOn {
                    Circle().fill(color).frame(width: 6, height: 6)
                }
                Circle().fill(Color.black.opacity(0.001)).frame(width: 14, height: 14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

// MARK: - Calendar tab

/// The calendar as its own notch tab, filling the open notch instead of sharing
/// the home page with the player. Enabled by `Defaults[.calendarAsSeparateTab]`.
struct NotchCalendarView: View {
    @EnvironmentObject var vm: VornyxViewModel

    var body: some View {
        CalendarView(style: .expanded)
            .environmentObject(vm)
            .onHover { isHovering in
                vm.isHoveringCalendar = isHovering
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
    }
}

#Preview {
    CalendarView(style: .expanded)
        .frame(width: 600, height: 160)
        .background(.black)
        .environmentObject(VornyxViewModel())
}
