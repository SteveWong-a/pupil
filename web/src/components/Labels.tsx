import type { Ref } from "react";
import type { FeatureId } from "../scene/macbook";
import styles from "./Labels.module.css";

interface CalloutDef {
  id: FeatureId;
  chapter: "ch1" | "ch2" | "ch3" | "ch4";
  side: "left" | "right";
  title: string;
  note: string;
}

const CALLOUTS: CalloutDef[] = [
  // Chapter 1: Gaze & Instant Screen Blur (Left Callouts)
  { id: "gaze-cam", chapter: "ch1", side: "left", title: "1080p FaceTime HD & ANE", note: "10 FPS on-device gaze cone · 0B written to disk" },
  { id: "gaze-notch", chapter: "ch1", side: "left", title: "Expanding Notch Pill", note: "Instant visual deterrent when a second face looks" },
  { id: "gaze-shield", chapter: "ch1", side: "left", title: "95ms Privacy Blur Shield", note: "Full-screen Gaussian blur before text can be read" },

  // Chapter 2: Charger & Lid Tamper Alert (Left Callouts)
  { id: "tamper-magsafe", chapter: "ch2", side: "left", title: "MagSafe 3 Power Tripwire", note: "150ms IOKit AC unplug interrupt · 15s grace window" },
  { id: "tamper-hinge", chapter: "ch2", side: "left", title: "IOPMAssertion Lid Lockdown", note: "Blocks clamshell sleep on lid-close so alarm stays live" },
  { id: "tamper-siren", chapter: "ch2", side: "left", title: "Progressive 6-Speaker Siren", note: "Library-safe 30% → 100% ramp · forces built-in speakers" },

  // Chapter 3: iPhone Companion Link (Right Callouts)
  { id: "phone-push", chapter: "ch3", side: "right", title: "RFC 8291 Encrypted Web Push", note: "Sub-second APNs lock-screen alert + intruder snapshot" },
  { id: "phone-disarm", chapter: "ch3", side: "right", title: "One-Tap Remote Disarm", note: "Cancel grace countdown or siren from across the room" },
  { id: "phone-ble", chapter: "ch3", side: "right", title: "Bluetooth LE Proximity Radar", note: "Walk-away auto-arm & return auto-disarm (-52 dBm)" },

  // Chapter 4: Seamless macOS UI & Touch ID (Right Callouts)
  { id: "macos-popover", chapter: "ch4", side: "right", title: "Native Menu Bar Popover", note: "One-click arming, gaze toggles & tamper simulation" },
  { id: "macos-settings", chapter: "ch4", side: "right", title: "SwiftUI Settings Suite", note: "Granular gaze dwell, sensor tripwires & quiet library mode" },
  { id: "macos-touchid", chapter: "ch4", side: "right", title: "Circular Touch ID Sensor", note: "Sub-second Secure Enclave biometric disarm on key 13" },
];

export function Labels({ ref }: { ref?: Ref<HTMLDivElement> }) {
  return (
    <div ref={ref} className={styles.labels}>
      {CALLOUTS.map(({ id, chapter, side, title, note }) => (
        <div
          key={id}
          className={`${styles.label} ${styles[side]}`}
          data-feature={id}
          data-chapter={chapter}
          data-side={side}
        >
          <div className={styles.box}>
            <b>{title}</b>
            <span>{note}</span>
          </div>
        </div>
      ))}
    </div>
  );
}
