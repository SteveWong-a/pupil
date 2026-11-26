import type { Ref } from "react";
import { Button } from "./Button";
import styles from "./Final.module.css";

// Waitlist signups go to the "Pupil Count Me In" Google Form. The site used
// to capture emails locally (localStorage only, never reaching Steve); that
// submit path is removed, and this button opens the form in a new tab.
const GOOGLE_FORM_URL =
  "https://docs.google.com/forms/d/e/1FAIpQLSdk2oa2VkkAckSCynxuKdIyA4WHW3MGRp8U1aUxTugP4DmULA/viewform";

const INSTALL_STEPS = [
  {
    step: "1",
    title: "Download & install",
    body: "Download Pupil and drag it to Applications.",
  },
  {
    step: "2",
    title: "Open on first launch",
    body: "Open Pupil from Applications. If macOS blocks first launch, right-click Pupil.app and click Open, or run:",
    code: "xattr -cr /Applications/Pupil.app",
  },
  {
    step: "3",
    title: "Arm and step away",
    body: "Press Cmd+A to arm it when you sit down. Step away and Pupil watches your Mac.",
  },
] as const;

const SCREENSHOTS = [
  {
    src: "./assets/screenshots/menubar-popover.png",
    label: "Menu Bar Popover",
    alt: "Pupil menu bar popover showing armed status and quick toggles",
  },
  {
    src: "./assets/screenshots/screen-shield.png",
    label: "Screen Shield",
    alt: "Pupil full-screen lock shield with Touch ID and PIN unlock",
  },
  {
    src: "./assets/screenshots/settings-general.png",
    label: "General Settings",
    alt: "Pupil general settings panel for auto-arm and lockdown rules",
  },
  {
    src: "./assets/screenshots/settings-gaze.png",
    label: "Gaze Settings",
    alt: "Pupil gaze settings panel for dwell time and sensitivity",
  },
  {
    src: "./assets/screenshots/settings-sensors.png",
    label: "Sensors & iPhone Pairing",
    alt: "Pupil sensors settings panel with iPhone QR pairing",
  },
  {
    src: "./assets/screenshots/settings-alarm.png",
    label: "Alarm Settings",
    alt: "Pupil alarm settings panel for siren volume and event log",
  },
] as const;

const FAQS = [
  {
    q: "Does it drain my battery?",
    a: "Uses a 10 FPS default camera rate and automatically throttles down to 5 FPS below 30% battery or moderate heat, and 2 FPS under heavy thermal load.",
  },
  {
    q: "What if it triggers a false alarm?",
    a: "You can adjust gaze dwell time (0.5s to 3.0s) and sensitivity in Settings, and disarm anytime with Touch ID or your PIN.",
  },
  {
    q: "Does it work on Intel Macs?",
    a: "Yes. Any Apple Silicon or Intel Mac running macOS 14 or later with a built-in camera is supported.",
  },
  {
    q: "What can Pupil not stop?",
    a: "Pupil is a software deterrent. It cannot stop someone who force-powers-off your Mac by holding the power button for 10 seconds, or physically carries it away while ignoring the siren.",
  },
] as const;

interface FinalProps {
  ref?: Ref<HTMLElement>;
  onOpenScreenshots: () => void;
  onOpenBuild: () => void;
}

export function Final({ ref, onOpenScreenshots, onOpenBuild }: FinalProps) {
  return (
    <section ref={ref} id="download" className={styles.final} aria-label="Download and details">
      <div className={styles.container}>
        {/* a. Download & 3-Step Install */}
        <header className={styles.heroBlock}>
          <p className={styles.eyebrow}>Download for macOS</p>
          <h2 className={styles.title}>
            Leave your desk, <br />
            <em>keep your peace.</em>
          </h2>
          <p className={styles.closer}>
            Free, open-source macOS app. Runs locally on your Mac with zero cloud accounts.
          </p>

          <div className={styles.ctaRow}>
            <Button href="https://github.com/SteveWong-a/pupil/releases/latest">
              Download Pupil for macOS (.dmg)
            </Button>
            <Button
              href="#build"
              ghost
              onClick={(e) => {
                e.preventDefault();
                onOpenBuild();
              }}
            >
              Build from source (optional)
            </Button>
          </div>

          <ol className={styles.stepsGrid}>
            {INSTALL_STEPS.map((item) => (
              <li key={item.step} className={styles.stepCard}>
                <span className={styles.stepBadge}>{item.step}</span>
                <h3 className={styles.stepTitle}>{item.title}</h3>
                <p className={styles.stepBody}>{item.body}</p>
                {"code" in item && item.code ? (
                  <code className={styles.inlineCode}>{item.code}</code>
                ) : null}
              </li>
            ))}
          </ol>
        </header>

        {/* b. Screenshots & Demo Video Slot */}
        <section className={styles.block} aria-labelledby="screenshots-heading">
          <div className={styles.blockHeader}>
            <div>
              <p className={styles.eyebrow}>App Tour</p>
              <h3 id="screenshots-heading" className={styles.blockTitle}>
                Screenshots &amp; Demo
              </h3>
            </div>
            <Button
              href="#app-ui"
              ghost
              small
              onClick={(e) => {
                e.preventDefault();
                onOpenScreenshots();
              }}
            >
              Inspect Interactive App UI
            </Button>
          </div>

          <div className={styles.screensGrid}>
            {SCREENSHOTS.map((shot) => (
              <button
                key={shot.src}
                type="button"
                className={styles.shotCard}
                onClick={onOpenScreenshots}
              >
                <div className={styles.shotThumbWrap}>
                  <img src={shot.src} alt={shot.alt} loading="lazy" className={styles.shotThumb} />
                </div>
                <span className={styles.shotLabel}>{shot.label}</span>
              </button>
            ))}
          </div>

          <div className={styles.demoPlaceholder}>
            <div className={styles.demoTag}>Demo Video / GIF Placeholder</div>
            <h4 className={styles.demoTitle}>30-Second Walkthrough Slot</h4>
            <p className={styles.demoBody}>
              Record a 30-second clip showing: arm with Cmd+A, walk into frame, screen blurs, unplug charger for countdown, disarm with Touch ID.
            </p>
          </div>
        </section>

        {/* c. How Gaze Detection Works */}
        <section className={styles.block} aria-labelledby="gaze-heading">
          <div className={styles.infoCard}>
            <p className={styles.eyebrow}>On-Device Privacy</p>
            <h3 id="gaze-heading" className={styles.blockTitle}>
              How Gaze Detection Works
            </h3>
            <p className={styles.infoBody}>
              Gaze detection runs fully on-device and never saves a photo or video. Pupil does <strong>not</strong> use face enrollment or facial recognition: when armed, any sustained gaze looking at your screen inside the camera view triggers the blur, and it clears automatically once they look away. People walking past quickly reset the timer so they do not trigger it. You can tune dwell time (0.5s to 3.0s) and sensitivity in Settings. When an alarm fires, one verification photo goes to your paired iPhone.
            </p>
          </div>
        </section>

        {/* d. Requirements & iPhone Pairing Pointer */}
        <section className={styles.twoCol} aria-label="System requirements and iPhone companion">
          <div className={styles.infoCard}>
            <p className={styles.eyebrow}>System Requirements</p>
            <h3 className={styles.cardTitle}>Supported Macs &amp; iPhones</h3>
            <p className={styles.infoBody}>
              macOS 14 or later. Any Apple Silicon or Intel Mac with a built-in camera. iPhone alerts work with any iPhone running iOS 16.4 or later through Safari. Add Pupil to your Home Screen once to pair it.
            </p>
          </div>

          <div className={`${styles.infoCard} ${styles.phoneCard}`}>
            <p className={styles.eyebrow}>iPhone Companion</p>
            <h3 className={styles.cardTitle}>Pairing from your phone</h3>
            <p className={styles.infoBody}>
              On your iPhone? Open this site in Safari, add it to your Home Screen, and scan the QR code in Pupil Settings on your Mac.
            </p>
            <div className={styles.cardAction}>
              <Button href="./companion.html" ghost small>
                Open iPhone Companion
              </Button>
            </div>
          </div>
        </section>

        {/* e. FAQ (4 code-verified questions) */}
        <section className={styles.block} aria-labelledby="faq-heading">
          <p className={styles.eyebrow}>Frequently Asked Questions</p>
          <h3 id="faq-heading" className={styles.blockTitle}>
            Details &amp; Trade-offs
          </h3>
          <div className={styles.faqGrid}>
            {FAQS.map((item) => (
              <article key={item.q} className={styles.faqCard}>
                <h4 className={styles.faqQuestion}>{item.q}</h4>
                <p className={styles.faqAnswer}>{item.a}</p>
              </article>
            ))}
          </div>
        </section>

        {/* f. Secondary Waitlist (demoted below Download & FAQ) */}
        <section id="waitlist" className={styles.waitlistBox} aria-labelledby="waitlist-heading">
          <p className={styles.eyebrow}>Optional Updates</p>
          <h3 id="waitlist-heading" className={styles.waitlistTitle}>
            Get notified about future Pupil releases
          </h3>
          <p className={styles.waitlistSub}>
            Download is available right now above. Join the waitlist if you want occasional release notes.
          </p>

          <div className={styles.form}>
            <a
              href={GOOGLE_FORM_URL}
              target="_blank"
              rel="noopener noreferrer"
              className={styles.submitBtn}
            >
              Get Updates
            </a>
          </div>
        </section>

        <footer className={styles.footer}>
          <small className={styles.footnote}>
            &copy; 2026 Pupil · Local-Only macOS Security Sentinel
          </small>
          <div className={styles.footerLinks}>
            <a
              href="https://github.com/SteveWong-a/pupil"
              target="_blank"
              rel="noopener noreferrer"
              className={styles.footerLink}
            >
              GitHub
            </a>
            <a
              href="https://github.com/SteveWong-a/pupil/issues"
              target="_blank"
              rel="noopener noreferrer"
              className={styles.footerLink}
            >
              GitHub Issues
            </a>
          </div>
        </footer>
      </div>
    </section>
  );
}
