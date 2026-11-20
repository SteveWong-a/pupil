import type { FeatureId } from "./macbook";
import type { SectionName } from "./uiHandles";

export type ChapterKey = "ch1" | "ch2" | "ch3" | "ch4";

export interface FeatureShotSpec {
  id: FeatureId;
  chapter: ChapterKey;
  section: SectionName;
  side: "left" | "right";
  title: string;
  note: string;
  /** Optional world-space offset added to mb.featurePoint(id) for ideal framing */
  targetOffset?: [number, number, number];
  az: number;
  el: number;
  dist: number;
  fov: number;
  shiftX?: number;
  shiftY?: number;
  bokeh: number;
  focusRange: number;
}

export const FEATURE_LIST: FeatureShotSpec[] = [
  // Chapter 1: Gaze & Instant Screen Blur
  {
    id: "gaze-cam",
    chapter: "ch1",
    section: "gaze",
    side: "left",
    title: "1080p FaceTime HD & ANE",
    note: "10 FPS on-device gaze cone · 0B written to disk",
    targetOffset: [0, -0.5, 0.2],
    az: -0.06,
    el: 0.08,
    dist: 17.5,
    fov: 25,
    shiftX: 0,
    shiftY: -0.04,
    bokeh: 2.0,
    focusRange: 10,
  },
  {
    id: "gaze-notch",
    chapter: "ch1",
    section: "gaze",
    side: "left",
    title: "Expanding Notch Pill",
    note: "Instant visual deterrent when a second face looks",
    targetOffset: [1.6, -0.35, 0.2],
    az: -0.08,
    el: 0.08,
    dist: 20.5,
    fov: 26,
    shiftX: 0,
    shiftY: -0.03,
    bokeh: 1.8,
    focusRange: 12,
  },
  {
    id: "gaze-shield",
    chapter: "ch1",
    section: "gaze",
    side: "left",
    title: "95ms Privacy Blur Shield",
    note: "Full-screen Gaussian blur before text can be read",
    targetOffset: [7.5, 0.4, 0.4],
    az: -0.06,
    el: 0.1,
    dist: 34,
    fov: 28,
    shiftX: 0,
    shiftY: -0.02,
    bokeh: 1.2,
    focusRange: 18,
  },

  // Chapter 2: Charger & Lid Tamper Alert
  {
    id: "tamper-magsafe",
    chapter: "ch2",
    section: "tamper",
    side: "left",
    title: "MagSafe 3 Power Tripwire",
    note: "150ms IOKit AC unplug interrupt · 15s grace window",
    targetOffset: [0.4, 0.4, 0.1],
    az: -1.16,
    el: 0.2,
    dist: 17.5,
    fov: 25,
    shiftX: 0,
    shiftY: -0.03,
    bokeh: 2.3,
    focusRange: 9,
  },
  {
    id: "tamper-hinge",
    chapter: "ch2",
    section: "tamper",
    side: "left",
    title: "IOPMAssertion Lid Lockdown",
    note: "Blocks clamshell sleep on lid-close so alarm stays live",
    targetOffset: [1.5, -0.4, 0.5],
    az: -0.92,
    el: 0.28,
    dist: 24,
    fov: 26,
    shiftX: 0,
    shiftY: -0.02,
    bokeh: 1.9,
    focusRange: 13,
  },
  {
    id: "tamper-siren",
    chapter: "ch2",
    section: "tamper",
    side: "left",
    title: "Progressive 6-Speaker Siren",
    note: "Library-safe 30% → 100% ramp · forces built-in speakers",
    targetOffset: [1.2, 0.1, 0],
    az: -0.56,
    el: 0.54,
    dist: 19,
    fov: 26,
    shiftX: 0,
    shiftY: -0.02,
    bokeh: 2.1,
    focusRange: 10,
  },

  // Chapter 3: iPhone Companion Link
  {
    id: "phone-push",
    chapter: "ch3",
    section: "phone",
    side: "right",
    title: "RFC 8291 Encrypted Web Push",
    note: "Sub-second APNs lock-screen alert + intruder snapshot",
    targetOffset: [-2.4, 0.4, 0.4],
    az: 0.12,
    el: 0.26,
    dist: 18.5,
    fov: 26,
    shiftX: 0,
    shiftY: -0.02,
    bokeh: 2.0,
    focusRange: 11,
  },
  {
    id: "phone-disarm",
    chapter: "ch3",
    section: "phone",
    side: "right",
    title: "One-Tap Remote Disarm",
    note: "Cancel grace countdown or siren from across the room",
    targetOffset: [-2.4, 0.2, 0],
    az: 0.16,
    el: 0.22,
    dist: 16.5,
    fov: 25,
    shiftX: 0,
    shiftY: -0.02,
    bokeh: 2.2,
    focusRange: 10,
  },
  {
    id: "phone-ble",
    chapter: "ch3",
    section: "phone",
    side: "right",
    title: "Bluetooth LE Proximity Radar",
    note: "Walk-away auto-arm & return auto-disarm (-52 dBm)",
    targetOffset: [-2.4, 0.2, -0.8],
    az: 0.22,
    el: 0.3,
    dist: 19.5,
    fov: 26,
    shiftX: 0,
    shiftY: -0.02,
    bokeh: 1.9,
    focusRange: 12,
  },

  // Chapter 4: Seamless macOS UI & Touch ID
  {
    id: "macos-popover",
    chapter: "ch4",
    section: "macos",
    side: "right",
    title: "Native Menu Bar Popover",
    note: "One-click arming, gaze toggles & tamper simulation",
    targetOffset: [-2.2, -0.6, 0.3],
    az: -0.1,
    el: 0.12,
    dist: 24,
    fov: 26,
    shiftX: 0,
    shiftY: -0.02,
    bokeh: 1.7,
    focusRange: 13,
  },
  {
    id: "macos-settings",
    chapter: "ch4",
    section: "macos",
    side: "right",
    title: "SwiftUI Settings Suite",
    note: "Granular gaze dwell, sensor tripwires & quiet library mode",
    targetOffset: [-1.2, 0, 0.3],
    az: -0.08,
    el: 0.12,
    dist: 26,
    fov: 27,
    shiftX: 0,
    shiftY: -0.02,
    bokeh: 1.5,
    focusRange: 15,
  },
  {
    id: "macos-touchid",
    chapter: "ch4",
    section: "macos",
    side: "right",
    title: "Circular Touch ID Sensor",
    note: "Sub-second Secure Enclave biometric disarm on key 13",
    targetOffset: [-0.2, 0.15, 0.1],
    az: -0.26,
    el: 0.62,
    dist: 13.5,
    fov: 24,
    shiftX: 0,
    shiftY: -0.03,
    bokeh: 2.6,
    focusRange: 7.5,
  },
];

export const FEATURE_SHOTS: Record<FeatureId, FeatureShotSpec> = Object.fromEntries(
  FEATURE_LIST.map((f) => [f.id, f]),
) as Record<FeatureId, FeatureShotSpec>;

export const CHAPTER_FEATURES: Record<ChapterKey, FeatureShotSpec[]> = {
  ch1: FEATURE_LIST.filter((f) => f.chapter === "ch1"),
  ch2: FEATURE_LIST.filter((f) => f.chapter === "ch2"),
  ch3: FEATURE_LIST.filter((f) => f.chapter === "ch3"),
  ch4: FEATURE_LIST.filter((f) => f.chapter === "ch4"),
};
