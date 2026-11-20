import { useEffect, useRef, useState } from "react";
import type { Experience } from "./scene/director";
import type { FeatureId } from "./scene/macbook";
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
  eyebrow: "01 · Gaze Blur",
  title: (
    <>
      Someone looks. <br />
      <em>Screen blurs.</em>
    </>
  ),
  body: "Pupil notices eyes on your screen and frosts it before a line can be read. It clears the moment they look away.",
};

const TAMPER = {
  eyebrow: "02 · Tamper Alert",
  title: (
    <>
      Unplugged or grabbed. <br />
      <em>Alarm sounds.</em>
    </>
  ),
  body: "Pull the charger, lift the laptop, or close the lid and Pupil counts down, then sounds a siren until you disarm it with Touch ID or your PIN.",
};

const PHONE = {
  eyebrow: "03 · iPhone Alerts",
  title: (
    <>
      Alerted on your iPhone. <br />
      <em>Disarmed from afar.</em>
    </>
  ),
  body: "Get a lock-screen alert with a snapshot on any iPhone, and disarm with one tap. Walk away and Pupil arms itself.",
};

const MACOS = {
  eyebrow: "04 · Menu Bar & Touch ID",
  title: (
    <>
      Built into the notch. <br />
      <em>Unlocked by Touch ID.</em>
    </>
  ),
  body: "Pupil lives in your menu bar and notch. Disarm in under a second with the Touch ID on your MacBook.",
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
  const [focusedFeature, setFocusedFeature] = useState<FeatureId | null>(null);
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
          onFocusChange: setFocusedFeature,
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

  const handleFocusFeature = (id: FeatureId) => experience.current?.focusFeature(id);

  return (
    <>
      <canvas ref={canvas} className={styles.gl} aria-label="Interactive 3D MacBook Pro and iPhone showcase" />
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
        <Panel ref={gaze} place="right" chapter="ch1" icon="eye" focused={focusedFeature} onFocusFeature={handleFocusFeature} {...GAZE} />
        <Panel ref={tamper} place="right" chapter="ch2" icon="bolt" focused={focusedFeature} onFocusFeature={handleFocusFeature} {...TAMPER} />
        <Panel ref={phone} place="left" chapter="ch3" icon="phone" focused={focusedFeature} onFocusFeature={handleFocusFeature} {...PHONE} />
        <Panel ref={macos} place="left" chapter="ch4" icon="touchid" focused={focusedFeature} onFocusFeature={handleFocusFeature} {...MACOS} />
        <Labels
          ref={labels}
          focused={focusedFeature}
          onFocus={handleFocusFeature}
          onHover={(id) => experience.current?.hoverFeature(id)}
        />
      </div>
      <ShowcaseModal view={modalView} onClose={() => setModalView(null)} onSwitchView={setModalView} />
      <main data-scroll-track className={styles.scroll} aria-label="Pupil" />
      <Final
        ref={final}
        onOpenScreenshots={() => setModalView("screenshots")}
        onOpenBuild={() => setModalView("build")}
      />
    </>
  );
}
