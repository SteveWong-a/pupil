import * as THREE from "three";
import type { CameraRig } from "./cameraRig";
import type { FeatureId, MacBook } from "./macbook";

interface InteractionOptions {
  canvas: HTMLCanvasElement;
  camera: THREE.PerspectiveCamera;
  mb: MacBook;
  rig: CameraRig;
  signal: AbortSignal;
  isReady: () => boolean;
  getFocused: () => FeatureId | null;
  onFocusFeature: (id: FeatureId) => void;
  onTriggerDemo: (id: FeatureId) => void;
  onClearFocus: () => void;
}

export function createSceneInteraction({
  canvas,
  camera,
  mb,
  rig,
  signal,
  isReady,
  getFocused,
  onFocusFeature,
  onTriggerDemo,
  onClearFocus,
}: InteractionOptions) {
  const raycaster = new THREE.Raycaster();
  const ndc = new THREE.Vector2();

  let activePointerId: number | null = null;
  let lastX = 0;
  let lastY = 0;
  let moved = 0;

  function pickFeature(clientX: number, clientY: number): FeatureId | null {
    ndc.set((clientX / innerWidth) * 2 - 1, -((clientY / innerHeight) * 2 - 1));
    raycaster.setFromCamera(ndc, camera);

    for (const target of mb.hitTargets) {
      const hits = raycaster.intersectObject(target.object, true);
      if (hits.length === 0) continue;
      if (target.feature === "gaze-shield" && hits[0].uv) {
        const { x: u, y: v } = hits[0].uv;
        if (v > 0.88 && u > 0.38 && u < 0.62) return "gaze-notch";
        if (v > 0.65 && u > 0.72) return "macos-popover";
        if (v > 0.3 && v < 0.72 && u > 0.5 && u < 0.82 && getFocused()?.startsWith("macos-")) return "macos-settings";
      }
      return target.feature;
    }
    return null;
  }

  function isModalOpen() {
    return Boolean(document.querySelector("[role='dialog']"));
  }

  canvas.addEventListener(
    "pointerdown",
    (e) => {
      if (!isReady() || isModalOpen()) return;
      if (e.pointerType === "mouse" && e.button !== 0) return;
      activePointerId = e.pointerId;
      lastX = e.clientX;
      lastY = e.clientY;
      moved = 0;
      rig.orbit.dragging = true;
      canvas.setPointerCapture(e.pointerId);
      canvas.style.cursor = "grabbing";
    },
    { signal },
  );

  canvas.addEventListener(
    "pointermove",
    (e) => {
      if (!isReady() || isModalOpen()) return;
      if (activePointerId === e.pointerId) {
        const dx = e.clientX - lastX;
        const dy = e.clientY - lastY;
        lastX = e.clientX;
        lastY = e.clientY;
        moved += Math.hypot(dx, dy);

        const focused = getFocused() !== null;
        const azLimit = focused ? 1.85 : 1.15;
        const sens = focused ? 0.0062 : 0.0048;
        rig.orbit.targetAz = THREE.MathUtils.clamp(rig.orbit.targetAz - dx * sens, -azLimit, azLimit);
        rig.orbit.targetEl = THREE.MathUtils.clamp(rig.orbit.targetEl + dy * sens * 0.78, -0.5, 0.75);
        return;
      }

      if (e.pointerType === "mouse" && activePointerId === null) {
        const hit = pickFeature(e.clientX, e.clientY);
        canvas.style.cursor = hit ? "pointer" : "grab";
      }
    },
    { signal },
  );

  function endPointer(e: PointerEvent, cancelled = false) {
    if (activePointerId !== e.pointerId) return;
    activePointerId = null;
    rig.orbit.dragging = false;
    if (canvas.hasPointerCapture(e.pointerId)) {
      canvas.releasePointerCapture(e.pointerId);
    }
    canvas.style.cursor = "grab";

    if (!cancelled && moved < 6 && isReady() && !isModalOpen()) {
      const hit = pickFeature(e.clientX, e.clientY);
      const cur = getFocused();
      if (hit) {
        if (cur === hit) onTriggerDemo(hit);
        else onFocusFeature(hit);
      } else if (cur !== null) {
        onClearFocus();
      }
    }
  }

  canvas.addEventListener("pointerup", (e) => endPointer(e, false), { signal });
  canvas.addEventListener("pointercancel", (e) => endPointer(e, true), { signal });
  canvas.addEventListener(
    "dblclick",
    () => {
      if (!isReady() || isModalOpen()) return;
      rig.resetOrbit();
    },
    { signal },
  );

  // Subtle +/- zoom and 0 reset while inspecting
  addEventListener(
    "keydown",
    (e) => {
      if (!isReady() || isModalOpen()) return;
      const tag = (document.activeElement as HTMLElement | null)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if (getFocused() === null) return;
      if (e.key === "=" || e.key === "+") {
        rig.orbit.targetDist = THREE.MathUtils.clamp(rig.orbit.targetDist - 3, -7, 16);
      } else if (e.key === "-") {
        rig.orbit.targetDist = THREE.MathUtils.clamp(rig.orbit.targetDist + 3, -7, 16);
      } else if (e.key === "0") {
        rig.resetOrbit();
      }
    },
    { signal },
  );
}
