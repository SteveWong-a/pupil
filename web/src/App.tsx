import { useEffect, useRef, useState } from "react";
import type { Experience } from "./lib/stage";
import type { SectionName } from "./lib/ui";
import { Nav } from "./components/Nav";
import { Hero } from "./components/Hero";
import { Panel } from "./components/Panel";
import { Labels } from "./components/Labels";
import { Final } from "./components/Final";
import { ShowcaseModal, type ModalView } from "./components/ShowcaseModal";
import styles from "./App.module.css";

const INSIDE = {
  eyebrow: "Inside Pupil",
  title: (
    <>
      Seven layers. <br />
      Zero cloud.
    </>
  ),
};

const VIBE_ROW = {
  eyebrow: "Four core tripwires",
  title: (
    <>
      Built for libraries, <br />
      cafes <em>&amp; solo work.</em>
    </>
  ),
};

const ACCEPT = {
  eyebrow: "Instant owner disarm",
  title: (
    <>
      Locked to thieves. <br />
      Effortless <em>for you.</em>
    </>
  ),
  body: "Disarm in under a second with Touch ID, PIN, or iPhone proximity, with a 15-second grace countdown and progressive library-safe siren.",
};

export function App() {
  const canvas = useRef<HTMLCanvasElement>(null);
  const veil = useRef<HTMLDivElement>(null);
  const nav = useRef<HTMLElement>(null);
  const hero = useRef<HTMLElement>(null);
  const cue = useRef<HTMLSpanElement>(null);
  const inside = useRef<HTMLElement>(null);
  const vibe = useRef<HTMLElement>(null);
  const key = useRef<HTMLElement>(null);
  const final = useRef<HTMLElement>(null);
  const labels = useRef<HTMLDivElement>(null);
  const experience = useRef<Experience | null>(null);
  const [active, setActive] = useState<SectionName | null>("overview");
  const [modalView, setModalView] = useState<ModalView | null>(null);

  useEffect(() => {
    if ("serviceWorker" in navigator && window.isSecureContext) {
      navigator.serviceWorker.register("./sw.js").catch(() => {});
    }

    const cancelled = new AbortController();
    import("./lib/stage")
      .then(({ startExperience }) =>
        startExperience({
          canvas: canvas.current!,
          ui: {
            veil: veil.current!,
            nav: nav.current!,
            hero: hero.current!,
            scrollCue: cue.current!,
            inside: inside.current!,
            vibeCopy: vibe.current!,
            keyCopy: key.current!,
            final: final.current!,
            labels: labels.current!,
          },
          onSection: setActive,
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
        <div ref={veil} className={styles.veil} />
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
        <Panel ref={inside} place="inside" {...INSIDE} />
        <Panel ref={vibe} place="vibe" {...VIBE_ROW} />
        <Labels ref={labels} />
        <Panel ref={key} place="key" {...ACCEPT} />
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
