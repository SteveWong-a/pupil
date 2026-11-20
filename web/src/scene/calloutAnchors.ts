import * as THREE from "three";
import { KEYS } from "./ansiLayout";
import { CAP_H, LAYERS, type FeatureId, type MacBook } from "./macbook";
import type { GlowState } from "./scrollStory";

export function createCalloutProjector({ mb, camera, root }: { mb: MacBook; camera: THREE.Camera; root: HTMLElement }) {
  const els = Array.from(root.querySelectorAll<HTMLElement>("[data-feature]"));
  const v = new THREE.Vector3();

  const toScreen = (world: THREE.Vector3, w: number, h: number, out: THREE.Vector3) => {
    out.copy(world).project(camera);
    out.set((out.x * 0.5 + 0.5) * w, (-out.y * 0.5 + 0.5) * h, out.z);
    return out;
  };
  const show = (el: HTMLElement, x: number, y: number, z: number, alpha: number, interactive: boolean) => {
    el.style.transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0)`;
    el.style.opacity = alpha.toFixed(3);
    const vis = alpha > 0.01 && z < 1;
    el.style.visibility = vis ? "visible" : "hidden";
    el.dataset.interactive = vis && interactive ? "true" : "false";
  };
  const hide = (el: HTMLElement) => {
    el.style.visibility = "hidden";
    el.dataset.interactive = "false";
  };

  const none: Pick<GlowState, "ch1" | "ch2" | "ch3" | "ch4"> = { ch1: 0, ch2: 0, ch3: 0, ch4: 0 };
  const LEAD = 40;
  const MIN_GAP = 64;

  function update(
    w: number,
    h: number,
    g: Pick<GlowState, "ch1" | "ch2" | "ch3" | "ch4"> = none,
    focused: FeatureId | null = null,
    hovered: FeatureId | null = null,
  ) {
    const outerMargin = Math.min(390, Math.max(320, w * 0.3));

    for (const ch of ["ch1", "ch2", "ch3", "ch4"] as const) {
      const alpha = g[ch];
      const group = els.filter((el) => el.dataset.chapter === ch);
      if (alpha <= 0.01) {
        group.forEach(hide);
        continue;
      }
      const side = group[0]?.dataset.side ?? "left";
      const minY = 120;
      const maxY = Math.max(minY, h - 140);
      const pts = group.map((el) => {
        const id = el.dataset.feature as FeatureId;
        mb.featurePoint(id, v);
        const sc = toScreen(v, w, h, new THREE.Vector3());
        const origX = sc.x;
        const origY = sc.y;
        const clampedX =
          side === "left"
            ? Math.min(w - 160, Math.max(outerMargin, origX))
            : Math.min(w - outerMargin, Math.max(160, origX));
        const boxY = Math.min(maxY, Math.max(minY, origY));
        return { el, id, origX, origY, clampedX, boxY, z: sc.z };
      });

      pts.sort((a, b) => a.boxY - b.boxY);
      for (let i = 1; i < pts.length; i++) {
        if (pts[i].boxY - pts[i - 1].boxY < MIN_GAP) {
          pts[i].boxY = pts[i - 1].boxY + MIN_GAP;
        }
      }
      const overflow = pts.length ? pts[pts.length - 1].boxY - maxY : 0;
      if (overflow > 0) {
        for (const pt of pts) pt.boxY -= overflow;
        if (pts[0].boxY < minY) {
          const shift = minY - pts[0].boxY;
          for (const pt of pts) pt.boxY += shift;
          for (let i = 1; i < pts.length; i++) {
            if (pts[i].boxY - pts[i - 1].boxY < MIN_GAP) {
              pts[i].boxY = pts[i - 1].boxY + MIN_GAP;
            }
          }
        }
      }

      const colX =
        side === "left"
          ? Math.max(outerMargin, Math.min(...pts.map((p) => p.clampedX)))
          : Math.min(w - outerMargin, Math.max(...pts.map((p) => p.clampedX)));

      for (const { el, id, origX, origY, boxY, z } of pts) {
        const lead = LEAD + Math.max(0, side === "left" ? origX - colX : colX - origX);
        const dy = boxY - origY;
        el.style.setProperty("--lead", `${lead.toFixed(1)}px`);
        el.style.setProperty("--dy", `${dy.toFixed(1)}px`);
        const isFocused = focused === id;
        const isHovered = hovered === id;
        el.dataset.focused = isFocused ? "true" : "false";
        el.dataset.hovered = isHovered ? "true" : "false";
        const effAlpha = focused && !isFocused && !isHovered ? alpha * 0.42 : alpha;
        show(el, origX, origY, z, effAlpha, alpha > 0.25);
      }
    }
  }

  return { update };
}

export function createKeyHover({ mb, camera, signal }: { mb: MacBook; camera: THREE.Camera; signal: AbortSignal }) {
  const raycaster = new THREE.Raycaster();
  const ndc = new THREE.Vector2();
  const inv = new THREE.Matrix4();
  const ray = new THREE.Ray();
  const hit = new THREE.Vector3();
  const tops = new THREE.Plane(new THREE.Vector3(0, 1, 0), -(LAYERS.caps.y + CAP_H / 2));
  const springs = KEYS.map(() => ({ x: 0, v: 0 }));
  const smooth = (e0: number, e1: number, x: number) => {
    const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
    return t * t * (3 - 2 * t);
  };

  let px = 0;
  let py = 0;
  let inside = false;
  addEventListener(
    "pointermove",
    (e) => {
      px = (e.clientX / innerWidth) * 2 - 1;
      py = -((e.clientY / innerHeight) * 2 - 1);
      inside = true;
    },
    { signal },
  );
  document.documentElement.addEventListener("pointerleave", () => (inside = false), { signal });
  addEventListener("pointerup", (e) => e.pointerType !== "mouse" && (inside = false), { signal });

  function update(dt: number, weight: number) {
    let hx = Infinity;
    let hz = Infinity;
    if (weight > 0.01 && inside) {
      ndc.set(px, py);
      raycaster.setFromCamera(ndc, camera);
      inv.copy(mb.root.matrixWorld).invert();
      ray.copy(raycaster.ray).applyMatrix4(inv);
      if (ray.intersectPlane(tops, hit)) {
        hx = hit.x;
        hz = hit.z;
      }
    }
    const h = Math.min(dt, 1 / 30);
    for (let i = 0; i < KEYS.length; i++) {
      const k = KEYS[i];
      const ox = Math.max(0, Math.abs(hx - k.x) - k.w / 2);
      const oz = Math.max(0, Math.abs(hz - k.z) - k.d / 2);
      const out = Math.hypot(ox, oz);
      const target = (out === 0 ? 1 : 0.35 * (1 - smooth(0, 1.4, out))) * weight;
      const s = springs[i];
      s.v += ((target - s.x) * 190 - s.v * 19) * h;
      s.x += s.v * h;
      const st = mb.keys[i];
      st.hover = s.x;
      st.orange += Math.max(0, s.x) * 0.9;
    }
  }

  return { update };
}
