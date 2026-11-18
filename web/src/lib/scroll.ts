import gsap from "gsap";
import { KEYS, VIBE, ACCEPT_INDEX } from "./layout";
import { LAYER_ORDER, type Keyboard } from "./keyboard";
import { BACKLIGHT } from "./preloader";
import type { Rig } from "./rig";
import type { Post } from "./post";
import type { Stage } from "./stage";
import type { UiRefs } from "./ui";

// Scroll is mapped onto one paused timeline 12 units long. The page only
// supplies a progress value; the render loop eases toward it, so the same
// timeline can be pinned to any frame.
//
//   0    – 1.6   flatten the floating keyboard, swing round to a three-quarter view
//   0.6  – 3.8   split vertically into seven layers, labels arrive
//   3.5  – 4.9   hold, slow orbit
//   4.9  – 6.7   layers close up while the camera settles on the vibe row
//   6.75 – 8.45  prompt, talk, reject, accept light up in turn
//   8.5  – 10.7  zoom onto accept; it splits into cap / switch / spring / light
//   10.9 – 12    accept closes, presses, and the glow floods out from it
const smooth = (a: number, b: number, t: number) => {
  const x = Math.min(1, Math.max(0, (t - a) / (b - a)));
  return x * x * (3 - 2 * x);
};

// how far the Touch ID key's parts rise when it comes apart
export const SPLIT = { cap: 2.95, switch: 1.9, spring: 0.85 };

export interface Glow {
  backlight: number;
  vibe: number;
  step: number; // which vibe key is showing off (0–3), fractional in between
  press: number; // the accept press at the end
  wave: number;
  key: number;
  labels: number;
  partLabels: number;
}

export type Scroll = ReturnType<typeof createScroll>;

export function createScroll({ kb, rig, post, stage, ui, signal }: { kb: Keyboard; rig: Rig; post: Post; stage: Stage; ui: UiRefs; signal: AbortSignal }) {
  const { cam } = rig;
  const { fx } = post;
  const hero = KEYS[ACCEPT_INDEX];
  const heroKey = kb.keys[ACCEPT_INDEX];
  const kbY = stage.kbPose.y;

  const glow: Glow = { backlight: BACKLIGHT, vibe: 0.9, step: -1, press: 0, wave: 0, key: 0, labels: 0, partLabels: 0 };
  stage.focusOverride = null;
  Object.assign(kb.pose, { lidAngle: 0, magsafeSlide: 0, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0 });

  const tl = gsap.timeline({ paused: true, defaults: { ease: "power2.inOut" } });
  tl.set(kb.pose, { lidAngle: 0, magsafeSlide: 0, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0 }, 0);

  // flatten + frame the 7-layer MacBook Pro stack
  tl.to(ui.hero, { autoAlpha: 0, y: -30, filter: "blur(10px)", duration: 0.7, ease: "power1.in" }, 0);
  tl.to(ui.scrollCue, { opacity: 0, duration: 0.3 }, 0);
  tl.to(stage.kbPose, { rx: 0, duration: 1.4 }, 0);
  tl.to(stage, { idle: 0.25, duration: 1.2 }, 0);
  tl.to(stage, { hoverKeys: 0, duration: 0.35 }, 0);
  tl.to(cam, { tx: 1.4, ty: kbY + 7.2, tz: 2.5, az: -0.44, el: 0.24, dist: 108, fov: 30, shiftX: -0.04, shiftY: -0.02, parallax: 0.5, duration: 1.6 }, 0);
  tl.to(stage, { shadow: 0.3, duration: 1.4 }, 0.7);
  tl.to(fx, { bokeh: 0.35, focusRange: 45, duration: 1.4 }, 0);

  // 7-layer teardown split (100% exploded + labels opaque by t = 2.45 / p = 0.20)
  LAYER_ORDER.forEach((name, i) => {
    tl.to(kb.explode, { [name]: 1, duration: 1.5, ease: "power3.inOut" }, 0.35 + i * 0.08);
  });
  tl.to(glow, { backlight: 1.05, duration: 1.4 }, 0.9);
  tl.to(glow, { labels: 1, duration: 0.01 }, 1.6);
  tl.fromTo(ui.inside, { autoAlpha: 0, y: 30 }, { autoAlpha: 1, y: 0, duration: 0.7, ease: "power3.out" }, 1.7);

  // hold + slow orbit
  tl.to(cam, { az: -0.26, el: 0.22, duration: 1.2, ease: "sine.inOut" }, 3.5);

  // reassemble & 4-stage robbery defense sequence
  tl.to(ui.inside, { autoAlpha: 0, y: -20, duration: 0.5, ease: "power1.in" }, 4.65);
  tl.to(glow, { labels: 0, duration: 0.01 }, 4.75);
  [...LAYER_ORDER].reverse().forEach((name, i) => {
    tl.to(kb.explode, { [name]: 0, duration: 1.2, ease: "power3.inOut" }, 4.85 + i * 0.05);
  });
  tl.to(glow, { backlight: 0.14, duration: 1.2 }, 5.0);
  tl.to(stage, { shadow: 1, duration: 1.1 }, 5.0);
  tl.to(stage, { idle: 0, duration: 0.9 }, 4.9);
  tl.to(cam, { tx: -1.4, ty: kbY + 6.8, tz: 1.8, az: -0.28, el: 0.22, dist: 72, shiftX: 0.12, shiftY: -0.04, fit: 0.85, parallax: 0.35, duration: 1.5, ease: "power3.inOut" }, 4.85);
  tl.to(fx, { bokeh: 0.8, focusRange: 28, duration: 1.4 }, 4.9);
  tl.fromTo(ui.vibeCopy, { autoAlpha: 0, y: 30 }, { autoAlpha: 1, y: 0, duration: 0.5, ease: "power3.out" }, 6.2);
  tl.fromTo(glow, { step: -0.6 }, { step: 3.6, duration: 1.65, ease: "none" }, 6.45);

  // Stage 1: Shoulder Surfer Gaze Shield (pinned at ?p=0.57 / t = 6.84)
  tl.set(kb.pose, { screenMode: 1 }, 6.45);
  tl.to(kb.pose, { shieldBlur: 1, duration: 0.25, ease: "power2.out" }, 6.45);

  // Stage 2: MagSafe 3 physical unplug + 15s countdown (pinned at ?p=0.61 / t = 7.32)
  tl.set(kb.pose, { screenMode: 2 }, 7.05);
  tl.to(kb.pose, { magsafeSlide: 1, countdown: 15, duration: 0.22, ease: "power2.out" }, 7.05);
  tl.to(cam, { tx: -2.4, az: -0.34, duration: 0.4, ease: "sine.inOut" }, 7.05);

  // Stage 3: Lid-slam attempt + progressive siren (pinned at ?p=0.65 / t = 7.80)
  tl.set(kb.pose, { screenMode: 3 }, 7.55);
  tl.to(kb.pose, { lidAngle: 0.48, sirenPulse: 1, duration: 0.22, ease: "power2.inOut" }, 7.55);

  // Stage 4: Recovery before Touch ID macro
  tl.to(kb.pose, { lidAngle: 0, magsafeSlide: 0, sirenPulse: 0, duration: 0.28, ease: "power2.inOut" }, 8.1);

  // zoom onto Touch ID (HERO_KEY = 13), which splits into 4 parts (settled by t = 9.50 / ?p=0.80)
  tl.to(ui.vibeCopy, { autoAlpha: 0, y: -20, duration: 0.35, ease: "power1.in" }, 8.35);
  tl.to(cam, { tx: hero.x + 0.4, ty: kbY + 2.85, tz: hero.z, az: -0.4, el: 0.44, dist: 12.2, shiftX: 0.04, shiftY: -0.06, fit: 0.32, portraitLift: 0.2, duration: 0.95, ease: "power3.inOut" }, 8.4);
  tl.to(fx, { bokeh: 4.2, focusRange: 5.0, duration: 0.9 }, 8.45);
  tl.to(stage, { tilt: 0.25, duration: 0.9 }, 8.45);
  tl.to(heroKey, { parts: 1, duration: 0.01 }, 8.75);
  tl.to(heroKey.lift, { cap: SPLIT.cap, switch: SPLIT.switch, spring: SPLIT.spring, duration: 0.65, ease: "power3.inOut" }, 8.8);
  tl.to(glow, { key: 2.4, duration: 0.6 }, 8.85);
  tl.to(glow, { partLabels: 1, duration: 0.01 }, 9.35);
  tl.fromTo(ui.keyCopy, { autoAlpha: 0, y: 30 }, { autoAlpha: 1, y: 0, duration: 0.45, ease: "power3.out" }, 9.35);

  // close, Touch ID press, disarm wave & unblurred desktop
  tl.to(glow, { partLabels: 0, duration: 0.01 }, 10.85);
  tl.to(ui.keyCopy, { autoAlpha: 0, y: -20, duration: 0.4, ease: "power1.in" }, 10.85);
  tl.to(heroKey.lift, { cap: 0, switch: 0, spring: 0, duration: 0.55, ease: "power3.inOut" }, 10.9);
  tl.set(kb.pose, { screenMode: 4 }, 11.35);
  tl.to(kb.pose, { shieldBlur: 0, duration: 0.45, ease: "power2.out" }, 11.35);
  tl.to(glow, { press: 0.09, duration: 0.15, ease: "power2.in" }, 11.4);
  tl.to(glow, { wave: 1, duration: 0.5, ease: "none" }, 11.4);
  tl.to(glow, { backlight: 1.2, duration: 0.5 }, 11.4);
  tl.to(cam, { tx: 0, ty: kbY + 6.8, tz: 1.8, az: -0.22, el: 0.24, dist: 74, fit: 0.8, shiftX: 0, shiftY: -0.08, portraitLift: 0, parallax: 1, duration: 1.0, ease: "power2.inOut" }, 10.9);
  tl.to(fx, { bokeh: 1.2, focusRange: 18, duration: 1.0 }, 10.9);
  tl.to(stage, { tilt: 1, duration: 1.0 }, 10.9);
  tl.fromTo(ui.final, { autoAlpha: 0, y: 30, filter: "blur(10px)" }, { autoAlpha: 1, y: 0, filter: "blur(0px)", duration: 0.45, ease: "power3.out" }, 11.5);
  tl.set(heroKey, { parts: 0 }, 11.5);

  /* ------------------------------------------------- progress + per frame */

  let target = 0;
  let current = 0;
  const maxScroll = () => document.documentElement.scrollHeight - innerHeight;
  const readScroll = () => {
    const max = maxScroll();
    target = max > 0 ? Math.min(1, Math.max(0, scrollY / max)) : 0;
  };
  addEventListener("scroll", readScroll, { passive: true, signal });
  readScroll();

  // nav jumps glide the timeline to a section (through everything in
  // between) rather than snapping; any scroll input takes over again
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

    // keys sit still; the light, the vibe row, siren pulse and Touch ID key change
    const waveR = glow.wave * 40;
    const siren = kb.pose.sirenPulse;
    for (let i = 0; i < KEYS.length; i++) {
      const st = kb.keys[i];
      st.off.set(0, 0, 0);
      st.q.identity();
      st.s = 1;
      st.press = 0;
      const d = Math.hypot(KEYS[i].x - hero.x, KEYS[i].z - hero.z);
      const front = Math.max(0, Math.min(1, (waveR - d) / 4));
      const crest = front * Math.exp(-Math.max(0, waveR - d) / 6);
      st.white = 0;
      st.orange = glow.backlight + crest * 2.4 + siren * 0.9;
    }
    VIBE.forEach((i, j) => {
      const st = kb.keys[i];
      const bump = smooth(0.65, 0.2, Math.abs(glow.step - j));
      st.orange = Math.max(st.orange, glow.vibe) + bump * 2.4;
      st.press = 0.08 * bump;
    });
    heroKey.press += glow.press;
    heroKey.orange += glow.key;
    kb.look.mic = 0.2 + smooth(0.65, 0.2, Math.abs(glow.step - 1)) * 0.8;
    stage.focusOverride = heroKey.parts > 0.5 ? "keyStack" : null;
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
