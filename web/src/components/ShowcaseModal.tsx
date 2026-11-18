import { useEffect, useState } from "react";
import styles from "./ShowcaseModal.module.css";

export type ModalView = "screenshots" | "build";

interface Hotspot {
  x: number;
  y: number;
  title: string;
  desc: string;
}

interface ScreenTab {
  key: string;
  label: string;
  src: string;
  file: string;
  hotspots: Hotspot[];
}

const TABS: ScreenTab[] = [
  {
    key: "general",
    label: "General",
    src: "./assets/screenshots/settings-general.png",
    file: "GeneralSettingsPage.swift",
    hotspots: [
      { x: 78, y: 24, title: "Idle Auto-Arm (5–30m)", desc: "Arms after HID inactivity; ignores closed-lid sleep." },
      { x: 78, y: 48, title: "OS Hardware Lockdown", desc: "Blocks Force Quit, Command-Tab, and Dock during tamper." },
      { x: 68, y: 72, title: "Stepped Grace Timers", desc: "5s–30s window to cancel accidental cable bumps." },
    ],
  },
  {
    key: "gaze",
    label: "Gaze ANE",
    src: "./assets/screenshots/settings-gaze.png",
    file: "GazeSettingsPage.swift",
    hotspots: [
      { x: 78, y: 17, title: "Adaptive Frame Governor", desc: "Scales 10 → 5 → 2 FPS on low battery and thermal load." },
      { x: 70, y: 28, title: "Notch Deterrent Modes", desc: "Switch between live notch wings and silent audit log." },
      { x: 65, y: 42, title: "4-Stage Peripheral Cone", desc: "Expands camera ROI up to 90% for library side angles." },
    ],
  },
  {
    key: "sensors",
    label: "Sensors & Push",
    src: "./assets/screenshots/settings-sensors.png",
    file: "SensorsSettingsPage.swift",
    hotspots: [
      { x: 56, y: 6, title: "Hardware Tripwire Matrix", desc: "Monitors MagSafe, USB-C displays, lid state, and input." },
      { x: 45, y: 39, title: "One-Time QR Pairing", desc: "Direct RFC 8291 Web Push encryption without cloud relays." },
      { x: 65, y: 75, title: "Proximity & Trusted Wi-Fi", desc: "Bluetooth RSSI disarm and SHA-256 Wi-Fi boundaries." },
    ],
  },
  {
    key: "alarm",
    label: "Siren & Vault",
    src: "./assets/screenshots/settings-alarm.png",
    file: "AlarmSettingsPage.swift",
    hotspots: [
      { x: 78, y: 12, title: "Speaker Route Override", desc: "Bypasses headphones and unmutes built-in MacBook speakers." },
      { x: 64, y: 18, title: "Acoustic Ceiling Presets", desc: "Caps siren at 45% (Library), 80% (Cafe), or 100%." },
      { x: 68, y: 50, title: "Encrypted Tamper Journal", desc: "200-event AES-GCM ring buffer with Markdown export." },
    ],
  },
  {
    key: "menubar",
    label: "Menu Bar",
    src: "./assets/screenshots/menubar-popover.png",
    file: "MenuBarPopoverView.swift",
    hotspots: [
      { x: 50, y: 13, title: "Live NSStatusBar Header", desc: "Real-time armed state, grace timer, and AC status." },
      { x: 65, y: 47, title: "1-Click Quick Toggles", desc: "Flip gaze blur and auto-arm without opening Settings." },
      { x: 50, y: 75, title: "Dockless Accessory Mode", desc: "Zero Dock clutter; blocks unauthorized Quit while armed." },
    ],
  },
  {
    key: "shield",
    label: "Screen Shield",
    src: "./assets/screenshots/screen-shield.png",
    file: "ScreenShieldView.swift",
    hotspots: [
      { x: 50, y: 42, title: "Tamper Source Telemetry", desc: "Displays exact hardware trigger and timestamp on lock screen." },
      { x: 59, y: 61, title: "Touch ID & PIN Backoff", desc: "Instant biometric unlock with exponential brute-force lockouts." },
      { x: 50, y: 90, title: "macOS Password Recovery", desc: "LocalAuthentication fallback resets PIN lockout cleanly." },
    ],
  },
];

const BUILD_CMD = `git clone https://github.com/stevewong-a/pupil.git
cd pupil && ./scripts/package_dmg.sh
open dist/Pupil.app`;

interface ShowcaseModalProps {
  view: ModalView | null;
  onClose: () => void;
  onSwitchView: (v: ModalView) => void;
}

export function ShowcaseModal({ view, onClose, onSwitchView }: ShowcaseModalProps) {
  const [tabIdx, setTabIdx] = useState(0);
  const [spotIdx, setSpotIdx] = useState(0);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!view) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [view, onClose]);

  if (!view) return null;
  const tab = TABS[tabIdx];
  const spot = tab.hotspots[spotIdx] || tab.hotspots[0];

  return (
    <div
      className={styles.backdrop}
      role="dialog"
      aria-modal="true"
      aria-label="Pupil macOS App UI & Local Build"
      onClick={onClose}
    >
      <div className={styles.modal} onClick={(e) => e.stopPropagation()}>
        <div className={styles.header}>
          <div className={styles.modeTabs}>
            <button
              type="button"
              className={`${styles.modeBtn} ${view === "screenshots" ? styles.modeActive : ""}`}
              onClick={() => onSwitchView("screenshots")}
            >
              macOS App UI ({TABS.length} Views)
            </button>
            <button
              type="button"
              className={`${styles.modeBtn} ${view === "build" ? styles.modeActive : ""}`}
              onClick={() => onSwitchView("build")}
            >
              Build from Source (30s)
            </button>
          </div>
          <button type="button" className={styles.closeBtn} onClick={onClose} aria-label="Close modal">
            ✕
          </button>
        </div>

        {view === "screenshots" ? (
          <div className={styles.body}>
            <div className={styles.screenTabs} role="tablist">
              {TABS.map((t, i) => (
                <button
                  key={t.key}
                  type="button"
                  role="tab"
                  aria-selected={i === tabIdx}
                  className={`${styles.tabBtn} ${i === tabIdx ? styles.tabActive : ""}`}
                  onClick={() => {
                    setTabIdx(i);
                    setSpotIdx(0);
                  }}
                >
                  {t.label}
                </button>
              ))}
            </div>

            <div className={styles.stageGrid}>
              <div className={styles.viewport}>
                <div className={styles.imgWrap}>
                  <img src={tab.src} alt={tab.label} className={styles.screenshot} />
                  {tab.hotspots.map((h, i) => (
                    <button
                      key={h.title}
                      type="button"
                      style={{ left: `${h.x}%`, top: `${h.y}%` }}
                      className={`${styles.pin} ${i === spotIdx ? styles.pinActive : ""}`}
                      onClick={() => setSpotIdx(i)}
                      aria-label={`Hotspot ${i + 1}: ${h.title}`}
                    >
                      {i + 1}
                    </button>
                  ))}
                </div>
              </div>

              <div className={styles.inspector}>
                <p className={styles.meta}>
                  {tab.file} · Hotspot {spotIdx + 1} of {tab.hotspots.length}
                </p>
                <h3 className={styles.spotTitle}>{spot.title}</h3>
                <p className={styles.spotDesc}>{spot.desc}</p>
                <div className={styles.spotList}>
                  {tab.hotspots.map((h, i) => (
                    <button
                      key={h.title}
                      type="button"
                      className={`${styles.spotItem} ${i === spotIdx ? styles.spotItemActive : ""}`}
                      onClick={() => setSpotIdx(i)}
                    >
                      <span>{i + 1}</span>
                      <b>{h.title}</b>
                    </button>
                  ))}
                </div>
                <a href="./companion.html" className={styles.companionLink}>
                  Open iPhone Web Push Companion PWA →
                </a>
              </div>
            </div>
          </div>
        ) : (
          <div className={styles.buildBody}>
            <p className={styles.meta}>Swift 6.0 · macOS 14+ · Zero external runtime dependencies</p>
            <h3 className={styles.spotTitle}>Compile &amp; launch Pupil.app in 30 seconds.</h3>
            <p className={styles.spotDesc}>
              Auditable native source using Apple Vision ANE, IOKit, CoreAudio, CryptoKit, and LocalAuthentication.
            </p>
            <pre className={styles.codeBlock}>
              <code>{BUILD_CMD}</code>
            </pre>
            <div className={styles.buildActions}>
              <button
                type="button"
                className={styles.copyBtn}
                onClick={async () => {
                  try {
                    await navigator.clipboard.writeText(BUILD_CMD);
                    setCopied(true);
                    setTimeout(() => setCopied(false), 2000);
                  } catch {
                    // ignore clipboard errors
                  }
                }}
              >
                {copied ? "Copied Commands!" : "Copy Terminal Commands"}
              </button>
              <a href="./companion.html" className={styles.companionLink}>
                Open iPhone Companion PWA →
              </a>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
