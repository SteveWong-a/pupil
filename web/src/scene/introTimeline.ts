import gsap from "gsap";
import { KEYS } from "./ansiLayout";
import { FLIGHT_END, HERO, KB_Y, flightAt, type CameraRig } from "./cameraRig";
import type { StageState } from "./director";
import type { MacBook } from "./macbook";
import type { PostPipeline } from "./postPipeline";
import type { UiRefs } from "./uiHandles";

export const BACKLIGHT = 0.82;
const smooth = (x: number) => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));

export type IntroTimeline = ReturnType<typeof createIntroTimeline>;

export function createIntroTimeline({
  mb,
  rig,
  post,
  stage,
  ui,
  onDone,
}: {
  mb: MacBook;
  rig: CameraRig;
  post: PostPipeline;
  stage: StageState;
  ui: UiRefs;
  onDone: () => void;
}) {
  const { cam, flight } = rig;
  const { fx } = post;
  const tl = gsap.timeline({ paused: true });

  Object.assign(cam, {
    tx: HERO.target[0],
    ty: HERO.target[1],
    tz: HERO.target[2],
    az: HERO.az,
    el: HERO.el,
    dist: HERO.dist,
    fov: HERO.fov,
    roll: 0,
    fit: 1,
    shiftX: 0,
    shiftY: -0.05,
    parallax: 0,
    shake: 0,
  });
  Object.assign(fx, { bokeh: 0.8, focusRange: 14, bloom: 1.0, focusRow: 0, motionBlur: 0.6 });
  Object.assign(flight, { mix: 1, near: 0.1 });
  Object.assign(stage, { desk: 0, idle: 0, tilt: 0, shadow: 0.85, hoverKeys: 0, light: 0.65, rim: 0.6, rake: 0.25 });
  Object.assign(stage.mbPose, { y: KB_Y, rx: 0, ry: 0, rz: 0 });
  Object.assign(mb.pose, { lidAngle: 0.86, magsafeSlide: 0.75, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0, phoneMode: 0, phonePress: 0 });

  const glow = { level: 0.0 };
  post.ao.configuration.aoRadius = 0.45;

  // 1. MagSafe 3 snaps into the left port (0.15s -> 0.80s)
  tl.to(mb.pose, { magsafeSlide: 0, duration: 0.65, ease: "back.out(1.4)" }, 0.15);

  // 2. Studio lights rise & 16" Retina display lid hinges open (0.70s -> 2.65s)
  tl.to(stage, { light: 1, shadow: 1, rim: 1, rake: 0, duration: 1.4, ease: "sine.inOut" }, 0.6);
  tl.to(mb.pose, { lidAngle: 0, duration: 1.95, ease: "power2.inOut" }, 0.7);
  tl.to(glow, { level: BACKLIGHT, duration: 1.4, ease: "sine.inOut" }, 1.1);
  tl.to(fx, { bokeh: 0.5, focusRange: 18, motionBlur: 0, duration: 1.2, ease: "sine.inOut" }, 1.8);

  // 3. Settle into Hero product tilt & hand off to orbit rig
  tl.to(stage.mbPose, { rx: 0.12, duration: 1.4, ease: "power2.inOut" }, 1.8);
  tl.to(flight, { mix: 0, duration: 1.0, ease: "power2.inOut" }, FLIGHT_END - 1.0);
  tl.to(stage, { idle: 1, tilt: 1, hoverKeys: 1, duration: 0.8, ease: "sine.out" }, FLIGHT_END - 0.8);
  tl.to(cam, { parallax: 1, duration: 0.8, ease: "sine.inOut" }, FLIGHT_END - 0.8);

  gsap.set([ui.hero, ui.gaze, ui.tamper, ui.phone, ui.macos, ui.final], { autoAlpha: 0 });
  gsap.set(ui.nav, { autoAlpha: 1 });
  tl.fromTo(ui.veil, { autoAlpha: 1 }, { autoAlpha: 0, duration: 0.4, ease: "power1.out" }, 0);
  tl.fromTo(ui.hero, { autoAlpha: 0, y: 24, filter: "blur(12px)" }, { autoAlpha: 1, y: 0, filter: "blur(0px)", duration: 0.9, ease: "power3.out" }, FLIGHT_END - 0.85);
  tl.call(() => onDone(), undefined, FLIGHT_END);

  let playing = false;
  function play() {
    tl.time(0);
    playing = true;
  }
  function advance(dt: number) {
    if (!playing) return;
    const t = Math.min(FLIGHT_END, tl.time() + Math.min(dt, 1 / 30));
    tl.time(t);
    if (t >= FLIGHT_END) playing = false;
  }

  function update() {
    const t = tl.time();
    flightAt(t, flight);

    const wave = -18 + (t - 0.85) * 26;
    for (let i = 0; i < KEYS.length; i++) {
      const k = KEYS[i];
      const st = mb.keys[i];
      st.off.set(0, 0, 0);
      st.q.identity();
      st.s = 1;
      st.press = 0;
      st.inner = 1;
      st.led = 1;
      const wake = smooth((wave - k.x) / 5.0);
      st.white = glow.level * wake;
      st.orange = glow.level * wake;
    }
  }

  return { tl, play, advance, update, end: FLIGHT_END };
}
