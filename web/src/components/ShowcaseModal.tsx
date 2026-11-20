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
  isIframe?: boolean;
  hotspots: Hotspot[];
}

const TABS: ScreenTab[] = [
  {
    key: "general",
    label: "General",
    src: "./assets/screenshots/settings-general.png",
    file: "General Settings",
    hotspots: [
      { x: 78, y: 24, title: "Auto-Arm When Idle (5-30m)", desc: "Arms automatically after you stop using your keyboard and mouse." },
      { x: 78, y: 48, title: "Screen Lockdown", desc: "Keeps the shield on top and blocks Force Quit during an alarm." },
      { x: 68, y: 72, title: "Grace Countdown", desc: "Gives you 5 to 30 seconds to cancel an accidental cable bump." },
    ],
  },
  {
    key: "gaze",
    label: "Gaze Blur",
    src: "./assets/screenshots/settings-gaze.png",
    file: "Gaze Settings",
    hotspots: [
      { x: 78, y: 17, title: "Battery-Friendly Camera", desc: "Slows camera checks automatically when battery is low or your Mac warms up." },
      { x: 70, y: 28, title: "Notch Alert Style", desc: "Switch between a visible notch warning or quiet screen blur." },
      { x: 65, y: 42, title: "Wide Side Detection", desc: "Spots people glancing from the side at nearby cafe or library tables." },
    ],
  },
  {
    key: "sensors",
    label: "Sensors & iPhone",
    src: "./assets/screenshots/settings-sensors.png",
    file: "Sensors Settings",
    hotspots: [
      { x: 56, y: 6, title: "Tamper Sensors", desc: "Watches your charger, unplugged cables, lid close, and sudden movement." },
      { x: 45, y: 39, title: "One-Time QR Pairing", desc: "Scan once in Safari on your iPhone for encrypted alerts with no account." },
      { x: 65, y: 75, title: "Walk-Away & Trusted Wi-Fi", desc: "Arms when your iPhone leaves Bluetooth range and pauses on home Wi-Fi." },
    ],
  },
  {
    key: "alarm",
    label: "Siren & Log",
    src: "./assets/screenshots/settings-alarm.png",
    file: "Alarm Settings",
    hotspots: [
      { x: 78, y: 12, title: "Built-In Speaker Override", desc: "Plays the siren through your MacBook speakers even if headphones are plugged in." },
      { x: 64, y: 18, title: "Volume Presets", desc: "Cap the siren at 45% for libraries, 80% for cafes, or full volume." },
      { x: 68, y: 50, title: "Encrypted Event Log", desc: "Saves a local history of alerts you can export anytime." },
    ],
  },
  {
    key: "menubar",
    label: "Menu Bar",
    src: "./assets/screenshots/menubar-popover.png",
    file: "Menu Bar Popover",
    hotspots: [
      { x: 50, y: 13, title: "Live Menu Bar Status", desc: "See armed status, countdown timer, and charger state at a glance." },
      { x: 65, y: 47, title: "One-Click Toggles", desc: "Turn gaze blur or auto-arm on and off without opening Settings." },
      { x: 50, y: 75, title: "Stays Out of Your Dock", desc: "Runs quietly in the menu bar and blocks quitting while armed." },
    ],
  },
  {
    key: "shield",
    label: "Screen Shield",
    src: "./assets/screenshots/screen-shield.png",
    file: "Screen Shield",
    hotspots: [
      { x: 50, y: 42, title: "Clear Alert Reason", desc: "Shows exactly what triggered the alert and when it happened." },
      { x: 59, y: 61, title: "Touch ID & PIN Unlock", desc: "Unlock in under a second with Touch ID or your backup PIN." },
      { x: 50, y: 90, title: "Mac Password Recovery", desc: "Use your Mac login password if you ever forget your PIN." },
    ],
  },
  {
    key: "companion",
    label: "Mobile Companion",
    src: "./companion.html",
    file: "iPhone Companion",
    isIframe: true,
    hotspots: [
      { x: 50, y: 24, title: "Direct iPhone Pairing", desc: "Scan the QR code in Settings once. No cloud accounts or logins." },
      { x: 50, y: 54, title: "Snapshot Preview", desc: "Check a camera snapshot on your iPhone before choosing to disarm." },
      { x: 50, y: 82, title: "One-Tap Remote Disarm", desc: "Silence the alarm and clear the Screen Shield from across the library or cafe." },
    ],
  },
];

const BUILD_CMD = `git clone https://github.com/SteveWong-a/pupil.git
cd pupil && ./scripts/build-dmg.sh
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
              Build from Source (Optional)
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
                  {tab.isIframe ? (
                    <div className={styles.phoneFrame}>
                      <iframe src={tab.src} title={tab.label} className={styles.phoneIframe} />
                    </div>
                  ) : (
                    <>
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
                    </>
                  )}
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
            <p className={styles.meta}>Optional · macOS 14 or later · Apple Silicon &amp; Intel</p>
            <h3 className={styles.spotTitle}>Build Pupil.app from source (optional).</h3>
            <p className={styles.spotDesc}>
              Most users can download the ready-to-run app from GitHub Releases. If you prefer to build from source
              yourself, run these commands in Terminal.
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
              <a
                href="https://github.com/SteveWong-a/pupil/releases/latest"
                target="_blank"
                rel="noopener noreferrer"
                className={styles.companionLink}
              >
                Download Ready-to-Run DMG →
              </a>
              <a href="./companion.html" className={styles.companionLink}>
                Open iPhone Companion →
              </a>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
