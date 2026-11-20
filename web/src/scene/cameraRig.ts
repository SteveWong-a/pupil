import * as THREE from "three";

export const KB_Y = 4.4;
export const HERO = { target: [2.2, 9.6, 1.5], az: -0.16, el: 0.23, dist: 78, fov: 30 } as const;
export const FLIGHT_END = 3.5;

type V3 = [number, number, number];
type Keyframe = [camera: V3, aim: V3, roll: number, fov: number];

const heroPos: V3 = [
  HERO.target[0] + HERO.dist * Math.cos(HERO.el) * Math.sin(HERO.az),
  HERO.target[1] + HERO.dist * Math.sin(HERO.el) - KB_Y,
  HERO.target[2] + HERO.dist * Math.cos(HERO.el) * Math.cos(HERO.az),
];
const heroAim: V3 = [HERO.target[0], HERO.target[1] - KB_Y, HERO.target[2]];

const KEYFRAMES: Keyframe[] = [
  [[-26.5, 2.4, -2.5], [-14.5, 1.2, -3.2], -0.08, 36],
  [[-23.5, 3.2, 4.5], [-11.0, 1.3, -1.5], -0.1, 36],
  [[-16.5, 4.8, 16.5], [-3.0, 2.2, 1.5], -0.12, 35],
  [[-9.5, 6.8, 28.0], [0.5, 3.4, 1.2], -0.08, 33],
  [[-10.2, 9.8, 52.0], [1.6, 4.6, 1.4], -0.03, 31],
  [heroPos, heroAim, 0, HERO.fov],
];

const FEEL: [number, number][] = [
  [0.0, 1.35],
  [0.8, 1.25],
  [1.6, 0.9],
  [2.4, 0.45],
  [3.0, 0.16],
  [FLIGHT_END, 0],
];

const BOXES = [{ x0: -16.0, x1: 16.0, y0: 0, y1: 1.95, z0: -6.4, z1: 14.5 }];
const NEAREST = 0.7;

function monotone(xs: number[], ys: number[]) {
  const n = xs.length - 1;
  const h = xs.slice(1).map((x, i) => x - xs[i]);
  const s = h.map((hi, i) => (ys[i + 1] - ys[i]) / hi);
  const m = ys.map((_, i) => (i === 0 ? s[0] : i === n ? s[n - 1] : s[i - 1] * s[i] <= 0 ? 0 : (s[i - 1] + s[i]) / 2));
  for (let i = 0; i < n; i++) {
    if (s[i] === 0) {
      m[i] = m[i + 1] = 0;
      continue;
    }
    const al = m[i] / s[i];
    const be = m[i + 1] / s[i];
    const r = al * al + be * be;
    if (r > 9) {
      const k = 3 / Math.sqrt(r);
      m[i] = k * al * s[i];
      m[i + 1] = k * be * s[i];
    }
  }
  return (x: number) => {
    x = Math.min(xs[n], Math.max(xs[0], x));
    let i = 0;
    while (i < n - 1 && x > xs[i + 1]) i++;
    const u = (x - xs[i]) / h[i];
    const u2 = u * u;
    const u3 = u2 * u;
    return (2 * u3 - 3 * u2 + 1) * ys[i] + (u3 - 2 * u2 + u) * h[i] * m[i] + (-2 * u3 + 3 * u2) * ys[i + 1] + (u3 - u2) * h[i] * m[i + 1];
  };
}

const along = [0];
for (let i = 1; i < KEYFRAMES.length; i++) {
  const [p, q] = [KEYFRAMES[i - 1][0], KEYFRAMES[i][0]];
  along.push(along[i - 1] + Math.hypot(q[0] - p[0], q[1] - p[1], q[2] - p[2]));
}
const LENGTH = along[along.length - 1];
const channel = (pick: (k: Keyframe) => number) => monotone(along, KEYFRAMES.map(pick));
const posFns = [0, 1, 2].map((j) => channel((k) => k[0][j]));
const aimFns = [0, 1, 2].map((j) => channel((k) => k[1][j]));
const rollFn = channel((k) => k[2]);
const fovFn = channel((k) => k[3]);

const N = 4000;
const feltAt = new Float64Array(N + 1);
const clearance = (q: number[]) =>
  Math.hypot(
    NEAREST,
    Math.min(
      ...BOXES.map((b) =>
        Math.hypot(Math.max(b.x0 - q[0], q[0] - b.x1, 0), Math.max(b.y0 - q[1], q[1] - b.y1, 0), Math.max(b.z0 - q[2], q[2] - b.z1, 0)),
      ),
    ),
  );
{
  const pts = Array.from({ length: N + 1 }, (_, i) => posFns.map((f) => f((i / N) * LENGTH)));
  let D = pts.map(clearance);
  const R = Math.round((2.5 / LENGTH) * N);
  for (let pass = 0; pass < 3; pass++) {
    const sum = [0];
    for (const v of D) sum.push(sum[sum.length - 1] + v);
    D = D.map((_, i) => {
      const lo = Math.max(0, i - R);
      const hi = Math.min(N, i + R);
      return (sum[hi + 1] - sum[lo]) / (hi - lo + 1);
    });
  }
  for (let i = 1; i <= N; i++) {
    const [p, q] = [pts[i - 1], pts[i]];
    feltAt[i] = feltAt[i - 1] + Math.hypot(q[0] - p[0], q[1] - p[1], q[2] - p[2]) / D[i];
  }
}

const distanceOfFelt = (f: number) => {
  let lo = 0;
  let hi = N;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (feltAt[mid] < f) lo = mid;
    else hi = mid;
  }
  const u = (f - feltAt[lo]) / (feltAt[hi] - feltAt[lo] || 1);
  return ((lo + Math.min(1, Math.max(0, u))) / N) * LENGTH;
};

const STEP = 1 / 500;
const feel = monotone(
  FEEL.map((k) => k[0]),
  FEEL.map((k) => k[1]),
);
const steps = Math.round(FLIGHT_END / STEP);
const felt = new Float64Array(steps + 2);
for (let i = 1; i < felt.length; i++) felt[i] = felt[i - 1] + ((feel((i - 1) * STEP) + feel(i * STEP)) / 2) * STEP;
const scale = feltAt[N] / felt[steps];
const distanceAt = (t: number) => {
  const x = Math.min(FLIGHT_END, Math.max(0, t)) / STEP;
  const i = Math.min(steps, Math.floor(x));
  return distanceOfFelt((felt[i] + (felt[i + 1] - felt[i]) * (x - i)) * scale);
};

export const keyTimes = along.map((d) => {
  let i = 0;
  while (i < steps && distanceAt(i * STEP) < d - 1e-6) i++;
  return i * STEP;
});

export interface FlightState {
  mix: number;
  pos: THREE.Vector3;
  target: THREE.Vector3;
  roll: number;
  fov: number;
  near: number;
  fit: number;
}

export function flightAt(t: number, out: FlightState) {
  const d = distanceAt(t);
  out.pos.set(posFns[0](d), posFns[1](d) + KB_Y, posFns[2](d));
  out.target.set(aimFns[0](d), aimFns[1](d) + KB_Y, aimFns[2](d));
  out.roll = rollFn(d);
  out.fov = fovFn(d);
  const reach = Math.hypot(out.pos.x - out.target.x, out.pos.y - out.target.y, out.pos.z - out.target.z);
  const f = Math.min(1, Math.max(0, Math.log(reach / 12) / Math.log(HERO.dist / 12)));
  out.fit = f * f * (3 - 2 * f);
  return out;
}

/* ----------------------------------------------------------- orbit rig */

const NEAR = 0.3;
const WIDEST = 16 / 9;

export interface CamShot {
  tx: number;
  ty: number;
  tz: number;
  az: number;
  el: number;
  dist: number;
  fov: number;
  roll: number;
  shiftX: number;
  shiftY: number;
  fit: number;
  parallax: number;
  portraitLift: number;
  shake: number;
}

export interface FocusState {
  mix: number;
  tx: number;
  ty: number;
  tz: number;
  az: number;
  el: number;
  dist: number;
  fov: number;
  shiftX: number;
  shiftY: number;
  bokeh: number;
  focusRange: number;
}

export interface OrbitState {
  az: number;
  el: number;
  dist: number;
  targetAz: number;
  targetEl: number;
  targetDist: number;
  dragging: boolean;
}

export type CameraRig = ReturnType<typeof createCameraRig>;

function lerpAngle(a: number, b: number, t: number) {
  let d = ((b - a + Math.PI) % (Math.PI * 2)) - Math.PI;
  if (d < -Math.PI) d += Math.PI * 2;
  return a + d * t;
}

export function createCameraRig(signal: AbortSignal) {
  const cam: CamShot = {
    tx: 0,
    ty: 0,
    tz: 0,
    az: 0,
    el: 0.3,
    dist: 40,
    fov: 32,
    roll: 0,
    shiftX: 0,
    shiftY: 0,
    fit: 1,
    parallax: 0,
    portraitLift: 0,
    shake: 0,
  };
  const focus: FocusState = {
    mix: 0,
    tx: 0,
    ty: 0,
    tz: 0,
    az: 0,
    el: 0.25,
    dist: 20,
    fov: 26,
    shiftX: 0,
    shiftY: 0,
    bokeh: 1.8,
    focusRange: 10,
  };
  const orbit: OrbitState = {
    az: 0,
    el: 0,
    dist: 0,
    targetAz: 0,
    targetEl: 0,
    targetDist: 0,
    dragging: false,
  };
  let clock = 0;
  const wobble = (t: number, a: number) => Math.sin(t * 1.3 + a) * 0.6 + Math.sin(t * 2.9 + a * 2.1) * 0.3 + Math.sin(t * 6.1 + a * 0.7) * 0.1;
  const target = new THREE.Vector3();
  const pointer = { x: 0, y: 0, sx: 0, sy: 0 };
  const flight: FlightState = { mix: 0, pos: new THREE.Vector3(), target: new THREE.Vector3(), roll: 0, fov: 34, near: 0.3, fit: 0 };
  const orbitPos = new THREE.Vector3();
  const flightPos = new THREE.Vector3();

  addEventListener(
    "pointermove",
    (e) => {
      pointer.x = (e.clientX / innerWidth) * 2 - 1;
      pointer.y = (e.clientY / innerHeight) * 2 - 1;
    },
    { signal },
  );

  function resetOrbit() {
    orbit.targetAz = 0;
    orbit.targetEl = 0;
    orbit.targetDist = 0;
  }

  function isInteractiveSettled() {
    if (orbit.dragging) return false;
    if (focus.mix > 0.001 && focus.mix < 0.999) return false;
    return (
      Math.abs(orbit.targetAz - orbit.az) < 1e-4 &&
      Math.abs(orbit.targetEl - orbit.el) < 1e-4 &&
      Math.abs(orbit.targetDist - orbit.dist) < 1e-3
    );
  }

  function apply(camera: THREE.PerspectiveCamera, w: number, h: number, dt = 1 / 60) {
    clock += dt;
    const k = 1 - Math.exp(-dt * 3);
    pointer.sx += (pointer.x - pointer.sx) * k;
    pointer.sy += (pointer.y - pointer.sy) * k;

    const ok = 1 - Math.exp(-dt * 11);
    orbit.az += (orbit.targetAz - orbit.az) * ok;
    orbit.el += (orbit.targetEl - orbit.el) * ok;
    orbit.dist += (orbit.targetDist - orbit.dist) * ok;

    const fm = THREE.MathUtils.clamp(focus.mix, 0, 1);
    const aspect = w / h;
    const narrow = Math.max(1, 1.55 / aspect) ** 0.78;
    const effFit = THREE.MathUtils.lerp(cam.fit, 0.35, fm);
    const baseDist = THREE.MathUtils.lerp(cam.dist, focus.dist, fm);
    const dist = THREE.MathUtils.clamp(baseDist * (1 + (narrow - 1) * effFit) + orbit.dist, 9, 95);

    const parallaxWeight = cam.parallax * (1 - fm * 0.75) * (orbit.dragging ? 0.15 : 1);
    const baseAz = lerpAngle(cam.az, focus.az, fm);
    const baseEl = THREE.MathUtils.lerp(cam.el, focus.el, fm);
    const az = baseAz + orbit.az + pointer.sx * 0.03 * parallaxWeight + wobble(clock, 0.4) * 0.006 * cam.shake * (1 - fm);
    const el = THREE.MathUtils.clamp(
      baseEl + orbit.el - pointer.sy * 0.02 * parallaxWeight + wobble(clock, 2.3) * 0.004 * cam.shake * (1 - fm),
      0.04,
      1.38,
    );

    target.set(
      THREE.MathUtils.lerp(cam.tx, focus.tx, fm),
      THREE.MathUtils.lerp(cam.ty, focus.ty, fm),
      THREE.MathUtils.lerp(cam.tz, focus.tz, fm),
    );
    orbitPos.set(
      target.x + dist * Math.cos(el) * Math.sin(az),
      target.y + dist * Math.sin(el),
      target.z + dist * Math.cos(el) * Math.cos(az),
    );
    const f = flight.mix;
    const back = 1 + (narrow - 1) * cam.fit * flight.fit;
    flightPos.copy(flight.pos).sub(flight.target).multiplyScalar(back).add(flight.target);
    camera.position.lerpVectors(orbitPos, flightPos, f);
    target.lerp(flight.target, f);
    camera.up.set(0, 1, 0);
    camera.lookAt(target);
    camera.rotateZ(THREE.MathUtils.lerp(cam.roll * (1 - fm), flight.roll, f) + wobble(clock, 4.1) * 0.005 * cam.shake * (1 - fm));
    camera.fov = THREE.MathUtils.lerp(THREE.MathUtils.lerp(cam.fov, focus.fov, fm), flight.fov, f);
    camera.near = THREE.MathUtils.lerp(NEAR, flight.near, f);
    camera.aspect = aspect;

    const effShiftX = THREE.MathUtils.lerp(cam.shiftX, focus.shiftX, fm);
    const effShiftY = THREE.MathUtils.lerp(cam.shiftY, focus.shiftY, fm);
    const sx = aspect < 1 ? 0 : effShiftX;
    let sy = effShiftY - Math.max(0, Math.min(aspect, WIDEST) - 1.6) * 0.32 * (1 - fm * 0.7);
    if (aspect < 1) sy += cam.portraitLift * (1 - fm);
    camera.setViewOffset(w, h, -sx * w * (1 - f), sy * h * (1 - f), w, h);
    camera.updateProjectionMatrix();
  }

  return { cam, focus, orbit, target, pointer, flight, resetOrbit, isInteractiveSettled, apply };
}
