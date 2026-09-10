//
//  WeatherView.swift
//  VornyxNotch
//
//  The dashboard's other left-hand page.
//

import Defaults
import SwiftUI

/// Now on the left, the next few days on the right - the same split the month
/// and the agenda use, so the two pages feel like the same drawer.
struct WeatherView: View {
    @ObservedObject private var weather = WeatherManager.shared
    @Default(.weatherUnit) private var unit

    var body: some View {
        Group {
            if let snapshot = weather.snapshot {
                content(snapshot)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { weather.refreshIfStale() }
    }

    // MARK: - Loaded

    /// Read the column's width and hand each half an exact share of it.
    ///
    /// `maxWidth: .infinity` was not enough: a flexible frame takes the
    /// proposal but does not stop its contents asking for more, so the forecast
    /// card overran the column by a few points and the column's clip sliced its
    /// right-hand edge clean off. `days` is handed the width outright and puts
    /// its own background inside it, which is the part a frame alone could not
    /// fix - an oversized child is centred in its frame, and the background
    /// went on overhanging both ends of it.
    private func content(_ snapshot: WeatherSnapshot) -> some View {
        GeometryReader { proxy in
            let daysWidth = max(130, proxy.size.width - nowWidth - columnGap)

            ZStack(alignment: .topLeading) {
                // Everything the shower falls across: the hero, and the space
                // the forecast panel will stand in.
                now(snapshot)

                WeatherPrecipitation(kind: Precipitation(code: snapshot.code))
                    // Runs on past the page's own bottom, behind the page dots
                    // - see `bottomBleed`.
                    .padding(.bottom, -WeatherPrecipitationStyle.bottomBleed)

                // The panel goes over the shower rather than under it. Rain
                // runs down the outside of glass; it does not cross the numbers
                // behind it, and four rows of small type read through a
                // downpour was the one place the weather beat the forecast.
                //
                // Which is also why the panel is properly dark rather than the
                // faint 5% wash the other cards wear: what it is standing in
                // front of here is not a flat page but a lit sky with rain on
                // it.
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: nowWidth + columnGap)
                    VStack(spacing: 0) {
                        days(snapshot, width: daysWidth)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .background(WeatherGlow(code: snapshot.code, isDay: snapshot.isDay))
    }

    private let nowWidth: CGFloat = 124
    private let columnGap: CGFloat = 12

    // MARK: Now

    private func now(_ snapshot: WeatherSnapshot) -> some View {
        let palette = WeatherCode.palette(snapshot.code, isDay: snapshot.isDay)

        return VStack(alignment: .leading, spacing: 0) {
            placeChip(snapshot.place)

            // The hero: the number and the sky it belongs to, on one line. The
            // icon carries a halo of its own colour so it reads as lit rather
            // than stamped on.
            HStack(alignment: .center, spacing: 6) {
                HStack(alignment: .top, spacing: 1) {
                    Text(degrees(snapshot.temperature))
                        .font(.system(size: 46, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, palette[0].opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .monospacedDigit()
                    Text("°")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 6)
                }

                ZStack {
                    Circle()
                        .fill(palette[0])
                        .frame(width: 30, height: 30)
                        .blur(radius: 14)
                        .opacity(0.65)
                    conditionSymbol(snapshot.code, isDay: snapshot.isDay, size: 26)
                }
            }
            .padding(.top, 2)

            Text(WeatherCode.label(snapshot.code))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            Text("Feels like \(degrees(snapshot.apparent))°")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 1)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                detail("humidity", "\(snapshot.humidity)%")
                detail("wind", "\(Int(snapshot.wind.rounded()))")
            }
        }
        .frame(width: nowWidth, alignment: .leading)
    }

    /// A symbol that moves: rain falls, sun shimmers. Indefinite symbol effects
    /// rather than an animation of our own, so the motion is the system's and
    /// costs nothing to keep running.
    @ViewBuilder
    private func conditionSymbol(_ code: Int, isDay: Bool, size: CGFloat) -> some View {
        let symbol = Image(systemName: WeatherCode.symbol(code, isDay: isDay))
            .font(.system(size: size))
            .symbolRenderingMode(.multicolor)

        switch code {
        case 51...86, 95...99:
            // Anything falling out of the sky: the layers cycle downwards.
            symbol.symbolEffect(.variableColor.iterative.reversing)
        case 0:
            symbol.symbolEffect(.pulse)
        default:
            symbol
        }
    }

    private func placeChip(_ place: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "location.fill")
                .font(.system(size: 7))
            Text(place)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.10)))
    }

    private func detail(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.07)))
    }

    // MARK: Days

    /// Today plus the next three, on a surface of their own. Bars rather than
    /// bare numbers: the point of a forecast at a glance is which day is the
    /// warm one, and that is a shape question, not a reading question.
    /// The four-day panel.
    ///
    /// Takes its width rather than being framed from outside, so the background
    /// is laid out inside the column instead of round an oversized child - see
    /// `content`.
    private func days(_ snapshot: WeatherSnapshot, width: CGFloat) -> some View {
        let range = temperatureRange(snapshot.days)
        let shape = RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 4), style: .continuous)

        return VStack(spacing: 2) {
            ForEach(snapshot.days.prefix(4)) { day in
                dayRow(day, range: range, now: snapshot)
            }
        }
        .padding(6)
        .frame(width: width)
        .background(
            shape
                // Dark first, then the usual wash on top: the black is what
                // holds the sky and the rain back off the type, and the white
                // is what keeps it looking like the app's other panels.
                .fill(.black.opacity(0.38))
                .overlay(shape.fill(.white.opacity(0.06)))
                .overlay(shape.strokeBorder(.white.opacity(0.09), lineWidth: 1))
        )
    }

    private func dayRow(
        _ day: DayForecast,
        range: ClosedRange<Double>,
        now snapshot: WeatherSnapshot
    ) -> some View {
        let today = isToday(day.date)

        return HStack(spacing: 4) {
            Text(weekday(day.date))
                .font(.system(size: 10, weight: today ? .bold : .medium, design: .rounded))
                .foregroundStyle(.white.opacity(today ? 0.95 : 0.5))
                .lineLimit(1)
                // "Today" in bold rounded needs every point of this. At 30 it
                // truncated to "Tod…" while the three-letter days sat in space.
                .frame(width: 38, alignment: .leading)

            conditionSymbol(day.code, isDay: true, size: 11)
                // Wider than the point size: the wet symbols are broad glyphs -
                // `cloud.rain.fill` runs about 15pt across at 11pt type - and
                // in a 16pt frame it overflowed left into the day's name.
                .frame(width: 20)

            Text(degrees(day.low))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .monospacedDigit()
                .frame(width: 17, alignment: .trailing)

            band(for: day, in: range, now: today ? snapshot.temperature : nil)

            Text(degrees(day.high))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(today ? 0.95 : 0.75))
                .monospacedDigit()
                .frame(width: 17, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            Capsule().fill(.white.opacity(today ? 0.08 : 0))
        )
    }

    /// One day's low-to-high, placed along the whole week's range - so the bars
    /// can be read against each other rather than each against itself.
    ///
    /// The bar is coloured by the temperatures at its own ends, so a cold day
    /// is a blue stub and a hot one runs into red. Today also carries a marker
    /// for where the temperature is right now, between its two ends.
    private func band(for day: DayForecast, in range: ClosedRange<Double>, now: Double?) -> some View {
        GeometryReader { proxy in
            let span = max(1, range.upperBound - range.lowerBound)
            let start = (day.low - range.lowerBound) / span
            let width = max(0.08, (day.high - day.low) / span)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.09))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                temperatureColor(day.low, in: range),
                                temperatureColor(day.high, in: range),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * width)
                    .offset(x: proxy.size.width * start)

                if let now {
                    let position = ((now - range.lowerBound) / span)
                        .clamped(to: 0...1)
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .offset(x: proxy.size.width * position - 2.5)
                }
            }
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity)
    }

    /// Cold to hot across the week's own range, so the scale always uses its
    /// whole span whether the week runs 2° to 8° or 18° to 34°.
    private func temperatureColor(_ value: Double, in range: ClosedRange<Double>) -> Color {
        let stops: [Color] = [
            Color(red: 0.35, green: 0.55, blue: 0.95),
            .cyan,
            .teal,
            .yellow,
            .orange,
            Color(red: 0.95, green: 0.35, blue: 0.30),
        ]
        let span = max(1, range.upperBound - range.lowerBound)
        let normalized = ((value - range.lowerBound) / span).clamped(to: 0...1)
        let index = Int((normalized * Double(stops.count - 1)).rounded())
        return stops[index]
    }

    private func temperatureRange(_ days: [DayForecast]) -> ClosedRange<Double> {
        let lows = days.map(\.low)
        let highs = days.map(\.high)
        guard let low = lows.min(), let high = highs.max(), low < high else { return 0...1 }
        return low...high
    }

    // MARK: - Not loaded yet

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 7) {
            switch weather.state {
            case .loading, .idle:
                ProgressView()
                    .controlSize(.small)
                Text("Getting the forecast…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .needsLocation:
                Image(systemName: "location.slash")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text("Location is off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Allow it, or name a place in Settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                settingsButton
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    Button("Try again") { weather.refresh() }
                    settingsButton
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingsButton: some View {
        Button("Open Settings") {
            DispatchQueue.main.async {
                SettingsWindowController.shared.showWindow()
            }
        }
        .controlSize(.small)
    }

    // MARK: - Formatting

    /// Whole degrees, with the unit said once in the big number rather than on
    /// every value in the column.
    private func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func weekday(_ date: Date) -> String {
        if isToday(date) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Glow

/// The weather's colour, behind the page.
///
/// The same trick as the album art's living glow, with the condition's palette
/// standing in for the artwork: three soft blobs, blurred past recognition,
/// drifting on periods that share no common multiple so the motion never
/// resolves into a loop. See `WeatherGlowStyle` for the numbers.
private struct WeatherGlow: View {
    let code: Int
    let isDay: Bool

    @State private var phase = Double.random(in: 0..<1000)
    @State private var tick: Double = 0

    /// A plain timer rather than `TimelineView(.animation)`, for the same
    /// reason the album art uses one: the notch lives in a non-activating
    /// panel, where the display-link schedule cannot be relied on to keep
    /// firing. Stored, not computed - a computed publisher would be rebuilt on
    /// every body pass.
    private let clock = Timer.publish(
        every: 1 / WeatherGlowStyle.frameRate, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        let style = WeatherGlowStyle.self
        let colors = WeatherCode.palette(code, isDay: isDay)
        let t = tick + phase

        GeometryReader { proxy in
            ZStack {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    // Each blob is offset in time from the last, so they never
                    // swell together.
                    let seed = Double(index) * 31
                    let breathe = sin((t + seed) / style.breathePeriod)
                    let sway = sin((t + seed * 1.7) / style.swayPeriod)
                    let bob = cos((t + seed * 2.3) / style.bobPeriod)
                    let anchor = style.anchors[index % style.anchors.count]

                    Circle()
                        .fill(color.opacity(0.75))
                        .frame(width: proxy.size.width * 0.6)
                        .scaleEffect(style.baseScale + style.scaleSwing * breathe)
                        .position(
                            x: proxy.size.width * anchor.x + style.driftRadius * sway,
                            y: proxy.size.height * anchor.y + style.driftRadius * bob
                        )
                }
            }
            .blur(radius: style.blur)
            .opacity(style.opacity)
            // Fade to nothing before the page's edges, so the column's clip has
            // nothing left to cut into a straight line. Inset and blurred by
            // the same amount, which puts the mask at roughly zero right where
            // the clip happens.
            .mask(
                Rectangle()
                    .fill(.white)
                    .padding(style.edgeFade)
                    .blur(radius: style.edgeFade)
            )
        }
        .onReceive(clock) { date in
            tick = date.timeIntervalSinceReferenceDate
        }
        // Decoration only: it must never take a click meant for the page.
        .allowsHitTesting(false)
    }
}

// MARK: - Falling weather

/// A random number generator that always answers the same way.
///
/// SplitMix64, which is four lines and passes the tests that matter here:
/// nothing depends on it being unguessable, only on it being the same shower
/// every time the same weather is drawn.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}


/// What is coming out of the sky, if anything.
enum Precipitation {
    case none
    case rain(count: Int)
    case snow

    /// Read off the WMO code, with the code's own sense of how hard it is
    /// coming down: drizzle is not a downpour, and showers are.
    init(code: Int) {
        switch code {
        case 51, 53, 56:
            self = .rain(count: WeatherPrecipitationStyle.dropsLight)
        case 55, 57, 61, 63, 66:
            self = .rain(count: WeatherPrecipitationStyle.dropsMedium)
        case 65, 67, 80, 81, 82, 95, 96, 99:
            self = .rain(count: WeatherPrecipitationStyle.dropsHeavy)
        case 71, 73, 75, 77, 85, 86:
            self = .snow
        default:
            self = .none
        }
    }

    var isNothing: Bool { if case .none = self { return true } else { return false } }
}

/// Rain and snow falling behind the page, the way the Weather app does it.
///
/// One `Canvas` rather than a view per drop: eighty SwiftUI views each with
/// their own animation would be eighty things for the layout system to think
/// about every frame, where this is a single draw call.
///
/// Behind the text on purpose. Apple can put weather in front of its labels
/// because it owns the whole screen and can afford the contrast; in a notch the
/// text is small and the background is black, and rain across it just makes it
/// harder to read.
struct WeatherPrecipitation: View {
    let kind: Precipitation

    /// A drop's whole life, decided once: where it falls, how fast, how big.
    /// Regenerating these per frame would make the rain shimmer rather than
    /// fall, because every drop would be somewhere new.
    private struct Drop {
        let x: Double
        let phase: Double
        let speed: Double
        let length: Double
        let opacity: Double
        /// Keeps each flake's sway out of step with its neighbours'.
        let swayPhase: Double
    }

    @State private var tick: Double = 0

    /// Every drop's whole life, worked out from the intensity alone.
    ///
    /// Computed rather than kept in `@State` and filled in on appear: a stored
    /// shower has to be told when the weather changed, and any pass where that
    /// message went missing left the page with no drops at all - rain that is
    /// there only some of the time. Rebuilding a couple of hundred structs per
    /// frame costs microseconds, and there is nothing left to get out of step.
    ///
    /// Seeded rather than random, for the reason the stored version existed:
    /// drops re-rolled every frame would shimmer in place instead of falling.
    /// The same intensity always gives the same shower.
    private var drops: [Drop] {
        let style = WeatherPrecipitationStyle.self
        let snowing = isSnow
        var rng = SeededGenerator(seed: UInt64(count) &* 6_364_136_223_846_793_005 &+ 1)

        return (0..<count).map { _ in
            Drop(
                x: .random(in: 0...1, using: &rng),
                phase: .random(in: 0...1, using: &rng),
                speed: .random(in: snowing ? style.snowSpeed : style.rainSpeed, using: &rng),
                length: .random(in: snowing ? style.flakeRadius : style.rainLength, using: &rng),
                opacity: .random(in: style.opacity, using: &rng),
                swayPhase: .random(in: 0...6, using: &rng)
            )
        }
    }

    private let clock = Timer.publish(
        every: 1 / WeatherPrecipitationStyle.frameRate, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        Canvas { context, size in
            let style = WeatherPrecipitationStyle.self
            let snowing = isSnow

            for drop in drops {
                // Fall wraps: a drop leaving the bottom is the same drop coming
                // back in at the top, so a fixed handful of them is an endless
                // shower.
                let progress = (drop.phase + tick * drop.speed)
                    .truncatingRemainder(dividingBy: 1)
                let y = progress * (size.height + drop.length) - drop.length

                if snowing {
                    let sway = sin((tick + drop.swayPhase) * 1.4) * style.snowSway
                    let point = CGPoint(x: drop.x * size.width + sway, y: y)
                    let radius = drop.length
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: point.x - radius, y: point.y - radius,
                            width: radius * 2, height: radius * 2
                        )),
                        with: .color(.white.opacity(drop.opacity))
                    )
                } else {
                    let lean = style.rainSlant * size.width
                    let x = drop.x * size.width + lean * progress
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + lean * 0.35, y: y + drop.length))
                    context.stroke(
                        path,
                        with: .color(.white.opacity(drop.opacity)),
                        style: StrokeStyle(
                            lineWidth: WeatherPrecipitationStyle.rainWidth,
                            lineCap: .round
                        )
                    )
                }
            }
        }
        // Fade the shower out before the page's edges rather than letting the
        // clip cut it. A gradient rather than the glow's blurred-inset trick:
        // rain is thin high-contrast strokes, and a blur would smear them into
        // grey haze instead of thinning them out. Left and right are left hard
        // - slanted rain has to arrive from somewhere, and drops leaving
        // sideways is what rain does.
        .mask(
            GeometryReader { proxy in
                // As fractions, because gradient stops are: the caps keep the
                // two fades from meeting and dimming the middle on a short page.
                let height = max(proxy.size.height, 1)
                let top = min(WeatherPrecipitationStyle.topFade / height, 0.35)
                let bottom = min(WeatherPrecipitationStyle.bottomFade / height, 0.35)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: top),
                        .init(color: .white, location: 1 - bottom),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .allowsHitTesting(false)
        .onReceive(clock) { date in
            guard !kind.isNothing else { return }
            tick = date.timeIntervalSinceReferenceDate
        }
    }

    private var isSnow: Bool { if case .snow = kind { return true } else { return false } }

    private var count: Int {
        switch kind {
        case .none: return 0
        case .rain(let count): return count
        case .snow: return WeatherPrecipitationStyle.flakes
        }
    }
}
