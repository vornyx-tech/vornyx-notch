//
//  MusicVisualizer.swift
//  VornyxNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
//  The real-audio path - a Core Audio process tap on the player itself, split
//  into bands with biquad filters and read as RMS through an attack/release
//  envelope - follows Atoll's AudioTap and AudioProcessor (GPL-3.0),
//  https://github.com/Ebullioscopic/Atoll, itself after ZephyrCodesStuff's
//  rtaudio.
//

import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Defaults
import SwiftUI
import os
import simd

// MARK: - The bars

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var isPlaying = false
    private var animationTimer: Timer?
    /// Set while real levels are driving the bars, so the random animation
    /// stays out of the way.
    private var driven = false

    private static let rest: CGFloat = 0.35

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    deinit {
        animationTimer?.invalidate()
    }

    private func setupBars() {
        let barWidth: CGFloat = 2
        let barCount = 4
        let spacing: CGFloat = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        let totalHeight: CGFloat = 14
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            barLayer.path = NSBezierPath(
                roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                xRadius: barWidth / 2, yRadius: barWidth / 2
            ).cgPath
            barLayer.transform = CATransform3DMakeScale(1, Self.rest, 1)
            barLayers.append(barLayer)
            layer?.addSublayer(barLayer)
        }
    }

    // MARK: Random

    /// The stand-in when no real levels come: each bar eases to a new height
    /// from wherever it is now. No autoreversing, no animation left filled in
    /// on top of the layer - those were what left bars stuck at odd heights
    /// when playback flipped quickly or the notch opened and closed.
    private func startAnimating() {
        guard animationTimer == nil else { return }
        updateBars()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateBars()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateBars() {
        for barLayer in barLayers {
            move(barLayer, to: .random(in: Self.rest ... 1.0), duration: 0.3)
        }
    }

    /// From the height on screen - mid-animation or not - to the target, the
    /// model set to the target so nothing snaps back when it ends.
    private func move(_ barLayer: CAShapeLayer, to scale: CGFloat, duration: CFTimeInterval) {
        let current = (barLayer.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat)
            ?? (barLayer.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? Self.rest
        barLayer.removeAnimation(forKey: "scaleY")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barLayer.transform = CATransform3DMakeScale(1, scale, 1)
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = current
        animation.toValue = scale
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        barLayer.add(animation, forKey: "scaleY")
    }

    private func settle() {
        for barLayer in barLayers { move(barLayer, to: Self.rest, duration: 0.25) }
    }

    // MARK: Driving

    func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        if !playing {
            stopAnimating()
            settle()
        } else if !driven {
            startAnimating()
        }
    }

    /// Drives the bars from what is actually playing. Nil hands them back to
    /// the random animation.
    func setLevels(_ levels: [CGFloat]?) {
        guard isPlaying, let levels, !levels.isEmpty else {
            if driven {
                driven = false
                if isPlaying { startAnimating() }
            }
            return
        }

        if !driven {
            driven = true
            stopAnimating()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, barLayer) in barLayers.enumerated() {
            barLayer.removeAnimation(forKey: "scaleY")
            let level = levels[min(i, levels.count - 1)]
            // The envelope already smooths; a layer animation on top of it
            // would only add lag.
            barLayer.transform = CATransform3DMakeScale(1, 0.2 + 0.8 * max(0, min(1, level)), 1)
        }
        CATransaction.commit()
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    @ObservedObject private var levels = SystemAudioLevels.shared

    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        // Held, not started: the levels run while any view wants them, so
        // one view going away - the notch opening or closing - does not stop
        // them under the others.
        Task { @MainActor in SystemAudioLevels.shared.acquire() }
        return spectrum
    }

    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
        nsView.setLevels(levels.hasSignal ? levels.bars : nil)
    }

    static func dismantleNSView(_ nsView: AudioSpectrum, coordinator: ()) {
        Task { @MainActor in SystemAudioLevels.shared.release() }
    }
}

// MARK: - The actual audio

/// Four band levels of what the music player is playing, for the bars.
///
/// macOS has no "give me the audio that is playing" API. The usual route is
/// ScreenCaptureKit, behind Screen Recording - alarming to ask for to draw
/// four bars. This uses Core Audio process taps (macOS 14.2 and later), behind
/// a permission of their own for system audio, capturing nothing of the
/// screen. The tap is on the now-playing app alone where it can be found, so a
/// notification sound does not twitch the bars; on everything otherwise.
///
/// A refused permission does not fail the tap - it hears silence. So a tap
/// that stays silent while music plays counts as no signal, and the bars go
/// back to their stand-in animation rather than lying flat.
@MainActor
final class SystemAudioLevels: ObservableObject {
    static let shared = SystemAudioLevels()

    /// Low to high, each 0...1.
    @Published private(set) var bars: [CGFloat] = Array(repeating: 0, count: 4)
    /// Real levels are coming in.
    @Published private(set) var hasSignal = false

    private var users = 0
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var processor: BandProcessor?
    private var ticker: Timer?
    private var stopTask: Task<Void, Never>?
    private var watchers: Set<AnyCancellable> = []
    /// The app the tap is on, to rebuild it when another takes over.
    private var tappedBundleID: String?
    /// After a tap could not be made, when to try again.
    private var retryAfter = Date.distantPast
    private var silentSince: Date?

    private var isRunning: Bool { aggregateID != AudioObjectID(kAudioObjectUnknown) }

    private init() {}

    // MARK: Holding

    func acquire() {
        users += 1
        if watchers.isEmpty { watch() }
        reconsider()
    }

    func release() {
        users = max(0, users - 1)
        reconsider()
    }

    private func watch() {
        let music = MusicManager.shared
        music.$isPlaying.removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.reconsider() } }
            .store(in: &watchers)
        music.$bundleIdentifier.removeDuplicates()
            .sink { [weak self] bundle in
                Task { @MainActor in
                    guard let self, self.isRunning, bundle != self.tappedBundleID else { return }
                    self.teardown()
                    self.reconsider()
                }
            }
            .store(in: &watchers)
        Defaults.publisher(.realAudioSpectrum, options: [])
            .sink { [weak self] _ in Task { @MainActor in self?.reconsider() } }
            .store(in: &watchers)
    }

    /// Runs while anything shows the bars, the setting is on and music plays;
    /// stops a moment after that is no longer so, so a notch opening and
    /// closing, or a track change, does not tear the tap down and rebuild it.
    private func reconsider() {
        let wanted = users > 0 && Defaults[.realAudioSpectrum] && MusicManager.shared.isPlaying
        if wanted {
            stopTask?.cancel()
            stopTask = nil
            if !isRunning, Date() >= retryAfter { start() }
        } else if isRunning, stopTask == nil {
            stopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled else { return }
                self.stopTask = nil
                self.teardown()
            }
        }
    }

    private func start() {
        guard build() else {
            teardown()
            retryAfter = Date().addingTimeInterval(10)
            return
        }
        silentSince = nil
        let ticker = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publish() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    /// Creates a tap and throws it away, purely to raise the permission prompt,
    /// and turns the real levels on if it was allowed.
    func requestAccess() -> Bool {
        if isRunning { return true }
        let allowed = build()
        teardown()
        if allowed { Defaults[.realAudioSpectrum] = true }
        return allowed
    }

    // MARK: Publishing

    /// Each band's recent peak, forgotten slowly, to read the band against.
    private var peaks = SIMD4<Float>(repeating: 0)

    private func publish() {
        guard let processor else { return }
        let raw = processor.levels()
        let loud = raw.max() > 0.0005

        // Music spreads its energy across the bands, so each one alone is a
        // few percent of full scale - raw, the bars barely moved. Each is read
        // against its own recent peak instead, which fades over a few seconds:
        // the bars use their height at any volume, in any track.
        peaks = SIMD4(
            max(peaks[0] * 0.997, raw[0]), max(peaks[1] * 0.997, raw[1]),
            max(peaks[2] * 0.997, raw[2]), max(peaks[3] * 0.997, raw[3]))
        let floor = SIMD4<Float>(repeating: 0.002)
        let values = raw / simd_max(peaks, floor)

        // Silence while music plays: no permission, or a player the tap cannot
        // hear. Given a moment, since a quiet passage is silence too.
        if loud {
            silentSince = nil
        } else if MusicManager.shared.isPlaying {
            silentSince = silentSince ?? Date()
        }
        let signal = loud || (silentSince.map { Date().timeIntervalSince($0) < 2 } ?? false)
        if signal != hasSignal { hasSignal = signal }
        guard signal else { return }
        bars = [values[0], values[1], values[2], values[3]].map { CGFloat(min(1, max(0, $0))) }
    }

    // MARK: Core Audio

    private func build() -> Bool {
        guard #available(macOS 14.2, *) else { return false }

        let bundle = MusicManager.shared.bundleIdentifier
        let processes = bundle.map(Self.audioProcesses(for:)) ?? []
        let description = processes.isEmpty
            ? CATapDescription(monoGlobalTapButExcludeProcesses: [])
            : CATapDescription(monoMixdownOfProcesses: processes)
        description.name = "Vornyx Notch visualizer"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        tappedBundleID = processes.isEmpty ? nil : bundle

        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr,
              tap != AudioObjectID(kAudioObjectUnknown)
        else { return false }
        tapID = tap

        guard let tapUID = Self.string(from: tap, selector: kAudioTapPropertyUID),
              let outputUID = Self.defaultOutputUID()
        else { return false }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vornyx Notch visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            // Private, so it never shows up as a device anybody can pick.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]
            ],
        ]

        var aggregateDevice = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDevice) == noErr,
              aggregateDevice != AudioObjectID(kAudioObjectUnknown)
        else { return false }
        aggregateID = aggregateDevice

        let processor = BandProcessor(sampleRate: Self.sampleRate(of: tap) ?? 48_000)
        self.processor = processor

        var proc: AudioDeviceIOProcID?
        // Runs on the real-time audio thread: the processor allocates nothing
        // there - every buffer is made up front.
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateDevice, nil) {
            _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first,
                  let samples = first.mData?.assumingMemoryBound(to: Float.self)
            else { return }
            processor.process(samples, count: Int(first.mDataByteSize) / MemoryLayout<Float>.size)
        }
        guard status == noErr, let proc else { return false }
        procID = proc

        return AudioDeviceStart(aggregateDevice, proc) == noErr
    }

    private func teardown() {
        ticker?.invalidate()
        ticker = nil
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID) }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        processor = nil
        peaks = SIMD4(repeating: 0)
        tappedBundleID = nil
        silentSince = nil
        if hasSignal { hasSignal = false }
        bars = Array(repeating: 0, count: 4)
    }

    /// Core Audio's process objects for an app, its helpers included - a
    /// player such as TIDAL plays from `com.tidal.desktop.player`, not from the
    /// app itself.
    private static func audioProcesses(for bundleID: String) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr
        else { return [] }

        let wanted = bundleID.lowercased()
        return objects.filter { object in
            guard let id = string(from: object, selector: kAudioProcessPropertyBundleID)?.lowercased()
            else { return false }
            return id == wanted || id.hasPrefix(wanted + ".")
        }
    }

    private static func sampleRate(of tap: AudioObjectID) -> Float? {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr,
              format.mSampleRate > 0
        else { return nil }
        return Float(format.mSampleRate)
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return nil }
        return string(from: device, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func string(from object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var value: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}

// MARK: - Bands

/// Splits mono audio into four bands and follows how loud each is.
///
/// Samples are gathered into 512-sample blocks; each block runs through one
/// biquad per band - a low-pass at 150 Hz, band-passes at 500 Hz, 1.6 kHz and
/// 5 kHz, narrow enough that a note lights its own bar most - and its RMS, boosted per band, feeds an envelope that rises fast
/// and falls slower, the way the eye reads music moving. All of it is set up
/// in `init`: `process` runs on the real-time thread and allocates nothing.
final class BandProcessor: @unchecked Sendable {
    private static let blockSize = 512
    private static let bands = 4
    private static let gains: [Float] = [3.0, 5.0, 8.0, 14.0]
    private static let attack: Float = 0.85
    private static let release: Float = 0.40

    private let mono = UnsafeMutablePointer<Float>.allocate(capacity: BandProcessor.blockSize)
    private let filtered = UnsafeMutablePointer<Float>.allocate(capacity: BandProcessor.blockSize)
    private let delays: [UnsafeMutablePointer<Float>]
    private let setups: [vDSP_biquad_Setup]
    private var envelopes = SIMD4<Float>(repeating: 0)
    private var writePosition = 0

    private let published = OSAllocatedUnfairLock(initialState: SIMD4<Float>(repeating: 0))

    private enum Kind { case lowPass, bandPass }

    init(sampleRate: Float) {
        let filters: [(Kind, Float, Float)] = [
            (.lowPass, 150, 0.707),
            (.bandPass, 500, 1.0),
            (.bandPass, 1_600, 1.0),
            (.bandPass, 5_000, 1.0),
        ]
        setups = filters.compactMap { kind, frequency, q in
            Self.setup(kind, frequency: frequency, q: q, sampleRate: sampleRate)
        }
        delays = (0 ..< Self.bands).map { _ in
            let delay = UnsafeMutablePointer<Float>.allocate(capacity: 4)
            delay.initialize(repeating: 0, count: 4)
            return delay
        }
        mono.initialize(repeating: 0, count: Self.blockSize)
        filtered.initialize(repeating: 0, count: Self.blockSize)
    }

    deinit {
        setups.forEach(vDSP_biquad_DestroySetup)
        delays.forEach { $0.deallocate() }
        mono.deallocate()
        filtered.deallocate()
    }

    /// What the bands read now, 0...1-ish.
    func levels() -> SIMD4<Float> {
        published.withLock { $0 }
    }

    func process(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0, setups.count == Self.bands else { return }
        var source = samples
        var remaining = count
        while remaining > 0 {
            let take = min(remaining, Self.blockSize - writePosition)
            (mono + writePosition).update(from: source, count: take)
            writePosition += take
            source += take
            remaining -= take
            if writePosition == Self.blockSize {
                processBlock()
                writePosition = 0
            }
        }
    }

    private func processBlock() {
        for band in 0 ..< Self.bands {
            vDSP_biquad(setups[band], delays[band], mono, 1, filtered, 1, vDSP_Length(Self.blockSize))
            var rms: Float = 0
            vDSP_rmsqv(filtered, 1, &rms, vDSP_Length(Self.blockSize))
            let level = rms.isFinite ? min(1, rms * Self.gains[band]) : 0
            let previous = envelopes[band]
            let rate = level > previous ? Self.attack : Self.release
            envelopes[band] = previous + (level - previous) * rate
        }
        let snapshot = envelopes
        published.withLock { $0 = snapshot }
    }

    private static func setup(_ kind: Kind, frequency: Float, q: Float, sampleRate: Float) -> vDSP_biquad_Setup? {
        let w0 = 2 * Double.pi * Double(frequency) / Double(sampleRate)
        let alpha = sin(w0) / (2 * Double(q))
        let cosw = cos(w0)
        let a0 = 1 + alpha
        let (b0, b1, b2): (Double, Double, Double) = switch kind {
        case .lowPass: ((1 - cosw) / 2, 1 - cosw, (1 - cosw) / 2)
        case .bandPass: (alpha, 0, -alpha)
        }
        let coefficients = [b0 / a0, b1 / a0, b2 / a0, -2 * cosw / a0, (1 - alpha) / a0]
        return vDSP_biquad_CreateSetup(coefficients, 1)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
