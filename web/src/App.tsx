import { useEffect, useRef, useState } from "react";
import type { Experience } from "./scene/director";
import type { SectionName } from "./scene/uiHandles";
import { Nav } from "./components/Nav";
import { Loader } from "./components/Loader";
import { Hero } from "./components/Hero";
import { Panel } from "./components/Panel";
import { Labels } from "./components/Labels";
import { Final } from "./components/Final";
import { ShowcaseModal, type ModalView } from "./components/ShowcaseModal";
import styles from "./App.module.css";

const GAZE = {
  eyebrow: "01 · Gaze Detection & Privacy Shield",
  title: (
    <>
      Someone looks. <br />
      Screen blurs <em>in 95ms.</em>
    </>
  ),
  body: "10 FPS Apple Vision gaze tracking on the M4 Neural Engine detects shoulder-surfers in real time, expanding the Notch pill and frosting your desktop before a single line can be read.",
};

const TAMPER = {
  eyebrow: "02 · Hardware Tripwires & Lockdown",
  title: (
    <>
      Unplug or lid slam. <br />
      Instant <em>lockdown.</em>
    </>
  ),
  body: "IOKit power and lid-angle tripwires fire in 150ms. Unplugging MagSafe 3 or closing the display blocks clamshell sleep via IOPMAssertion and launches a 15-second countdown into a progressive 30% → 100% siren.",
};

const PHONE = {
  eyebrow: "03 · iPhone Companion & Proximity",
  title: (
    <>
      Alerted on iPhone. <br />
      Disarmed <em>from afar.</em>
    </>
  ),
  body: "RFC 8291 encrypted Web Push delivers an instant lock-screen alert and intruder snapshot to your iPhone 16 Pro—with one-tap remote disarm and Bluetooth LE walk-away auto-arming.",
};

const MACOS = {
  eyebrow: "04 · Native macOS UI & Touch ID",
  title: (
    <>
      Built into the Notch. <br />
      Unlocked by <em>Touch ID.</em>
    </>
  ),
  body: "Lives natively in the macOS Sequoia menu bar and display notch. Tap the circular Touch ID sensor on the Magic Keyboard to disarm in under a second.",
};

export function App() {
  const canvas = useRef<HTMLCanvasElement>(null);
  const veil = useRef<HTMLDivElement>(null);
  const nav = useRef<HTMLElement>(null);
  const hero = useRef<HTMLElement>(null);
  const cue = useRef<HTMLSpanElement>(null);
  const gaze = useRef<HTMLElement>(null);
  const tamper = useRef<HTMLElement>(null);
  const phone = useRef<HTMLElement>(null);
  const macos = useRef<HTMLElement>(null);
  const final = useRef<HTMLElement>(null);
  const labels = useRef<HTMLDivElement>(null);
  const experience = useRef<Experience | null>(null);
  const [active, setActive] = useState<SectionName | null>("overview");
  const [modalView, setModalView] = useState<ModalView | null>(null);
  const [sceneReady, setSceneReady] = useState(false);
  const lockResolveRef = useRef<(() => void) | null>(null);
  const lockedEarlyRef = useRef(false);

  const handleLocked = () => {
    lockedEarlyRef.current = true;
    lockResolveRef.current?.();
    lockResolveRef.current = null;
  };

  useEffect(() => {
    if ("serviceWorker" in navigator && window.isSecureContext) {
      navigator.serviceWorker.register("./sw.js").catch(() => {});
    }

    const cancelled = new AbortController();
    import("./scene/director")
      .then(({ startExperience }) =>
        startExperience({
          canvas: canvas.current!,
          ui: {
            veil: veil.current!,
            nav: nav.current!,
            hero: hero.current!,
            scrollCue: cue.current!,
            gaze: gaze.current!,
            tamper: tamper.current!,
            phone: phone.current!,
            macos: macos.current!,
            final: final.current!,
            labels: labels.current!,
          },
          onSection: setActive,
          waitForLoaderLock: (skipWait) => {
            setSceneReady(true);
            if (skipWait || lockedEarlyRef.current) return Promise.resolve();
            return new Promise<void>((resolve) => {
              lockResolveRef.current = resolve;
            });
          },
          cancelled: cancelled.signal,
        }),
      )
      .then((exp) => {
        if (cancelled.signal.aborted) exp?.dispose();
        else experience.current = exp;
      });
    return () => {
      cancelled.abort();
      experience.current?.dispose();
      experience.current = null;
    };
  }, []);

  return (
    <>
      <canvas ref={canvas} className={styles.gl} aria-hidden="true" />
      <div className={styles.ui}>
        <Loader ref={veil} sceneReady={sceneReady} onLocked={handleLocked} />
        <Nav
          ref={nav}
          active={active}
          onGo={(name) => experience.current?.goToSection(name)}
          onWaitlist={() => experience.current?.goToEnd()}
          onOpenModal={() => setModalView("screenshots")}
        />
        <Hero
          ref={hero}
          cueRef={cue}
          onWaitlist={() => experience.current?.goToEnd()}
          onOpenModal={() => setModalView("screenshots")}
        />
        <Panel ref={gaze} place="right" icon="eye" {...GAZE} />
        <Panel ref={tamper} place="right" icon="bolt" {...TAMPER} />
        <Panel ref={phone} place="left" icon="phone" {...PHONE} />
        <Panel ref={macos} place="left" icon="touchid" {...MACOS} />
        <Labels ref={labels} />
        <Final
          ref={final}
          onOpenScreenshots={() => setModalView("screenshots")}
          onOpenBuild={() => setModalView("build")}
        />
      </div>
      <ShowcaseModal view={modalView} onClose={() => setModalView(null)} onSwitchView={setModalView} />
      <main className={styles.scroll} aria-label="Pupil" />
    </>
  );
}
