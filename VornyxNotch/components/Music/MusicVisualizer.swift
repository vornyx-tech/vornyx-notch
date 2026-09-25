//
//  MusicVisualizer.swift
//  VornyxNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import AppKit
import AudioToolbox
import Cocoa
import CoreAudio
import Defaults
import SwiftUI
import os

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    private var animationTimer: Timer?
    /// Set while real levels are driving the bars, so the random animation
    /// stays out of the way.
    private var driven = false
    
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
            let path = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                                    xRadius: barWidth / 2,
                                    yRadius: barWidth / 2)
            barLayer.path = path.cgPath
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }
    }
    
    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateBars()
        }
    }
    
    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }
    
    private func updateBars() {
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            let targetScale = CGFloat.random(in: 0.35 ... 1.0)
            barScales[i] = targetScale
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.3
            animation.autoreverses = true
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            }
            barLayer.add(animation, forKey: "scaleY")
        }
    }
    
    private func resetBars() {
        for (i, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barScales[i] = 0.35
        }
    }
    
    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying, !driven {
            startAnimating()
        } else if !isPlaying {
            stopAnimating()
        }
    }

    /// Drives the bars from what is actually playing. Nil hands them back to
    /// the random animation, which is what runs when the tap is off or refused.
    func setLevels(_ levels: [CGFloat]?) {
        guard let levels, !levels.isEmpty else {
            if driven {
                driven = false
                if isPlaying { startAnimating() }
            }
            return
        }

        if !driven {
            driven = true
            stopAnimatingKeepingBars()
        }

        for (i, barLayer) in barLayers.enumerated() {
            let level = levels[min(i, levels.count - 1)]
            let scale = 0.2 + 0.8 * max(0, min(1, level))
            barScales[i] = scale
            // The publisher already smooths; a layer animation on top of it
            // only adds lag.
            barLayer.transform = CATransform3DMakeScale(1, scale, 1)
        }
    }

    private func stopAnimatingKeepingBars() {
        animationTimer?.invalidate()
        animationTimer = nil
        for barLayer in barLayers { barLayer.removeAllAnimations() }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    @Default(.realAudioSpectrum) private var realSpectrum
    @ObservedObject private var levels = SystemAudioLevels.shared

    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }

    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        let wanted = realSpectrum && isPlaying
        // Hopped off the view update: starting the tap publishes, and
        // publishing from inside a redraw is what SwiftUI complains about.
        Task { @MainActor in
            wanted ? SystemAudioLevels.shared.start() : SystemAudioLevels.shared.stop()
        }
        nsView.setPlaying(isPlaying)
        nsView.setLevels(wanted && levels.isRunning ? levels.bars : nil)
    }

    static func dismantleNSView(_ nsView: AudioSpectrum, coordinator: ()) {
        Task { @MainActor in SystemAudioLevels.shared.stop() }
    }
}

// MARK: - The actual audio

/// Four band levels of whatever the Mac is playing, for the bars in the notch.
///
/// macOS has no "give me the audio that is playing" API. The usual route is
/// ScreenCaptureKit, which is gated behind Screen Recording - an alarming thing
/// to ask for in order to draw four bars. This uses Core Audio process taps
/// instead (macOS 14.2 and later), which answer to a permission of their own
/// for system audio and capture nothing of the screen.
///
/// The tap feeds a private aggregate device; its IO block splits the samples
/// into four bands and leaves them under a lock. Nothing is allocated there -
/// it runs on a real-time thread - and a timer on the main actor publishes what
/// it finds, smoothed, at 30 a second.
@MainActor
final class SystemAudioLevels: ObservableObject {
    static let shared = SystemAudioLevels()

    /// Low to high, each 0...1.
    @Published private(set) var bars: [CGFloat] = Array(repeating: 0, count: 4)
    @Published private(set) var isRunning = false
    /// Set when the tap could not be created: no permission, or no route to
    /// the audio. The bars fall back to the random animation.
    @Published private(set) var unavailable = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var ticker: Timer?
    private var smoothed = [Float](repeating: 0, count: 4)

    /// Written by the IO block, read by the ticker.
    private let latest = OSAllocatedUnfairLock(initialState: [Float](repeating: 0, count: 4))

    private init() {}

    func start() {
        guard !isRunning, !unavailable else { return }
        guard buildTap() else {
            unavailable = true
            teardown()
            return
        }
        isRunning = true
        let ticker = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publish() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        teardown()
        bars = Array(repeating: 0, count: 4)
        smoothed = [Float](repeating: 0, count: 4)
    }

    /// Creates a tap and throws it away, purely to raise the permission prompt.
    /// Returns whether the system let us have it.
    func requestAccess() -> Bool {
        if isRunning { return true }
        let allowed = buildTap()
        teardown()
        unavailable = !allowed
        return allowed
    }

    // MARK: - Publishing

    private func publish() {
        let values = latest.withLock { $0 }
        // Quick to rise, slow to fall: the way a level meter reads.
        for i in 0 ..< smoothed.count {
            let target = values[i]
            smoothed[i] = target > smoothed[i]
                ? smoothed[i] + (target - smoothed[i]) * 0.6
                : smoothed[i] + (target - smoothed[i]) * 0.2
        }
        bars = smoothed.map { CGFloat(min(1, $0)) }
    }

    // MARK: - Core Audio

    private func buildTap() -> Bool {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "Vornyx Notch visualizer"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        guard #available(macOS 14.2, *) else { return false }

        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr,
              tap != AudioObjectID(kAudioObjectUnknown)
        else { return false }
        tapID = tap

        guard let tapUID = string(from: tap, selector: kAudioTapPropertyUID),
              let outputUID = defaultOutputUID()
        else { return false }

        let sampleRate = tapSampleRate() ?? 48_000

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vornyx Notch visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            // Private, so it never shows up as a device anybody can pick.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        var aggregateDevice = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDevice) == noErr,
              aggregateDevice != AudioObjectID(kAudioObjectUnknown)
        else { return false }
        aggregateID = aggregateDevice

        // Band edges as one-pole coefficients for this sample rate.
        let lowCoefficient = coefficient(hz: 200, sampleRate: sampleRate)
        let midCoefficient = coefficient(hz: 1_000, sampleRate: sampleRate)
        let highCoefficient = coefficient(hz: 4_000, sampleRate: sampleRate)
        let store = latest

        var lowState: Float = 0
        var midState: Float = 0
        var highState: Float = 0

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateDevice, nil) {
            _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first,
                  let samples = first.mData?.assumingMemoryBound(to: Float.self)
            else { return }

            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { return }

            var sums = SIMD4<Float>(repeating: 0)
            for i in 0 ..< count {
                let sample = samples[i]
                lowState += lowCoefficient * (sample - lowState)
                midState += midCoefficient * (sample - midState)
                highState += highCoefficient * (sample - highState)

                // Each band is what the next filter up has not taken yet.
                let low = lowState
                let mid = midState - lowState
                let upper = highState - midState
                let top = sample - highState
                sums += SIMD4(low * low, mid * mid, upper * upper, top * top)
            }

            let scale = 1 / Float(count)
            // Roughly how loud each band sounds, rather than its raw power.
            let levels = [
                min(1, (sums[0] * scale).squareRoot() * 4.5),
                min(1, (sums[1] * scale).squareRoot() * 7),
                min(1, (sums[2] * scale).squareRoot() * 11),
                min(1, (sums[3] * scale).squareRoot() * 16),
            ]
            store.withLock { $0 = levels }
        }
        guard status == noErr, let proc else { return false }
        procID = proc

        return AudioDeviceStart(aggregateDevice, proc) == noErr
    }

    private func teardown() {
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
        latest.withLock { $0 = [Float](repeating: 0, count: 4) }
    }

    /// A one-pole lowpass coefficient for a corner frequency.
    private func coefficient(hz: Float, sampleRate: Float) -> Float {
        1 - exp(-2 * .pi * hz / sampleRate)
    }

    private func tapSampleRate() -> Float? {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr,
              format.mSampleRate > 0
        else { return nil }
        return Float(format.mSampleRate)
    }

    private func defaultOutputUID() -> String? {
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

    private func string(from object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
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

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
