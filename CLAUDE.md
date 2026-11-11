# Pupil — Claude Code notes

macOS menu bar app that guards an unattended laptop. `SecurityCoordinator` (Core) is the hub: settings, notch overlay and screen shield arm/disarm it; camera vision and hardware monitors feed it events that escalate to countdown, siren and phone push.

## Escalation pipeline

```
Camera frame (~10 FPS) → gaze + motion samples → SecurityCoordinator
Hardware (charger, lid, lock, wake) ──────────→ triggerTamper
                                                   │
        states: disarmed → arming → armed → tamperPending (grace countdown) → alarm
                                                   │
                                  siren + AlertNotifier (phone push)
```

## Testing notes

- Run the full test suite with `swift test`.
- Headless test runners lacking `NSCameraUsageDescription` are safely handled via `CameraManager.isCaptureEnabled` to prevent TCC SIGABRT crashes.
- Synthetic camera frames for motion tests live in `Tests/PupilTests/SpatialLiftSyntheticTests.swift` (`SynthScene`).

## Work log: spatial lift fixes, escalation changes, and revisions

### 1. Spatial lift detection (`Vision/VisionMotionDetector.swift`)

Findings from running real Vision registration on synthetic frames:

| Finding | Evidence |
|---|---|
| Flat top band gave garbage | Blank ceiling + a little sensor noise scored ~22 (trigger is 1); a real shift elsewhere in the frame was invisible |
| Homography score is erratic | A 5 px shift scored 15, a 10 px shift scored 0.4, so the score flickered |
| Timer reset on any weak frame | The 1.2 s "sustained" clock restarted on every dip |
| A big move reads as no motion | After a lift the scene no longer overlaps the single anchor frame |

Changes & Optimizations:

- Analyze the **whole frame**, downscaled to 320×240, with faces masked (was: top 25% only).
- **Texture gate** (`textureEnergy`, threshold `minimumTextureEnergy`): a flat scene is marked `isRegistrationReliable = false` and ignored instead of producing a random score.
- **Cached anchor texture energy**: `anchorTextureEnergyValue` is computed once when the anchor frame is locked, eliminating redundant 80×60 gradient computations at 10 FPS.
- **Frame-to-frame translation** (`MotionSample.interFrameTranslation`, deadband `SpatialMotionSensitivity.interFrameDeadband`) so a large move still registers after the anchor stops overlapping.
- **Dropout tolerance** (`motionDropoutToleranceSeconds = 0.4`): a short dip below the deadband no longer resets the sustained-motion clock. The 0.5 s table-bump rule is unchanged.
- **Tuned homography deadband**: raised High sensitivity `warpDeadband` to `0.12` to prevent baseline camera sensor noise (scored ~0.083 / ratio ~1.04) from causing false alarms.

### 2. Tamper confirmation (`Core/TamperScorer.swift`, `Core/SecurityCoordinator.swift`)

Camera motion and lens-blocked are **weak** signals (lighting changes and people can fake them). Charger, lid, lock, wake and manual test are **strong** signals.

| Situation | Result |
|---|---|
| Motion alone (< 4 s) | Event log "Motion Detected (unconfirmed)", at most once per 10 s. No countdown |
| Motion persisting ≥ 4 s (`loneLiftEscalationSeconds`) | Normal grace countdown (`tamperPending`) |
| Lens blocked alone, ≥ 8 s (`loneOcclusionEscalationSeconds`) | Normal grace countdown (`tamperPending`) |
| Motion, then a strong signal (or vice-versa) | Normal grace countdown (never skips countdown; preserves owner's disarm window) |
| Motion while a countdown from another source is running | Countdown continues (does NOT cut countdown short or alarm immediately) |
| Strong signal alone | Normal grace countdown |

Design Rule: Legitimate owners who approach their laptop and unplug the charger or touch the keyboard must always receive their full configured grace period (`settings.gracePeriodSeconds`) to scan Touch ID or enter their PIN without false siren alarms.

### 3. Alert delivery (`Core/AlertNotifier.swift`, `Core/WebPushManager.swift`)

The coordinator routes all pushes through `alertNotifier.send(AlertMessage)`.

- Serial, ordered queue. A newer message with the same tag replaces one still waiting.
- Preemption & superseding: A `critical` alarm message immediately cancels and preempts in-flight retries of a `pupil-tamper` countdown push so theft alerts dispatch without delay.
- Retries with backoff 1 s, 3 s, 8 s for transient failures (timeout, 429, 5xx). 404/410 and other 4xx are not retried.
- Results appear in the event log ("Phone Alert Delivered" / "Phone Alert Failed").
- `WebPushManager.deliverPush` makes one attempt and returns a `PushOutcome`; `sendPushNotification` wraps it.

### 4. Camera lifecycle fix (`Vision/CameraManager.swift`, `Core/SecurityCoordinator.swift`)

- Camera monitoring lifecycle (`syncCameraLifecycle`) now runs when `isMonitoring && (settings.gazeDetectionEnabled || settings.isSpatialMotionEnabled)`. This fixes the previous bug where arming on battery with Spatial Lift active but Gaze disabled left the camera off.
- `CameraManager.isCaptureEnabled` safely gates camera session activation when running in headless test harnesses.

## Files touched

- `Sources/Pupil/Vision/VisionMotionDetector.swift` (~)
- `Sources/Pupil/Settings/PupilSettings.swift` (~, `interFrameDeadband`)
- `Sources/Pupil/Core/SecurityCoordinator.swift` (~)
- `Sources/Pupil/Core/WebPushManager.swift` (~)
- `Sources/Pupil/Core/TamperScorer.swift` (+)
- `Sources/Pupil/Core/AlertNotifier.swift` (+)
- `Tests/PupilTests/PupilSecurityTests.swift` (~, updated lift test, added `TamperConfirmationTests`)
- `Tests/PupilTests/SpatialLiftSyntheticTests.swift` (+)
