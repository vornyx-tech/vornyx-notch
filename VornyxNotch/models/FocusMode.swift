//
//  FocusMode.swift
//  VornyxNotch
//
//  The Focus modes macOS ships, as the notch draws them.
//
//  Mode identifiers, symbols and colours after DynamicNotch by Evgeniy
//  Petrukovich (GPL-3.0), https://github.com/jackson-storm/dynamicnotch
//

import SwiftUI

/// A Focus mode, by the identifier macOS gives it.
enum FocusMode: Equatable {
    case doNotDisturb, work, personal, sleep, driving, fitness, gaming
    case mindfulness, reading, reduceInterruptions
    /// One the user made, or one this list has not heard of.
    case other

    init(identifier: String?) {
        switch identifier {
        case "com.apple.donotdisturb.mode", "com.apple.donotdisturb.mode.default": self = .doNotDisturb
        case "com.apple.focus.work": self = .work
        case "com.apple.focus.personal": self = .personal
        case "com.apple.sleep.sleep-mode", "com.apple.focus.sleep": self = .sleep
        case "com.apple.donotdisturb.mode.driving", "com.apple.focus.driving": self = .driving
        case "com.apple.donotdisturb.mode.workout", "com.apple.focus.fitness": self = .fitness
        case "com.apple.focus.gaming": self = .gaming
        case "com.apple.focus.mindfulness": self = .mindfulness
        case "com.apple.focus.reading": self = .reading
        case "com.apple.focus.reduce-interruptions": self = .reduceInterruptions
        case let id?:
            // Identifiers vary between releases - com.apple.focus.work, or
            // com.apple.donotdisturb.mode.work - so a known word in one names
            // the mode before the Do Not Disturb prefix is taken to mean Do
            // Not Disturb itself, which read every mode on newer systems as it.
            self = Self.byWord(in: id)
                ?? (id.hasPrefix("com.apple.donotdisturb") ? .doNotDisturb : .other)
        default: self = .other
        }
    }

    private static func byWord(in identifier: String) -> FocusMode? {
        let id = identifier.lowercased()
        let words: [(String, FocusMode)] = [
            ("work", .work), ("personal", .personal), ("sleep", .sleep), ("bedtime", .sleep),
            ("driving", .driving), ("fitness", .fitness), ("workout", .fitness), ("gaming", .gaming),
            ("mindfulness", .mindfulness), ("reading", .reading), ("reduce-interruptions", .reduceInterruptions),
            ("reduceinterruptions", .reduceInterruptions),
        ]
        // "workout" before "work", or a workout would read as Work.
        return words.sorted { $0.0.count > $1.0.count }.first { id.contains($0.0) }?.1
    }

    /// From what the menu bar item says - "Focus, Work", or a localised
    /// equivalent carrying the English mode name - when there is no
    /// identifier to go by. Nil when it names no mode this list knows.
    init?(menuTitle: String) {
        let lowered = menuTitle.lowercased()
        // Named modes first, Do Not Disturb last: the item can mention Do Not
        // Disturb beside the mode actually on, and was read as it.
        let byName: [(String, FocusMode)] = [
            ("workout", .fitness), ("work", .work), ("personal", .personal),
            ("sleep", .sleep), ("driving", .driving), ("fitness", .fitness), ("gaming", .gaming),
            ("mindfulness", .mindfulness), ("reading", .reading), ("reduce interruptions", .reduceInterruptions),
            ("do not disturb", .doNotDisturb),
        ]
        guard let match = byName.first(where: { lowered.contains($0.0) }) else { return nil }
        self = match.1
    }

    var name: String {
        switch self {
        case .doNotDisturb: return "Do Not Disturb"
        case .work: return "Work"
        case .personal: return "Personal"
        case .sleep: return "Sleep"
        case .driving: return "Driving"
        case .fitness: return "Fitness"
        case .gaming: return "Gaming"
        case .mindfulness: return "Mindfulness"
        case .reading: return "Reading"
        case .reduceInterruptions: return "Reduce Interruptions"
        case .other: return "Focus"
        }
    }

    var symbol: String {
        switch self {
        case .doNotDisturb, .other: return "moon.fill"
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        case .sleep: return "bed.double.fill"
        case .driving: return "car.fill"
        case .fitness: return "figure.run"
        case .gaming: return "gamecontroller.fill"
        case .mindfulness: return "brain.head.profile"
        case .reading: return "book.closed.fill"
        case .reduceInterruptions: return "apple.intelligence"
        }
    }

    /// The colours System Settings uses for each.
    var tint: Color {
        switch self {
        case .doNotDisturb, .other: return Color(red: 0.370, green: 0.360, blue: 0.902)
        case .work: return Color(red: 0.414, green: 0.769, blue: 0.863)
        case .personal: return Color(red: 0.748, green: 0.354, blue: 0.948)
        case .sleep: return Color(red: 0.341, green: 0.384, blue: 0.980)
        case .driving: return Color(red: 0.988, green: 0.561, blue: 0.153)
        case .fitness: return Color(red: 0.176, green: 0.804, blue: 0.459)
        case .gaming: return Color(red: 0.043, green: 0.518, blue: 1.000)
        case .mindfulness: return Color(red: 0.298, green: 0.800, blue: 0.780)
        case .reading: return Color(red: 1.000, green: 0.620, blue: 0.040)
        case .reduceInterruptions: return Color(red: 0.690, green: 0.450, blue: 0.980)
        }
    }
}
