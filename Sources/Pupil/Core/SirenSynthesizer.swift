//
//  SirenSynthesizer.swift
//  Pupil
//
//  Real-time alternating two-tone alarm synthesizer using AVAudioEngine + AVAudioSourceNode.
//  Zero external audio assets required; renders directly to the system output device.
//

import AudioToolbox
import AVFoundation
import Foundation

public protocol SirenPlaybackControlling: Sendable {
    var isActive: Bool { get }

    func start(
        baseFrequencyHz: Double,
        overrideSpeakers: Bool,
        targetVolume: Float,
        outputGain: Float
    )

    func setOutputGain(_ gain: Float)
    func stop()
}

public final class SirenSynthesizer: SirenPlaybackControlling, @unchecked Sendable {
    public static let shared = SirenSynthesizer()

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var isSounding = false
    private var sampleIndex: UInt64 = 0
    private var baseFrequencyHz: Double = 880.0

    public init() {}

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSounding
    }

    public func start(
        baseFrequencyHz: Double = 880.0,
        overrideSpeakers: Bool = false,
        targetVolume: Float = 0.80,
        outputGain: Float = 1.0
    ) {
        let clampedGain = min(max(outputGain.isFinite ? outputGain : 1.0, 0.0), 1.0)
        lock.lock()
        defer { lock.unlock() }
        self.baseFrequencyHz = baseFrequencyHz
        if isSounding {
            if let engine, engine.isRunning {
                engine.mainMixerNode.outputVolume = clampedGain
                return
            }
            if SecurityCoordinator.isRunningUnderTests {
                return
            }
            teardownEngineLocked()
        }
        if overrideSpeakers {
            SystemAudioController.shared.forceBuiltInSpeakers(volume: targetVolume)
        }
        isSounding = true
        sampleIndex = 0

        if SecurityCoordinator.isRunningUnderTests {
            return
        }

        let audioEngine = AVAudioEngine()
        let outputFormat = audioEngine.outputNode.inputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44100.0

        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            isSounding = false
            return
        }

        let node = AVAudioSourceNode(format: monoFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let highFreq = max(440.0, self.baseFrequencyHz)
            let lowFreq = highFreq * 0.75
            let halfSecondSamples = UInt64(sampleRate * 0.45)

            for frame in 0..<Int(frameCount) {
                let currentSample = self.sampleIndex
                self.sampleIndex &+= 1

                let useHigh = ((currentSample / max(1, halfSecondSamples)) % 2) == 0
                let freq = useHigh ? highFreq : lowFreq
                let periodSamples = max(2, UInt64(sampleRate / freq))
                let halfPeriod = max(1, periodSamples / 2)
                let sampleVal: Float = ((currentSample / halfPeriod) % 2 == 0) ? 0.65 : -0.65

                for buffer in ablPointer {
                    if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        data[frame] = sampleVal
                    }
                }
            }
            return noErr
        }

        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: monoFormat)
        audioEngine.mainMixerNode.outputVolume = clampedGain

        do {
            try audioEngine.start()
            self.engine = audioEngine
            self.sourceNode = node
        } catch {
            self.isSounding = false
        }
    }

    public func setOutputGain(_ gain: Float) {
        let clampedGain = min(max(gain.isFinite ? gain : 1.0, 0.0), 1.0)
        lock.lock()
        let activeEngine = isSounding ? engine : nil
        lock.unlock()
        activeEngine?.mainMixerNode.outputVolume = clampedGain
    }

    public func stop() {
        lock.lock()
        guard isSounding else {
            lock.unlock()
            SystemAudioController.shared.restoreIfNeeded()
            return
        }
        isSounding = false
        teardownEngineLocked()
        lock.unlock()

        SystemAudioController.shared.restoreIfNeeded()
    }

    private func teardownEngineLocked() {
        engine?.stop()
        if let node = sourceNode {
            engine?.detach(node)
        }
        sourceNode = nil
        engine = nil
    }

    /// Plays a brief 1.2s test chirp so the user can verify speaker output from Settings.
    public func playTestChirp(baseFrequencyHz: Double = 880.0) {
        start(baseFrequencyHz: baseFrequencyHz, overrideSpeakers: false, targetVolume: 0.80, outputGain: 1.0)
        setOutputGain(1.0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.stop()
        }
    }

    /// Plays a subtle, non-intrusive acoustic tick for countdown warning feedback.
    public func playCountdownTick() {
        guard !SecurityCoordinator.isRunningUnderTests else { return }
        AudioServicesPlaySystemSound(1057)
    }
}
