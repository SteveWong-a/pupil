import gsap from "gsap";
import * as THREE from "three";
import { KEYS, TOUCH_ID_KEY } from "./ansiLayout";
import { createCalloutProjector, createKeyHover } from "./calloutAnchors";
import { createCameraRig } from "./cameraRig";
import { CHAPTER_FEATURES, FEATURE_SHOTS } from "./featureShots";
import { createSceneInteraction } from "./interaction";
import { createIntroTimeline } from "./introTimeline";
import { createMacBook, type FeatureId } from "./macbook";
import { createPasserbyShadows } from "./passerbyShadows";
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
  focusFeature: (id: FeatureId) => void;
  clearFocus: () => void;
  triggerFeatureDemo: (id: FeatureId) => void;
  hoverFeature: (id: FeatureId | null) => void;
  dispose: () => void;
}

export async function startExperience({
  canvas,
  ui,
  onSection,
  onFocusChange,
  waitForLoaderLock,
  cancelled,
}: {
  canvas: HTMLCanvasElement;
  ui: UiRefs;
  onSection: (name: SectionName | null) => void;
  onFocusChange?: (id: FeatureId | null) => void;
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

  const passerby = createPasserbyShadows();
  keyLight.map = passerby.goboTexture;
  mb.setScreenShadowMap(passerby.screenTexture);
  mb.setDeckShadowMap(passerby.deckTexture);

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

  let focusedFeature: FeatureId | null = null;
  let hoveredFeature: FeatureId | null = null;
  const focusAnchor = new THREE.Vector3();
  const focusTargetLive = new THREE.Vector3();
  let focusAnchorSnapped = false;

  const demo = {
    blurMix: 0,
    blurState: false,
    magsafeMix: 0,
    magsafeState: false,
    lidMix: 0,
    lidState: false,
    sirenBurst: 0,
    phoneMix: 0,
    phoneState: false,
    touchPress: 0,
    touchWave: 0,
  };
  let demoTweenCount = 0;

  function resetDemoOverrides() {
    gsap.killTweensOf(demo);
    demo.blurState = false;
    demo.magsafeState = false;
    demo.lidState = false;
    demo.phoneState = false;
    demoTweenCount++;
    gsap.to(demo, {
      blurMix: 0,
      magsafeMix: 0,
      lidMix: 0,
      sirenBurst: 0,
      phoneMix: 0,
      touchPress: 0,
      touchWave: 0,
      duration: 0.45,
      ease: "power2.out",
      onComplete: () => {
        demoTweenCount = Math.max(0, demoTweenCount - 1);
      },
    });
  }

  function computeFeatureAnchor(id: FeatureId, out: THREE.Vector3) {
    mb.featurePoint(id, out);
    const off = FEATURE_SHOTS[id].targetOffset;
    if (off) out.x += off[0];
    if (off) out.y += off[1];
    if (off) out.z += off[2];
    return out;
  }

  function focusFeature(id: FeatureId) {
    skipIntro();
    if (focusedFeature === id) {
      clearFocus();
      return;
    }
    const spec = FEATURE_SHOTS[id];
    const currentSec = scroll ? sectionAt(scroll.progress()) : "overview";
    if (currentSec !== spec.section) {
      scroll!.goTo(SECTIONS[spec.section]);
    }

    const wasFocused = focusedFeature !== null && rig.focus.mix > 0.25;
    focusedFeature = id;
    onFocusChange?.(id);
    resetDemoOverrides();
    rig.resetOrbit();

    computeFeatureAnchor(id, focusAnchor);
    gsap.killTweensOf(rig.focus);

    if (!wasFocused) {
      rig.focus.tx = focusAnchor.x;
      rig.focus.ty = focusAnchor.y;
      rig.focus.tz = focusAnchor.z;
      rig.focus.az = spec.az;
      rig.focus.el = spec.el;
      rig.focus.dist = spec.dist;
      rig.focus.fov = spec.fov;
      rig.focus.shiftX = spec.shiftX ?? 0;
      rig.focus.shiftY = spec.shiftY ?? 0;
      rig.focus.bokeh = spec.bokeh;
      rig.focus.focusRange = spec.focusRange;
      focusAnchorSnapped = true;
      gsap.to(rig.focus, {
        mix: 1,
        duration: 0.85,
        ease: "power3.inOut",
      });
    } else {
      focusAnchorSnapped = false;
      gsap.to(rig.focus, {
        mix: 1,
        az: spec.az,
        el: spec.el,
        dist: spec.dist,
        fov: spec.fov,
        shiftX: spec.shiftX ?? 0,
        shiftY: spec.shiftY ?? 0,
        bokeh: spec.bokeh,
        focusRange: spec.focusRange,
        duration: 0.72,
        ease: "power3.inOut",
      });
    }
  }

  function clearFocus() {
    if (focusedFeature === null && rig.focus.mix <= 0.001) return;
    focusedFeature = null;
    onFocusChange?.(null);
    resetDemoOverrides();
    rig.resetOrbit();
    gsap.killTweensOf(rig.focus);
    gsap.to(rig.focus, {
      mix: 0,
      duration: 0.65,
      ease: "power2.inOut",
    });
  }

  function triggerFeatureDemo(id: FeatureId) {
    lastInput = performance.now();
    if (id.startsWith("gaze-")) {
      demo.blurState = !demo.blurState;
      demoTweenCount++;
      gsap.to(demo, {
        blurMix: demo.blurState ? 1 : 0,
        duration: 0.45,
        ease: "power2.out",
        onComplete: () => {
          demoTweenCount = Math.max(0, demoTweenCount - 1);
        },
      });
    } else if (id === "tamper-magsafe") {
      demo.magsafeState = !demo.magsafeState;
      demoTweenCount++;
      gsap.to(demo, {
        magsafeMix: demo.magsafeState ? 1 : 0,
        duration: 0.5,
        ease: "back.out(1.4)",
        onComplete: () => {
          demoTweenCount = Math.max(0, demoTweenCount - 1);
        },
      });
    } else if (id === "tamper-hinge") {
      demo.lidState = !demo.lidState;
      demoTweenCount++;
      gsap.to(demo, {
        lidMix: demo.lidState ? 1 : 0,
        duration: 0.65,
        ease: "power2.inOut",
        onComplete: () => {
          demoTweenCount = Math.max(0, demoTweenCount - 1);
        },
      });
    } else if (id === "tamper-siren") {
      demoTweenCount++;
      gsap.killTweensOf(demo, "sirenBurst");
      gsap.fromTo(
        demo,
        { sirenBurst: 1 },
        {
          sirenBurst: 0,
          duration: 1.2,
          ease: "power2.out",
          onComplete: () => {
            demoTweenCount = Math.max(0, demoTweenCount - 1);
          },
        },
      );
    } else if (id.startsWith("phone-")) {
      demo.phoneState = !demo.phoneState;
      demoTweenCount++;
      gsap.to(demo, {
        phoneMix: demo.phoneState ? 1 : 0,
        duration: 0.4,
        ease: "power2.out",
        onComplete: () => {
          demoTweenCount = Math.max(0, demoTweenCount - 1);
        },
      });
    } else if (id === "macos-touchid") {
      demoTweenCount++;
      gsap.killTweensOf(demo, "touchPress,touchWave");
      gsap.fromTo(
        demo,
        { touchPress: 0.08, touchWave: 0.01 },
        {
          touchPress: 0,
          touchWave: 1,
          duration: 0.85,
          ease: "power2.out",
          onComplete: () => {
            demo.touchWave = 0;
            demoTweenCount = Math.max(0, demoTweenCount - 1);
          },
        },
      );
    }
  }

  function hoverFeature(id: FeatureId | null) {
    hoveredFeature = id;
    lastInput = performance.now();
  }

  createSceneInteraction({
    canvas,
    camera,
    mb,
    rig,
    signal,
    isReady: () => scroll !== null,
    getFocused: () => focusedFeature,
    onFocusFeature: focusFeature,
    onTriggerDemo: triggerFeatureDemo,
    onClearFocus: clearFocus,
  });

  function goToSection(name: string) {
    if (!isSection(name)) return;
    clearFocus();
    skipIntro();
    scroll!.goTo(SECTIONS[name]);
    history.replaceState(null, "", name === "overview" ? location.pathname : `#${name}`);
  }

  function goToEnd() {
    clearFocus();
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
  addEventListener(
    "wheel",
    (e) => {
      if (e.deltaY > 30) impatient();
      if (Math.abs(e.deltaY) > 24) {
        if (focusedFeature !== null) clearFocus();
        else rig.resetOrbit();
      }
    },
    { passive: true, signal },
  );
  addEventListener(
    "touchmove",
    () => {
      impatient();
      if (focusedFeature !== null && !rig.orbit.dragging) clearFocus();
    },
    { passive: true, signal },
  );
  addEventListener(
    "keydown",
    (e) => {
      if (e.key === "Escape" && focusedFeature !== null) {
        clearFocus();
        return;
      }
      if (["ArrowDown", "PageDown", " ", "Escape"].includes(e.key)) impatient();
    },
    { signal },
  );

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

    const overviewWeight = scroll
      ? 1 - THREE.MathUtils.smoothstep(p, 0.05, 0.13)
      : THREE.MathUtils.smoothstep(intro.tl.time(), 2.35, 3.15);
    const gazeWeight = scroll ? scroll.glow.gazeShadow : 0;
    passerby.update(dt, t, {
      overviewWeight,
      gazeWeight,
      gazeRetreat: demo.blurState,
      frozen: FROZEN,
    });

    if (gazeWeight > 0.02 && Math.round(mb.pose.screenMode) <= 1) {
      const gb = passerby.getGazeBlurTrigger();
      mb.pose.shieldBlur = gb;
      mb.pose.screenMode = gb > 0.12 ? 1 : 0;
    }

    // Apply live hardware micro-demo overrides cleanly on top of scrollStory pose
    if (demo.blurMix > 0.001) {
      mb.pose.shieldBlur = THREE.MathUtils.lerp(mb.pose.shieldBlur, 0, demo.blurMix);
      if (demo.blurMix > 0.5) mb.pose.screenMode = 0;
    }
    if (demo.magsafeMix > 0.001) {
      mb.pose.magsafeSlide = THREE.MathUtils.lerp(mb.pose.magsafeSlide, 0, demo.magsafeMix);
    }
    if (demo.lidMix > 0.001) {
      mb.pose.lidAngle = THREE.MathUtils.lerp(mb.pose.lidAngle, 0.04, demo.lidMix);
    }
    if (demo.sirenBurst > 0.001) {
      mb.pose.sirenPulse = Math.min(1, mb.pose.sirenPulse + demo.sirenBurst * 0.85);
      const pulseGlow = demo.sirenBurst * 0.9;
      for (let i = 0; i < KEYS.length; i++) {
        mb.keys[i].orange += pulseGlow;
      }
    }
    if (demo.phoneMix > 0.001) {
      mb.pose.phonePress = THREE.MathUtils.lerp(mb.pose.phonePress, 0, demo.phoneMix);
      if (demo.phoneMix > 0.5) {
        mb.pose.phoneMode = 1;
        mb.pose.screenMode = 3;
      }
    }
    if (demo.touchPress > 0.001 || demo.touchWave > 0.001) {
      const heroKey = mb.keys[TOUCH_ID_KEY];
      heroKey.press += demo.touchPress;
      heroKey.white += demo.touchPress * 22;
      heroKey.orange += demo.touchPress * 22;
      if (demo.touchWave > 0.001) {
        const waveR = demo.touchWave * 36;
        for (let i = 0; i < KEYS.length; i++) {
          const d = Math.hypot(KEYS[i].x - touchIdKey.x, KEYS[i].z - touchIdKey.z);
          const front = Math.max(0, Math.min(1, (waveR - d) / 3.5));
          const crest = front * Math.exp(-Math.max(0, waveR - d) / 5.5);
          mb.keys[i].white += crest * 1.6;
          mb.keys[i].orange += crest * 1.6;
        }
      }
    }

    const idle = stage.idle * (1 - rig.focus.mix * 0.85);
    springLean(dt);
    const tilt = stage.tilt * (1 - rig.focus.mix);
    mb.root.position.y = stage.mbPose.y + Math.sin(t * 0.9) * 0.16 * idle - lean.y * 0.3 * tilt;
    mb.root.rotation.set(
      stage.mbPose.rx + Math.sin(t * 0.7 + 1) * 0.012 * idle + lean.y * 0.07 * tilt,
      stage.mbPose.ry + Math.sin(t * 0.45) * 0.02 * idle + lean.x * 0.15 * tilt,
      stage.mbPose.rz + Math.sin(t * 0.55) * 0.012 * idle - lean.x * 0.03 * tilt,
    );
    mb.root.updateMatrixWorld();
    const keyHoverWeight = Math.max(stage.hoverKeys, focusedFeature === "macos-touchid" ? rig.focus.mix : 0);
    hover.update(dt, keyHoverWeight);
    mb.update();

    if (focusedFeature !== null) {
      computeFeatureAnchor(focusedFeature, focusTargetLive);
      if (focusAnchorSnapped) {
        rig.focus.tx = focusTargetLive.x;
        rig.focus.ty = focusTargetLive.y;
        rig.focus.tz = focusTargetLive.z;
      } else {
        const fk = 1 - Math.exp(-dt * 11);
        rig.focus.tx += (focusTargetLive.x - rig.focus.tx) * fk;
        rig.focus.ty += (focusTargetLive.y - rig.focus.ty) * fk;
        rig.focus.tz += (focusTargetLive.z - rig.focus.tz) * fk;
        if (Math.hypot(focusTargetLive.x - rig.focus.tx, focusTargetLive.y - rig.focus.ty, focusTargetLive.z - rig.focus.tz) < 0.02) {
          focusAnchorSnapped = true;
        }
      }
    }

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

    const baseBokeh = post.fx.bokeh;
    const baseRange = post.fx.focusRange;
    const fm = rig.focus.mix;
    if (fm > 0.001) {
      post.fx.bokeh = THREE.MathUtils.lerp(baseBokeh, rig.focus.bokeh, fm);
      post.fx.focusRange = THREE.MathUtils.lerp(baseRange, rig.focus.focusRange, fm);
    }
    post.focusTarget.lerpVectors(rig.target, mb.root.localToWorld(focusTmp.copy(keyFocus)), post.fx.focusRow * (1 - fm));
    post.apply();
    post.fx.bokeh = baseBokeh;
    post.fx.focusRange = baseRange;

    callouts.update(W, H, scroll?.glow, focusedFeature, hoveredFeature);
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
    const resting =
      scroll !== null &&
      scroll.isSettled() &&
      rig.isInteractiveSettled() &&
      demoTweenCount === 0 &&
      !passerby.isActive() &&
      scroll.progress() >= 0.14 &&
      now - lastInput > 1500;
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
      passerby.dispose();
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
      if (focusedFeature !== null) {
        const spec = FEATURE_SHOTS[focusedFeature];
        const group = CHAPTER_FEATURES[spec.chapter];
        const idx = group.findIndex((f) => f.id === focusedFeature);
        const nextIdx = (idx + (e.key === "ArrowRight" ? 1 : -1) + group.length) % group.length;
        focusFeature(group[nextIdx].id);
        return;
      }
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
    focusFeature,
    clearFocus,
    triggerFeatureDemo,
    hoverFeature,
    dispose() {
      abort.abort();
      gsap.killTweensOf(rig.focus);
      gsap.killTweensOf(demo);
      renderer.setAnimationLoop(null);
      intro.tl.kill();
      (scroll as ScrollStory | null)?.dispose();
      post.composer.dispose();
      passerby.dispose();
      mb.dispose();
      env.dispose();
      deskMat.dispose();
      desk.geometry.dispose();
      renderer.dispose();
    },
  };
}
