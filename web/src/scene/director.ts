import * as THREE from "three";
import { KEYS, TOUCH_ID_KEY } from "./ansiLayout";
import { createCalloutProjector, createKeyHover } from "./calloutAnchors";
import { createCameraRig } from "./cameraRig";
import { createIntroTimeline } from "./introTimeline";
import { createMacBook } from "./macbook";
import { createPostPipeline } from "./postPipeline";
import { createStudioEnvironment, loadSceneAssets } from "./proceduralMaps";
import { createScrollStory, type ScrollStory } from "./scrollStory";
import { SECTIONS, isSection, sectionAt, type SectionName, type UiRefs } from "./uiHandles";

export interface StageState {
  desk: number;
  idle: number;
  shadow: number;
  tilt: number;
  hoverKeys: number;
  light: number;
  rim: number;
  rake: number;
  mbPose: { y: number; rx: number; ry: number; rz: number };
}

const FONTS = ['400 1em "Instrument Sans"', '500 1em "Instrument Sans"', '600 1em "Instrument Sans"', '700 1em "Newsreader"'];

export interface Experience {
  goToSection: (name: string) => void;
  goToEnd: () => void;
  dispose: () => void;
}

export async function startExperience({
  canvas,
  ui,
  onSection,
  waitForLoaderLock,
  cancelled,
}: {
  canvas: HTMLCanvasElement;
  ui: UiRefs;
  onSection: (name: SectionName | null) => void;
  waitForLoaderLock?: (skipWait: boolean) => Promise<void>;
  cancelled: AbortSignal;
}): Promise<Experience | null> {
  await Promise.all(FONTS.map((f) => document.fonts.load(f)));
  const assets = await loadSceneAssets();
  if (cancelled.aborted) {
    assets.legend.texture.dispose();
    assets.padTexture.dispose();
    assets.surface.metalNormal.dispose();
    assets.surface.capNormal.dispose();
    assets.surface.smudge.dispose();
    assets.surface.capSmudge.dispose();
    return null;
  }

  const abort = new AbortController();
  const { signal } = abort;

  history.scrollRestoration = "manual";
  scrollTo(0, 0);

  const params = new URLSearchParams(location.search);
  const FROZEN = params.has("t") || params.has("p");

  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: false,
    stencil: false,
    depth: false,
    powerPreference: "default",
  });
  const DPR_CAP = Math.min(devicePixelRatio, 1.25);
  let dprScale = 1;
  renderer.setPixelRatio(DPR_CAP);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x000000);
  const env = createStudioEnvironment(renderer);
  scene.environment = env;
  scene.environmentIntensity = 0.45;

  const camera = new THREE.PerspectiveCamera(32, innerWidth / innerHeight, 0.3, 400);

  const mb = createMacBook(assets);
  scene.add(mb.root);

  const deskMat = new THREE.MeshLambertMaterial({ color: 0x1c1815 });
  const deskColor = deskMat.color.clone();
  const desk = new THREE.Mesh(new THREE.PlaneGeometry(400, 400).rotateX(-Math.PI / 2), deskMat);
  desk.receiveShadow = true;
  scene.add(desk);

  const keyLight = new THREE.SpotLight(0xfff0e2, 1.9, 0, 0.42, 1, 0);
  keyLight.position.set(-8, 36, 20);
  keyLight.castShadow = true;
  keyLight.shadow.mapSize.set(1024, 1024);
  keyLight.shadow.camera.near = 15;
  keyLight.shadow.camera.far = 90;
  keyLight.shadow.bias = -0.0002;
  keyLight.shadow.normalBias = 0.02;
  keyLight.shadow.radius = 4;
  scene.add(keyLight, keyLight.target);

  const rim = new THREE.DirectionalLight(0xffffff, 0.9);
  const RIM_HOME = new THREE.Vector3(5, 10, -26);
  const RAKE_DIR = new THREE.Vector3(14, 1.7, 8);
  rim.position.copy(RIM_HOME);
  scene.add(rim);

  const stage: StageState = {
    desk: 0,
    idle: 0,
    shadow: 1,
    tilt: 0,
    hoverKeys: 0,
    light: 1,
    rim: 1,
    rake: 0,
    mbPose: { y: 0, rx: 0, ry: 0, rz: 0 },
  };

  const touchIdKey = KEYS[TOUCH_ID_KEY];
  const keyFocus = new THREE.Vector3(touchIdKey.x, 2.0, touchIdKey.z);
  const focusTmp = new THREE.Vector3();

  const rig = createCameraRig(signal);
  const lean = { x: 0, y: 0, vx: 0, vy: 0 };
  function springLean(dt: number) {
    const h = Math.min(dt, 1 / 30);
    lean.vx += ((rig.pointer.x - lean.x) * 38 - lean.vx * 8.5) * h;
    lean.vy += ((rig.pointer.y - lean.y) * 38 - lean.vy * 8.5) * h;
    lean.x += lean.vx * h;
    lean.y += lean.vy * h;
  }

  const post = createPostPipeline(renderer, scene, camera);
  const callouts = createCalloutProjector({ mb, camera, root: ui.labels });
  const hover = createKeyHover({ mb, camera, signal });

  let W = 0;
  let H = 0;
  function resize() {
    W = innerWidth;
    H = innerHeight;
    renderer.setSize(W, H, false);
    post.composer.setSize(W, H, false);
  }
  addEventListener("resize", resize, { signal });
  resize();

  let scroll: ScrollStory | null = null;
  const intro = createIntroTimeline({ mb, rig, post, stage, ui, onDone: finishIntro });

  function finishIntro() {
    if (scroll) return;
    intro.tl.pause();
    intro.update();
    document.body.classList.remove("is-locked");
    scroll = createScrollStory({ mb, rig, post, stage, ui, signal });
  }

  function skipIntro() {
    if (scroll) return;
    intro.tl.seek(intro.end);
    finishIntro();
  }

  function goToSection(name: string) {
    if (!isSection(name)) return;
    skipIntro();
    scroll!.goTo(SECTIONS[name]);
    history.replaceState(null, "", name === "overview" ? location.pathname : `#${name}`);
  }

  function goToEnd() {
    skipIntro();
    scroll!.goTo(1);
    history.replaceState(null, "", "#waitlist");
  }

  let activeSection: SectionName | null | undefined;
  function markSection() {
    const name = scroll ? sectionAt(scroll.progress()) : "overview";
    if (name === activeSection) return;
    activeSection = name;
    onSection(name);
  }

  const impatient = () => intro.tl.time() > 1 && skipIntro();
  addEventListener("wheel", (e) => e.deltaY > 30 && impatient(), { passive: true, signal });
  addEventListener("touchmove", impatient, { passive: true, signal });
  addEventListener("keydown", (e) => ["ArrowDown", "PageDown", " ", "Escape"].includes(e.key) && impatient(), { signal });

  let last = performance.now();

  function frame(now = performance.now()) {
    const dt = FROZEN ? 0 : Math.min(0.1, Math.max(0, (now - last) / 1000));
    last = now;
    const t = FROZEN ? 0 : now / 1000;

    if (scroll) scroll.update(dt);
    else {
      intro.advance(dt);
      intro.update();
    }
    markSection();
    const p = scroll ? scroll.progress() : 0;
    document.documentElement.style.setProperty("--scroll-progress", p.toFixed(4));

    const idle = stage.idle;
    springLean(dt);
    const tilt = stage.tilt;
    mb.root.position.y = stage.mbPose.y + Math.sin(t * 0.9) * 0.16 * idle - lean.y * 0.3 * tilt;
    mb.root.rotation.set(
      stage.mbPose.rx + Math.sin(t * 0.7 + 1) * 0.012 * idle + lean.y * 0.07 * tilt,
      stage.mbPose.ry + Math.sin(t * 0.45) * 0.02 * idle + lean.x * 0.15 * tilt,
      stage.mbPose.rz + Math.sin(t * 0.55) * 0.012 * idle - lean.x * 0.03 * tilt,
    );
    mb.root.updateMatrixWorld();
    hover.update(dt, stage.hoverKeys);
    mb.update();

    deskMat.color.copy(deskColor).multiplyScalar(stage.desk);
    desk.visible = stage.desk > 0.002;
    keyLight.target.position.set(0, mb.root.position.y, 0);
    keyLight.shadow.intensity = stage.shadow;
    keyLight.intensity = 1.9 * stage.light;
    rim.position.lerpVectors(RIM_HOME, RAKE_DIR, stage.rake);
    rim.intensity = THREE.MathUtils.lerp(0.9 * stage.light * stage.rim, 0.9, stage.rake);
    scene.environmentIntensity = 0.45 * (0.25 + 0.75 * stage.light);

    rig.apply(camera, W, H, dt);
    camera.updateMatrixWorld();
    post.focusTarget.lerpVectors(rig.target, mb.root.localToWorld(focusTmp.copy(keyFocus)), post.fx.focusRow);
    post.apply();

    callouts.update(W, H, scroll?.glow);
    mb.renderGlow(renderer, scene);
    post.composer.render(dt);
  }

  renderer.compile(scene, camera);

  let slowFor = 0;
  let fastFor = 0;
  function adaptResolution(interval: number) {
    if (interval > 1 / 40) slowFor += interval;
    else slowFor = Math.max(0, slowFor - interval * 0.5);
    if (interval < 1 / 57) fastFor += interval;
    else fastFor = 0;
    let next = dprScale;
    if (slowFor > 1) next = Math.max(0.8 / DPR_CAP, dprScale - 0.12);
    else if (fastFor > 4) next = Math.min(1, dprScale + 0.06);
    if (next !== dprScale) {
      dprScale = next;
      slowFor = fastFor = 0;
      renderer.setPixelRatio(DPR_CAP * dprScale);
      post.composer.setSize(W, H, false);
    }
  }

  let lastInput = performance.now();
  for (const type of ["pointermove", "pointerdown", "wheel", "scroll", "keydown", "touchstart"]) {
    addEventListener(type, () => (lastInput = performance.now()), { passive: true, signal });
  }
  let tick = 0;
  let lastLoop = 0;
  function loop(now: number) {
    const resting = scroll !== null && scroll.isSettled() && now - lastInput > 1500;
    if (resting && tick++ % 2) return;
    if (!resting && lastLoop && scroll && !FROZEN) adaptResolution((now - lastLoop) / 1000);
    lastLoop = resting ? 0 : now;
    frame(now);
  }

  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const hash = location.hash.slice(1);
  const directReveal =
    params.has("t") ||
    params.has("p") ||
    (isSection(hash) && hash !== "overview") ||
    hash === "waitlist" ||
    reduced;

  if (waitForLoaderLock) {
    await waitForLoaderLock(directReveal);
    if (cancelled.aborted) {
      abort.abort();
      intro.tl.kill();
      post.composer.dispose();
      mb.dispose();
      env.dispose();
      deskMat.dispose();
      desk.geometry.dispose();
      renderer.dispose();
      return null;
    }
  }

  renderer.setAnimationLoop(loop);

  if (params.has("t")) {
    intro.tl.seek(Number(params.get("t")));
  } else if (params.has("p")) {
    skipIntro();
    scroll!.pin(Number(params.get("p")));
  } else if (isSection(hash) && hash !== "overview") {
    skipIntro();
    const p = SECTIONS[hash];
    scrollTo({ top: p * (document.documentElement.scrollHeight - innerHeight), behavior: "instant" });
    scroll!.pin(p);
  } else if (hash === "waitlist") {
    skipIntro();
    scrollTo({ top: document.documentElement.scrollHeight - innerHeight, behavior: "instant" });
    scroll!.pin(1);
  } else if (reduced) {
    skipIntro();
  } else {
    intro.play();
  }

  const chapterOrder: (SectionName | "waitlist")[] = ["overview", "gaze", "tamper", "phone", "macos", "waitlist"];
  addEventListener(
    "keydown",
    (e) => {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
      const tag = (document.activeElement as HTMLElement | null)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || document.querySelector("[role='dialog']")) return;
      const cur = scroll ? (sectionAt(scroll.progress()) ?? "waitlist") : "overview";
      const idx = chapterOrder.indexOf(cur);
      const next = chapterOrder[Math.min(chapterOrder.length - 1, Math.max(0, idx + (e.key === "ArrowRight" ? 1 : -1)))];
      if (next === "waitlist") goToEnd();
      else goToSection(next);
    },
    { signal },
  );

  return {
    goToSection,
    goToEnd,
    dispose() {
      abort.abort();
      renderer.setAnimationLoop(null);
      intro.tl.kill();
      (scroll as ScrollStory | null)?.dispose();
      post.composer.dispose();
      mb.dispose();
      env.dispose();
      deskMat.dispose();
      desk.geometry.dispose();
      renderer.dispose();
    },
  };
}
