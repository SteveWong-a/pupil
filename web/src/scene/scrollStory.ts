import gsap from "gsap";
import { KEYS, TOUCH_ID_KEY } from "./ansiLayout";
import type { CameraRig } from "./cameraRig";
import type { StageState } from "./director";
import { BACKLIGHT } from "./introTimeline";
import type { MacBook } from "./macbook";
import type { PostPipeline } from "./postPipeline";
import type { UiRefs } from "./uiHandles";

export interface GlowState {
  backlight: number;
  press: number;
  wave: number;
  key: number;
  ch1: number;
  ch2: number;
  ch3: number;
  ch4: number;
}

export type ScrollStory = ReturnType<typeof createScrollStory>;

export function createScrollStory({
  mb,
  rig,
  post,
  stage,
  ui,
  signal,
}: {
  mb: MacBook;
  rig: CameraRig;
  post: PostPipeline;
  stage: StageState;
  ui: UiRefs;
  signal: AbortSignal;
}) {
  const { cam } = rig;
  const { fx } = post;
  const hero = KEYS[TOUCH_ID_KEY];
  const heroKey = mb.keys[TOUCH_ID_KEY];
  const kbY = stage.mbPose.y;

  const glow: GlowState = { backlight: BACKLIGHT, press: 0, wave: 0, key: 0, ch1: 0, ch2: 0, ch3: 0, ch4: 0 };
  Object.assign(mb.pose, { lidAngle: 0, magsafeSlide: 0, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0, phoneMode: 0, phonePress: 0, phoneLift: 0 });

  const tl = gsap.timeline({ paused: true, defaults: { ease: "power2.inOut" } });
  tl.set(mb.pose, { lidAngle: 0, magsafeSlide: 0, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0, phoneMode: 0, phonePress: 0, phoneLift: 0 }, 0);

  // CHAPTER 1: Gaze Detection & Instant Screen Blur (settled at t = 2.64 / ?p=0.22)
  tl.to(ui.hero, { autoAlpha: 0, y: -30, filter: "blur(10px)", duration: 0.6, ease: "power1.in" }, 0);
  tl.to(ui.scrollCue, { opacity: 0, duration: 0.3 }, 0);
  tl.to(stage.mbPose, { rx: 0.04, duration: 1.4 }, 0);
  tl.to(stage, { idle: 0.2, hoverKeys: 0, duration: 0.8 }, 0);
  tl.to(
    cam,
    { tx: 0.0, ty: kbY + 10.6, tz: -6.5, az: -0.1, el: 0.14, dist: 54, fov: 30, shiftX: 0.13, shiftY: -0.03, fit: 0.82, parallax: 0.35, duration: 1.7 },
    0,
  );
  tl.to(fx, { bokeh: 0.6, focusRange: 26, duration: 1.4 }, 0);

  tl.set(mb.pose, { screenMode: 1 }, 1.1);
  tl.to(mb.pose, { shieldBlur: 1, duration: 0.7, ease: "power2.out" }, 1.35);
  tl.to(glow, { ch1: 1, duration: 0.45, ease: "power2.out" }, 1.65);
  tl.fromTo(ui.gaze, { autoAlpha: 0, y: 28 }, { autoAlpha: 1, y: 0, duration: 0.55, ease: "power3.out" }, 1.65);

  // CHAPTER 2: Charger Unplug & Lid Tamper Alert (settled at t = 5.52 / ?p=0.46)
  tl.to(ui.gaze, { autoAlpha: 0, y: -20, duration: 0.45, ease: "power1.in" }, 3.4);
  tl.to(glow, { ch1: 0, duration: 0.35 }, 3.4);
  tl.to(
    cam,
    { tx: -7.5, ty: kbY + 5.8, tz: -2.4, az: -0.78, el: 0.22, dist: 58, shiftX: 0.14, shiftY: -0.02, fit: 0.86, duration: 1.5 },
    3.5,
  );
  tl.set(mb.pose, { screenMode: 2, countdown: 15 }, 4.2);
  tl.to(mb.pose, { magsafeSlide: 1, duration: 0.55, ease: "back.out(1.4)" }, 4.25);
  tl.to(mb.pose, { countdown: 0, duration: 0.9, ease: "none" }, 4.25);
  tl.set(mb.pose, { screenMode: 3 }, 5.15);
  tl.to(mb.pose, { lidAngle: 0.36, sirenPulse: 1, duration: 0.65, ease: "power2.inOut" }, 4.55);
  tl.to(glow, { ch2: 1, duration: 0.45, ease: "power2.out" }, 4.85);
  tl.fromTo(ui.tamper, { autoAlpha: 0, y: 28 }, { autoAlpha: 1, y: 0, duration: 0.55, ease: "power3.out" }, 4.85);

  // CHAPTER 3: iPhone 16 Pro Companion Link (settled at t = 8.16 / ?p=0.68)
  tl.to(ui.tamper, { autoAlpha: 0, y: -20, duration: 0.45, ease: "power1.in" }, 6.3);
  tl.to(glow, { ch2: 0, duration: 0.35 }, 6.3);
  tl.to(mb.pose, { lidAngle: 0, magsafeSlide: 0, sirenPulse: 0, duration: 0.8, ease: "power2.inOut" }, 6.4);
  tl.to(mb.pose, { phoneLift: 1, duration: 1.0, ease: "power3.inOut" }, 6.45);
  tl.to(
    cam,
    { tx: 16.2, ty: kbY + 5.8, tz: 4.8, az: 0.12, el: 0.16, dist: 45, shiftX: -0.08, shiftY: -0.02, fit: 0.78, duration: 1.45 },
    6.4,
  );
  tl.set(mb.pose, { phoneMode: 1 }, 6.6);
  tl.to(mb.pose, { phonePress: 0.45, duration: 0.35, ease: "power2.out" }, 7.55);
  tl.set(mb.pose, { screenMode: 4, phoneMode: 2 }, 7.65);
  tl.to(mb.pose, { shieldBlur: 0, duration: 0.4, ease: "power2.out" }, 7.65);
  tl.to(glow, { ch3: 1, duration: 0.45, ease: "power2.out" }, 7.65);
  tl.fromTo(ui.phone, { autoAlpha: 0, y: 28 }, { autoAlpha: 1, y: 0, duration: 0.55, ease: "power3.out" }, 7.65);

  // CHAPTER 4: Seamless macOS UI & Touch ID (settled at t = 10.32 / ?p=0.86)
  tl.to(ui.phone, { autoAlpha: 0, y: -20, duration: 0.45, ease: "power1.in" }, 8.9);
  tl.to(glow, { ch3: 0, duration: 0.35 }, 8.9);
  tl.to(mb.pose, { phoneLift: 0, duration: 0.85, ease: "power2.inOut" }, 8.95);
  tl.set(mb.pose, { phonePress: 0, screenMode: 0 }, 9.1);
  tl.set(mb.pose, { screenMode: 5 }, 9.8);
  tl.to(
    cam,
    { tx: 6.2, ty: kbY + 6.4, tz: -3.2, az: -0.22, el: 0.28, dist: 51, shiftX: 0.04, shiftY: -0.06, fit: 0.78, duration: 1.2 },
    9.0,
  );
  tl.to(glow, { press: 0.055, key: 1.8, backlight: 0.92, duration: 0.45, ease: "power2.out" }, 9.65);
  tl.to(glow, { ch4: 1, duration: 0.45, ease: "power2.out" }, 9.85);
  tl.fromTo(ui.macos, { autoAlpha: 0, y: 28 }, { autoAlpha: 1, y: 0, duration: 0.55, ease: "power3.out" }, 9.85);

  // FINAL WAITLIST CTA (settled at t = 12.00 / ?p=1.00)
  tl.to(ui.macos, { autoAlpha: 0, y: -20, duration: 0.4, ease: "power1.in" }, 10.95);
  tl.to(glow, { ch4: 0, press: 0, key: 0, duration: 0.35 }, 10.95);
  tl.set(mb.pose, { screenMode: 0, phoneMode: 0 }, 11.1);
  tl.to(stage.mbPose, { rx: 0.1, duration: 0.9 }, 11.0);
  tl.to(
    cam,
    { tx: 2.0, ty: kbY + 5.4, tz: 1.6, az: -0.18, el: 0.24, dist: 78, fit: 0.88, shiftX: 0, shiftY: -0.11, parallax: 1, duration: 1.0, ease: "power2.inOut" },
    11.0,
  );
  tl.to(fx, { bokeh: 0.8, focusRange: 20, duration: 1.0 }, 11.0);
  tl.to(stage, { tilt: 1, idle: 1, duration: 1.0 }, 11.0);
  tl.to(glow, { wave: 1, backlight: 1.0, duration: 0.65, ease: "none" }, 11.15);
  tl.fromTo(ui.final, { autoAlpha: 0, y: 30, filter: "blur(10px)" }, { autoAlpha: 1, y: 0, filter: "blur(0px)", duration: 0.45, ease: "power3.out" }, 11.45);

  let target = 0;
  let current = 0;
  const maxScroll = () => document.documentElement.scrollHeight - innerHeight;
  const readScroll = () => {
    const max = maxScroll();
    target = max > 0 ? Math.min(1, Math.max(0, scrollY / max)) : 0;
  };
  addEventListener("scroll", readScroll, { passive: true, signal });
  readScroll();

  const glide = { p: 0, active: false };
  const release = () => {
    if (!glide.active) return;
    gsap.killTweensOf(glide);
    glide.active = false;
  };
  for (const type of ["wheel", "touchstart", "keydown"]) addEventListener(type, release, { passive: true, signal });

  function goTo(p: number) {
    gsap.killTweensOf(glide);
    Object.assign(glide, { p: current, active: true });
    gsap.to(glide, {
      p,
      duration: 0.9 + Math.abs(p - current) * 2.2,
      ease: "power2.inOut",
      onComplete: () => {
        glide.active = false;
      },
    });
    target = p;
    scrollTo({ top: p * maxScroll(), behavior: "instant" });
  }

  function update(dt: number) {
    if (glide.active) current = glide.p;
    else current += (target - current) * (1 - Math.exp(-dt * 5));
    if (Math.abs(target - current) < 1e-5) current = target;
    tl.progress(current);

    const waveR = glow.wave * 40;
    const siren = mb.pose.sirenPulse;
    for (let i = 0; i < KEYS.length; i++) {
      const st = mb.keys[i];
      st.off.set(0, 0, 0);
      st.q.identity();
      st.s = 1;
      st.press = 0;
      const d = Math.hypot(KEYS[i].x - hero.x, KEYS[i].z - hero.z);
      const front = Math.max(0, Math.min(1, (waveR - d) / 4));
      const crest = front * Math.exp(-Math.max(0, waveR - d) / 6);
      const level = glow.backlight + crest * 1.4 + siren * 0.45;
      st.white = level;
      st.orange = level;
    }
    heroKey.press += glow.press;
    heroKey.white += glow.key;
    heroKey.orange += glow.key;
  }

  function pin(p: number) {
    release();
    target = current = p;
    tl.progress(p);
  }

  const isSettled = () => !glide.active && Math.abs(target - current) < 1e-4;

  function dispose() {
    gsap.killTweensOf(glide);
    tl.kill();
  }

  return { tl, update, pin, goTo, isSettled, glow, progress: () => current, dispose };
}
