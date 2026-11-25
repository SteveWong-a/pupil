# Technical Architecture Specification: Escalating Siren Audio Curve

- **Feature Branch**: `feat/siren-escalation-curve`
- **Target Application**: Pupil (macOS native Swift 6 / SwiftUI / AppKit)
- **Status**: Proposed Specification

---

## 1. Overview & Motivation

Currently, when `SecurityCoordinator.enterAlarm(source:simulated:)` transitions into `.alarm`, it immediately starts `SirenSynthesizer` at the full configured `PupilSettings.sirenOverrideVolume` (default `0.80`, up to `1.00`). During accidental triggers (e.g., forgetting to disarm before unplugging a charger or bumping the laptop), immediate full-volume siren output is jarring and disruptive in libraries, offices, or cafes.

This specification introduces an **optional progressive siren escalation curve**:
1. When enabled (`sirenEscalationCurveEnabled == true`), the alarm starts at **30%** of the configured target ceiling (`sirenOverrideVolume`) and progresses to **100%** of that ceiling according to the chosen `SirenEscalationProfile` (`.immediate`, `.stepped`, or `.smoothRamp`).
2. All curve math lives in a pure, deterministic, `Sendable` evaluator (`SirenEscalationEvaluator`).
3. All CoreAudio HAL and `AVAudioEngine` operations are dispatched off `@MainActor` through a non-blocking, generation-guarded `SystemAudioVolumeManager` wrapping the existing `SystemAudioController` and `SirenSynthesizer`, preserving pre-alarm `SystemAudioSnapshot` state and preventing stale writes after disarm.
4. Configuration is persisted in `PupilSettings` and exposed in `AlarmSettingsPage` using Pupil's sentence-case native settings components.

---

## 2. Existing Codebase Integration Points

Inspection of the current repository establishes the following baseline types and call sites:

- **`Sources/Pupil/Core/SystemAudioController.swift`**:
  - Defines `SystemAudioSnapshot`, `AudioHardwareBackend`, `CoreAudioHardwareBackend`, and `SystemAudioController`.
  - `SystemAudioController.forceBuiltInSpeakers(volume:)` captures `SystemAudioSnapshot` once (preserving prior default output device, mute state, and volume), switches default output to built-in speakers, unmutes, and clamps hardware volume to `[0.1, 1.0]`.
  - `SystemAudioController.restoreIfNeeded()` restores the captured snapshot atomically and clears it.
- **`Sources/Pupil/Core/SirenSynthesizer.swift`**:
  - Defines `SirenSynthesizer` (`AVAudioEngine` + `AVAudioSourceNode` dual-tone square-wave generator).
  - Currently accepts `start(baseFrequencyHz:overrideSpeakers:targetVolume:)` and calls `SystemAudioController.shared.forceBuiltInSpeakers(volume:)` synchronously on the caller's thread when `overrideSpeakers == true`.
  - `audioEngine.mainMixerNode.outputVolume` is currently hardcoded to `1.0`.
- **`Sources/Pupil/Core/SecurityCoordinator.swift`**:
  - `@MainActor @Observable` state machine with injectable `clock: () -> TimeInterval` and already-tracked `alarmStartTime: TimeInterval?`.
  - Calls `SirenSynthesizer.shared.start(...)` in `enterAlarm(source:simulated:)` and in the `lockMonitor.onLockEvent` `.wake` branch; calls `SirenSynthesizer.shared.stop()` in `performValidatedDisarm(method:)`.
- **`Sources/Pupil/Settings/PupilSettings.swift`**:
  - `@MainActor @Observable` `UserDefaults`-backed store containing `sirenFrequencyHz`, `sirenSpeakerOverrideEnabled`, `sirenOverrideVolume` (`0.10...1.00`), and `EnvironmentPreset` (`.quietLibrary = 0.45`, `.cafe = 0.80`, `.busyPark = 1.00`, `.custom`).
- **`Sources/Pupil/Settings/Pages/AlarmSettingsPage.swift`**:
  - Uses `SettingsGroup`, `SettingsRowContent`, `SettingsGroupDivider`, `SettingsMenuPickerPill`, `PupilToggle`, and `SettingsEnvironmentSliderRowContent` with sentence-case row titles.

---

## 3. Types, Protocols, and Data Models

### 3.1 `SirenEscalationProfile` (`Sources/Pupil/Core/SirenEscalationEvaluator.swift`)

```swift
public enum SirenEscalationProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case immediate
    case stepped
    case smoothRamp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .immediate: return "Immediate"
        case .stepped: return "Stepped"
        case .smoothRamp: return "Smooth ramp"
        }
    }

    public var subtitle: String {
        switch self {
        case .immediate:
            return "Starts immediately at 100% of configured volume."
        case .stepped:
            return "Escalates in three discrete steps (30% → 60% → 100% over 8 seconds)."
        case .smoothRamp:
            return "Continuously ramps from 30% to 100% of configured volume over 8 seconds."
        }
    }
}
```

### 3.2 `SirenEscalationEvaluation` (`Sources/Pupil/Core/SirenEscalationEvaluator.swift`)

Value-type snapshot returned by `SirenEscalationEvaluator` so both hardware volume override and synthesizer mixer gain are explicitly represented without ambiguity:

```swift
public struct SirenEscalationEvaluation: Sendable, Equatable {
    /// Normalized escalation progress along the active duration in [0.0, 1.0].
    public let progress: Double

    /// Relative curve multiplier in [0.30, 1.00] (1.00 when immediate or disabled).
    public let volumeFactor: Float

    /// Acoustic target volume relative to full scale (`volumeFactor * clampedMaxVolume`).
    public let targetVolume: Float

    /// Hardware-clamped system speaker volume in [0.10, 1.00] for `SystemAudioController`.
    public let hardwareVolume: Float

    /// Residual mixer gain (`targetVolume / hardwareVolume`) in (0.0, 1.0] for `SirenSynthesizer`
    /// when `hardwareVolume` is clamped at the 0.10 CoreAudio minimum floor.
    public let synthesizerGain: Float

    /// Discrete stage indicator (0 = immediate/disabled, 1...3 = escalation stage).
    public let stageIndex: Int

    /// `true` once the curve has reached its 1.00 plateau and no further ticks are needed.
    public let isComplete: Bool
}
```

### 3.3 `SirenPlaybackControlling` (`Sources/Pupil/Core/SirenSynthesizer.swift`)

Protocol abstraction over `SirenSynthesizer` enabling unit tests to verify audio start, gain modulation, and stop sequencing without instantiating real `AVAudioEngine` output streams:

```swift
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
```

**Required updates to `SirenSynthesizer`**:
- Conform `SirenSynthesizer` to `SirenPlaybackControlling`.
- Extend `start(baseFrequencyHz: Double = 880.0, overrideSpeakers: Bool = false, targetVolume: Float = 0.80, outputGain: Float = 1.0)` (keeping backwards-compatible defaults) and apply `audioEngine.mainMixerNode.outputVolume = min(max(outputGain, 0.0), 1.0)` before `audioEngine.start()`.
- Add `setOutputGain(_ gain: Float)`: reads `engine` and `isSounding` under `lock`, unlocks, then updates `activeEngine.mainMixerNode.outputVolume = min(max(gain, 0.0), 1.0)` without taking `lock` inside the real-time `AVAudioSourceNode` render callback.
- Keep `playTestChirp(baseFrequencyHz:)` resetting `outputGain` to `1.0` so a previous mid-ramp alarm never leaves test chirps attenuated.

### 3.4 `SystemAudioVolumeManaging` & `SystemAudioVolumeManager` (`Sources/Pupil/Core/SystemAudioVolumeManager.swift`)

Protocol and production coordinator isolating CoreAudio HAL and `AVAudioEngine` work onto a dedicated serial background `DispatchQueue` while guaranteeing strict FIFO ordering and generation-based cancellation:

```swift
public protocol SystemAudioVolumeManaging: Sendable {
    /// Starts alarm audio off the main thread. When `overrideSpeakers` is true, switches
    /// default output to built-in speakers and sets initial volume before starting synthesis.
    func beginAlarmAudio(
        sessionID: UInt64,
        baseFrequencyHz: Double,
        overrideSpeakers: Bool,
        initialEvaluation: SirenEscalationEvaluation
    )

    /// Applies an incremental volume/gain escalation step for `sessionID` off the main thread.
    /// Dropped immediately if `sessionID` is no longer active.
    func applyEscalationStep(
        sessionID: UInt64,
        overrideSpeakers: Bool,
        evaluation: SirenEscalationEvaluation
    )

    /// Invalidates `sessionID`, stops siren synthesis, and restores any captured
    /// `SystemAudioSnapshot` off the main thread.
    func endAlarmAudio(sessionID: UInt64)
}
```

**Required enhancement to `SystemAudioController` (`Sources/Pupil/Core/SystemAudioController.swift`)**:
- Cache `private var activeOverrideDeviceID: AudioDeviceID?` under `lock` when `forceBuiltInSpeakers(volume:)` resolves `targetDeviceID`, and clear it in `restoreIfNeeded()`.
- Add `public func updateOverrideVolume(_ volume: Float)`:
  - Clamps `volume` to `0.1...1.0`.
  - If `snapshot == nil`, delegates to `forceBuiltInSpeakers(volume: clampedVolume)`.
  - Otherwise resolves `let deviceID = activeOverrideDeviceID ?? backend.builtInSpeakerDeviceID() ?? backend.defaultOutputDeviceID()`, ensures unmute (`backend.setMuted(false, deviceID: deviceID)`), and sets `backend.setVirtualMainVolume(clampedVolume, deviceID: deviceID)` without re-enumerating all CoreAudio devices on every ramp tick and without overwriting the initial `SystemAudioSnapshot`.

---

## 4. Pure Logic Evaluator: `SirenEscalationEvaluator`

Location: `Sources/Pupil/Core/SirenEscalationEvaluator.swift`

```swift
public struct SirenEscalationEvaluator: Sendable, Equatable {
    public static let initialVolumeFactor: Float = 0.30
    public static let steppedMidVolumeFactor: Float = 0.60
    public static let fullVolumeFactor: Float = 1.00
    public static let minimumHardwareVolume: Float = 0.10
    public static let defaultRampDurationSeconds: TimeInterval = 8.0
    public static let evaluationTickIntervalSeconds: TimeInterval = 0.25

    public init() {}
}
```

### 4.1 Curve Rules & Mathematical Specification

Given inputs:
- `elapsedSeconds: TimeInterval`
- `profile: SirenEscalationProfile`
- `maxVolume: Float = 1.0`
- `enabled: Bool = true`
- `rampDurationSeconds: TimeInterval = SirenEscalationEvaluator.defaultRampDurationSeconds`

Evaluation proceeds purely and deterministically:

1. **Sanitize & Clamp Bounds**:
   - `clampedMax = min(max(maxVolume.isFinite ? maxVolume : 1.0, minimumHardwareVolume), 1.0)`
   - Handle non-finite `elapsedSeconds`:
     - If `elapsedSeconds.isNaN`: treat `clampedElapsed = 0.0`.
     - If `elapsedSeconds == .infinity`: treat as plateau (`clampedElapsed = effectiveDuration`).
     - If `elapsedSeconds == -.infinity` or `< 0`: `clampedElapsed = 0.0`.
   - `effectiveDuration = rampDurationSeconds.isFinite ? max(0.0, rampDurationSeconds) : defaultRampDurationSeconds`

2. **Immediate / Disabled Gate**:
   - If `!enabled` OR `profile == .immediate` OR `effectiveDuration <= 0.0`:
     - `progress = 1.0`, `volumeFactor = 1.00`, `stageIndex = 0`, `isComplete = true`.

3. **`.stepped` Profile (3-stage discrete curve: `30% -> 60% -> 100%`)**:
   - `progress = min(max(clampedElapsed / effectiveDuration, 0.0), 1.0)`
   - Stage thresholds (at default `8.0s` duration):
     - `clampedElapsed < effectiveDuration * 0.5` (`[0s, 4.0s)`): `volumeFactor = 0.30`, `stageIndex = 1`, `isComplete = false`
     - `effectiveDuration * 0.5 <= clampedElapsed < effectiveDuration` (`[4.0s, 8.0s)`): `volumeFactor = 0.60`, `stageIndex = 2`, `isComplete = false`
     - `clampedElapsed >= effectiveDuration` (`>= 8.0s`): `volumeFactor = 1.00`, `stageIndex = 3`, `isComplete = true`

4. **`.smoothRamp` Profile (continuous linear ramp `30% -> 100%`)**:
   - Note: macOS `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` already applies a perceptual dB taper internally, so linear interpolation over `[0.30, 1.00]` produces smooth perceptual loudness progression and exact midpoint predictability.
   - `progress = min(max(clampedElapsed / effectiveDuration, 0.0), 1.0)`
   - `volumeFactor = initialVolumeFactor + (fullVolumeFactor - initialVolumeFactor) * Float(progress)`
   - `isComplete = progress >= 1.0`
   - `stageIndex`: `1` if `progress < 0.5`, `2` if `progress < 1.0`, `3` if `isComplete`.

5. **Target & Hardware Split**:
   - `targetVolume = volumeFactor * clampedMax`
   - `hardwareVolume = min(max(targetVolume, minimumHardwareVolume), 1.0)`
   - `synthesizerGain = hardwareVolume > 0 ? min(max(targetVolume / hardwareVolume, 0.0), 1.0) : 1.0`
   - Example (`maxVolume = 0.20`, `.stepped`, `t = 0s`): `targetVolume = 0.06`, `hardwareVolume = 0.10`, `synthesizerGain = 0.60` (`0.10 * 0.60 = 0.06`), preserving a true 30%->100% acoustic ramp even near the `0.10` CoreAudio hardware clamp.

6. **Convenience Methods**:
   - `public static func evaluate(elapsedSeconds:profile:maxVolume:enabled:rampDurationSeconds:) -> SirenEscalationEvaluation`
   - `public static func targetVolume(elapsedSeconds:profile:maxVolume:enabled:rampDurationSeconds:) -> Float`
   - Instance `func evaluate(...) -> SirenEscalationEvaluation` forwarding to `Self.evaluate(...)` (matching `AdaptiveVisionGovernor`).

---

## 5. Threading & Non-Blocking System Audio Integration

### 5.1 Why Off-Main-Thread Dispatch + Generation Guards Are Required

1. `CoreAudioHardwareBackend` performs synchronous CoreAudio HAL IPC (`AudioObjectGetPropertyData`, `AudioObjectSetPropertyData`, device list enumeration in `builtInSpeakerDeviceID()`). Running these on `@MainActor`—especially repeatedly during a smooth ramp or during Bluetooth-to-speaker route transitions—risks UI frame drops and watchdog stalls when Touch ID or PIN unlock UI must remain responsive.
2. `AVAudioEngine()` initialization and `audioEngine.start()` should execute **after** `SystemAudioController.forceBuiltInSpeakers(...)` switches the default output device so `AVAudioEngine` binds directly to the built-in speakers at their native sample rate without briefly emitting a burst of audio through plugged-in headphones.
3. Unstructured Swift `Task { await actor.method() }` calls spawned from `@MainActor` do not guarantee FIFO submission order against one another. Using a single serial `DispatchQueue(label: "com.pupil.system-audio-volume", qos: .userInitiated)` together with a synchronous `NSLock`-protected `activeSessionID: UInt64` guarantees:
   - **Zero main-thread blocking**: Every method on `SystemAudioVolumeManager` returns immediately (`workerQueue.async`).
   - **Strict FIFO ordering**: `beginAlarmAudio(1)` -> `applyEscalationStep(1)` -> `endAlarmAudio(1)` -> `beginAlarmAudio(2)` execute strictly in submission order.
   - **Immediate stale-step cancellation**: `endAlarmAudio(sessionID:)` clears/advances `activeSessionID` synchronously under `stateLock` before enqueuing `stop()` + `restoreIfNeeded()`, so any pending `applyEscalationStep(sessionID:)` blocks already in `workerQueue` short-circuit on entry without touching CoreAudio.

### 5.2 `SystemAudioVolumeManager` State & Execution Flow

```
@MainActor (SecurityCoordinator)          stateLock (ns)           workerQueue (serial bg)
─────────────────────────────────         ──────────────           ─────────────────────────
enterAlarm()
  ├─ sessionID = nextSessionID()
  └─ beginAlarmAudio(sessionID, ...) ───► activeSessionID = id ──► guard active == id
                                                                   if overrideSpeakers:
                                                                     audioController.forceBuiltInSpeakers(hardwareVolume)
                                                                   guard active == id else { restoreIfNeeded(); return }
                                                                   sirenSynthesizer.start(..., overrideSpeakers: false, outputGain)

tickSirenEscalationIfNeeded() (0.25s)
  └─ applyEscalationStep(sessionID, ...) ► guard active == id ───► guard active == id
                                           dedup (>= 0.005 delta)  if overrideSpeakers:
                                                                     audioController.updateOverrideVolume(hardwareVolume)
                                                                   sirenSynthesizer.setOutputGain(effectiveGain)

performValidatedDisarm()
  └─ endAlarmAudio(sessionID) ──────────► activeSessionID = 0 ───► sirenSynthesizer.stop()
                                                                   audioController.restoreIfNeeded()
```

### 5.3 Speaker Override Disabled (`sirenSpeakerOverrideEnabled == false`)

When `sirenSpeakerOverrideEnabled == false`:
- `SystemAudioVolumeManager` **never** invokes `SystemAudioController.forceBuiltInSpeakers`, `updateOverrideVolume`, or `restoreIfNeeded` (or alters macOS output routing/mute).
- Instead, `sirenSynthesizer.start(..., overrideSpeakers: false, outputGain: evaluation.volumeFactor)` and `sirenSynthesizer.setOutputGain(evaluation.volumeFactor)` modulate `mainMixerNode.outputVolume` from `0.30` to `1.00`, delivering the same progressive escalation curve over the user's current audio path.

---

## 6. Settings Schema & UI Specification

### 6.1 `PupilSettings.swift` Additions

Add to `PupilSettings`:

```swift
public var sirenEscalationCurveEnabled: Bool {
    didSet { defaults.set(sirenEscalationCurveEnabled, forKey: Keys.sirenEscalationCurveEnabled) }
}

public var sirenEscalationProfile: SirenEscalationProfile {
    didSet { defaults.set(sirenEscalationProfile.rawValue, forKey: Keys.sirenEscalationProfile) }
}
```

Persistence keys inside `PupilSettings.Keys`:
- `static let sirenEscalationCurveEnabled = "pupil.sirenEscalationCurveEnabled"`
- `static let sirenEscalationProfile = "pupil.sirenEscalationProfile"`

Initialization defaults in `PupilSettings.init(defaults:)`:
- `sirenEscalationCurveEnabled`: `defaults.object(forKey: Keys.sirenEscalationCurveEnabled) as? Bool ?? false` (opt-in so existing default behavior is preserved until enabled).
- `sirenEscalationProfile`: decoded from `defaults.string(forKey: Keys.sirenEscalationProfile)` via `SirenEscalationProfile(rawValue:)`, defaulting to `.smoothRamp` (so toggling progressive escalation on immediately engages a progressive curve rather than `.immediate`, while preserving the user's selected profile across toggle off/on cycles).

### 6.2 `AlarmSettingsPage.swift` UI Integration

Place inside the top `SettingsGroup` directly after `locationEnvironmentRow` (keeping all siren audio output controls grouped above `"Test speaker"`), animated with `SettingsMetrics.stateTransitionAnimation` matching `GeneralSettingsPage` and `SensorsSettingsPage`:

```swift
SettingsGroupDivider()
SettingsRowContent(
    title: "Progressive siren escalation",
    subtitle: "Starts the alarm at 30% and builds to your configured volume instead of blasting immediately."
) {
    PupilToggle(isOn: $settings.sirenEscalationCurveEnabled)
}
if settings.sirenEscalationCurveEnabled {
    SettingsGroupDivider()
    SettingsRowContent(
        title: "Escalation curve",
        subtitle: settings.sirenEscalationProfile.subtitle
    ) {
        SettingsMenuPickerPill(label: settings.sirenEscalationProfile.title) {
            ForEach(SirenEscalationProfile.allCases) { profile in
                Button(profile.title) {
                    settings.sirenEscalationProfile = profile
                }
            }
        }
    }
}
```

Apply `.animation(SettingsMetrics.stateTransitionAnimation, value: settings.sirenEscalationCurveEnabled)` on the containing `SettingsGroup` (matching `GeneralSettingsPage.swift`). All labels follow sentence-case Pupil conventions and reuse `SettingsGroup`, `SettingsRowContent`, `SettingsGroupDivider`, `SettingsMenuPickerPill`, and `PupilToggle`.

---

## 7. `SecurityCoordinator` Wiring

### 7.1 Properties & Dependency Injection

Add to `SecurityCoordinator`:
- `public let audioVolumeManager: any SystemAudioVolumeManaging`
- `public private(set) var currentSirenVolumeFactor: Float = 1.0`
- `private var activeAudioSessionID: UInt64 = 0`
- `private var lastEscalationEvaluation: SirenEscalationEvaluation?`
- `private var alarmEscalationTimer: Timer?`

Update `SecurityCoordinator.init(...)` with an optional parameter `audioVolumeManager: (any SystemAudioVolumeManaging)? = nil`, defaulting to `SystemAudioVolumeManager.shared`. Existing callers and tests require zero signature changes.

### 7.2 Lifecycle Transitions

1. **`enterAlarm(source: TamperSource, simulated: Bool = false)`**:
   - Invalidate any prior `alarmEscalationTimer`.
   - Latch `alarmStartTime = clock()` (already present in `SecurityCoordinator`).
   - Increment `activeAudioSessionID &+= 1`; let `sessionID = activeAudioSessionID`.
   - Evaluate initial curve state at `elapsedSeconds = 0`:
     ```swift
     let initialEval = SirenEscalationEvaluator.evaluate(
         elapsedSeconds: 0,
         profile: settings.sirenEscalationProfile,
         maxVolume: Float(settings.sirenOverrideVolume),
         enabled: settings.sirenEscalationCurveEnabled
     )
     currentSirenVolumeFactor = initialEval.volumeFactor
     lastEscalationEvaluation = initialEval
     ```
   - Invoke `audioVolumeManager.beginAlarmAudio(sessionID: sessionID, baseFrequencyHz: Double(settings.sirenFrequencyHz), overrideSpeakers: settings.sirenSpeakerOverrideEnabled, initialEvaluation: initialEval)`.
   - If `!initialEval.isComplete`, schedule `alarmEscalationTimer` (`Timer.scheduledTimer(withTimeInterval: SirenEscalationEvaluator.evaluationTickIntervalSeconds, repeats: true)`) invoking `Task { @MainActor [weak self] in self?.tickSirenEscalationIfNeeded() }`.
   - Log `"ALARM LATCHED"` with escalation metadata when progressive escalation is active (`settings.sirenEscalationCurveEnabled && settings.sirenEscalationProfile != .immediate`).

2. **`tickSirenEscalationIfNeeded()` (`public func` on `@MainActor`)**:
   - Guard `state == .alarm`, `let start = alarmStartTime`; otherwise call `stopSirenEscalationTimer()` and return.
   - Compute `elapsed = max(0, clock() - start)`.
   - Evaluate `SirenEscalationEvaluator.evaluate(...)`.
   - Update `currentSirenVolumeFactor = evaluation.volumeFactor`.
   - If `evaluation != lastEscalationEvaluation`:
     - Store `lastEscalationEvaluation = evaluation`.
     - Call `audioVolumeManager.applyEscalationStep(sessionID: activeAudioSessionID, overrideSpeakers: settings.sirenSpeakerOverrideEnabled, evaluation: evaluation)`.
   - If `evaluation.isComplete`, call `stopSirenEscalationTimer()`.

3. **`lockMonitor.onLockEvent` `.wake` while `state == .alarm`**:
   - Replace the current unconditional `SirenSynthesizer.shared.start(..., targetVolume: Float(self.settings.sirenOverrideVolume))` call with `resumeAlarmAudioAtCurrentElapsedTime()`.
   - `resumeAlarmAudioAtCurrentElapsedTime()` computes `elapsed = max(0, clock() - (alarmStartTime ?? clock()))`, evaluates the current `SirenEscalationEvaluation` at `elapsed` (preserving curve position rather than resetting to `0.30` or jumping prematurely to `1.00`), increments `activeAudioSessionID`, calls `audioVolumeManager.beginAlarmAudio(...)`, and restarts `alarmEscalationTimer` if `!evaluation.isComplete`.

4. **`performValidatedDisarm(method: String)`**:
   - Call `stopSirenEscalationTimer()`.
   - Reset `currentSirenVolumeFactor = 1.0` and `lastEscalationEvaluation = nil`.
   - If `wasAlarm || activeAudioSessionID != 0`:
     - Capture `let endedSessionID = activeAudioSessionID`, increment `activeAudioSessionID &+= 1`, and invoke `audioVolumeManager.endAlarmAudio(sessionID: endedSessionID)` (which stops `SirenSynthesizer` and restores `SystemAudioSnapshot` off the main thread).

---

## 8. File Change Map

| File | Action | Purpose |
|---|---|---|
| `Sources/Pupil/Core/SirenEscalationEvaluator.swift` | Create | `SirenEscalationProfile`, `SirenEscalationEvaluation`, and pure `SirenEscalationEvaluator`. |
| `Sources/Pupil/Core/SystemAudioVolumeManager.swift` | Create | `SystemAudioVolumeManaging` protocol and non-blocking `SystemAudioVolumeManager`. |
| `Sources/Pupil/Core/SystemAudioController.swift` | Modify | Cache `activeOverrideDeviceID`; add fast `updateOverrideVolume(_:)` preserving snapshot. |
| `Sources/Pupil/Core/SirenSynthesizer.swift` | Modify | Add `SirenPlaybackControlling`, `outputGain` parameter on `start`, and `setOutputGain(_:)`. |
| `Sources/Pupil/Core/SecurityCoordinator.swift` | Modify | Inject `audioVolumeManager`, wire `enterAlarm`, `tickSirenEscalationIfNeeded`, `.wake` resume, and disarm cleanup. |
| `Sources/Pupil/Settings/PupilSettings.swift` | Modify | Add `sirenEscalationCurveEnabled`, `sirenEscalationProfile`, `Keys`, and UserDefaults init/fallback. |
| `Sources/Pupil/Settings/Pages/AlarmSettingsPage.swift` | Modify | Add sentence-case toggle and conditional profile picker inside `SettingsGroup`. |
| `Tests/PupilTests/SirenEscalationTests.swift` | Create | Deterministic unit & integration test suite (see Section 9). |

---

## 9. Deterministic Test Plan (`Tests/PupilTests/SirenEscalationTests.swift`)

All tests use Swift Testing (`@Suite`, `@Test`, `#expect`), isolated `UserDefaults(suiteName:)`, injectable `MockAudioHardwareBackend`, `MockSirenPlaybackController`, and `coordinator.clock`—with zero wall-clock `sleep` calls and zero real speaker output.

1. **`testImmediateAndDisabledCurveEvaluation`**:
   - Verifies that when `enabled == false` (with `.stepped` or `.smoothRamp`) OR `profile == .immediate` (with `enabled == true`), `SirenEscalationEvaluator.evaluate(elapsedSeconds: 0.0, ...)` immediately returns `volumeFactor == 1.0`, `targetVolume == clampedMaxVolume`, `stageIndex == 0`, and `isComplete == true`.
2. **`testSteppedProfileStageBoundaries`**:
   - With `maxVolume = 1.0` and `rampDurationSeconds = 8.0`, asserts exact step outputs across `[0.0, 3.999]` (`0.30`, stage `1`, `isComplete == false`), `[4.0, 7.999]` (`0.60`, stage `2`, `isComplete == false`), and `[8.0, 30.0]` (`1.00`, stage `3`, `isComplete == true`).
3. **`testSmoothRampMonotonicityAndBoundaryClamping`**:
   - Samples `.smoothRamp` at `-5.0`, `0.0`, `2.0`, `4.0`, `6.0`, `8.0`, `25.0`, `.nan`, and `.infinity`. Verifies exact linear values (`0.30`, `0.30`, `0.475`, `0.65`, `0.825`, `1.00`, `1.00`), safe handling of negative/`NaN`/`infinity`, and strict monotonic non-decreasing invariant (`eval[i].volumeFactor >= eval[i-1].volumeFactor`).
4. **`testEnvironmentCeilingScalingAndHardwareFloorCompensation`**:
   - Tests `.quietLibrary` (`0.45`) and low custom (`0.20`) ceilings. Confirms `0.20` at `t = 0` yields `targetVolume == 0.06`, `hardwareVolume == 0.10` (respecting `SystemAudioController`'s `0.10` floor), and `synthesizerGain == 0.60`, while `t = 8.0` yields `targetVolume == 0.20`, `hardwareVolume == 0.20`, and `synthesizerGain == 1.0`.
5. **`testPupilSettingsPersistenceAndInvalidProfileFallback`**:
   - Verifies defaults (`sirenEscalationCurveEnabled == false`, `sirenEscalationProfile == .smoothRamp`), round-trip persistence across `PupilSettings(defaults:)` reload, and fallback to `.smoothRamp` when an unknown raw string is written to `"pupil.sirenEscalationProfile"`.
6. **`testSystemAudioVolumeManagerSnapshotPreservationAndStaleStepCancellation`**:
   - Uses `MockAudioHardwareBackend` + `MockSirenPlaybackController` + dedicated serial `DispatchQueue` drained via `queue.sync {}`.
   - Verifies `beginAlarmAudio` sets built-in speaker override at `0.24` (`0.30 * 0.80`) and captures `SystemAudioSnapshot` once; `applyEscalationStep` updates volume to `0.48` without altering the snapshot; `endAlarmAudio` stops synthesis, restores the original device/mute/volume, and drops any subsequent stale `applyEscalationStep` for the ended `sessionID`.
7. **`testSystemAudioVolumeManagerSynthesizerOnlyWhenOverrideDisabled`**:
   - With `overrideSpeakers: false`, verifies `MockAudioHardwareBackend` default device, mute state, and hardware volume remain completely unmodified across `beginAlarmAudio`, `applyEscalationStep`, and `endAlarmAudio`, while `MockSirenPlaybackController` receives progressive `setOutputGain` updates (`0.30 -> 0.60 -> 1.00`).
8. **`testSecurityCoordinatorClockDrivenEscalationWakeAndDisarm`**:
   - Injects deterministic `coordinator.clock` and `MockSystemAudioVolumeManager` into `SecurityCoordinator`:
     - Triggers `enterAlarm(source: .chargerUnplugged)` at `t = 1000` with `.stepped` + `sirenOverrideVolume = 0.80` -> asserts `beginAlarmAudio` receives `0.24` (`volumeFactor == 0.30`).
     - Advances `clock` to `1004.0`, calls `tickSirenEscalationIfNeeded()` -> asserts `applyEscalationStep` receives `0.48`.
     - Simulates system wake (`lockMonitor.onLockEvent?(.wake)`) at `1006.0` -> asserts audio resumes at `0.48` (neither resetting to `0.24` nor skipping ahead to `0.80`).
     - Advances `clock` to `1008.0`, calls `tickSirenEscalationIfNeeded()` -> asserts `0.80` (`isComplete == true`).
     - Calls `disarmWithPin("1234")` -> asserts `endAlarmAudio` is invoked and `currentSirenVolumeFactor` resets to `1.0`.
