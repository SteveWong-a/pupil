import * as THREE from "three";

interface Passerby {
  x: number; // normalized -0.35 .. 1.35 across the spotlight cone
  dir: 1 | -1;
  speed: number;
  scale: number;
  opacity: number;
  bobPhase: number;
  bobFreq: number;
  lean: number;
}

export interface ShadowUpdateInput {
  /** 0..1 weight for Overview randomized passersby (ramps in during intro glide 2.4s->3.2s) */
  overviewWeight: number;
  /** 0..1 weight for Chapter 1 lingering shoulder-surfer shadow */
  gazeWeight: number;
  /** If true (live Gaze demo toggled off), lingering shadow steps back temporarily */
  gazeRetreat: boolean;
  /** True when ?t or ?p freezes time */
  frozen: boolean;
}

export type PasserbyShadows = ReturnType<typeof createPasserbyShadows>;

const GOBO_SIZE = 512;
const SCR_W = 256;
const SCR_H = 160;

function drawSilhouette(
  ctx: CanvasRenderingContext2D,
  cx: number,
  baseY: number,
  scale: number,
  lean: number,
  opacity: number,
  elongation = 1.0,
) {
  ctx.save();
  ctx.translate(cx, baseY);
  ctx.rotate(lean);
  ctx.fillStyle = `rgba(0, 0, 0, ${opacity.toFixed(3)})`;

  const s = scale;
  const e = elongation;

  // Elongated torso / lower body shadow column extending down across the desk & laptop
  ctx.beginPath();
  ctx.moveTo(-66 * s, 210 * s * e);
  ctx.bezierCurveTo(-72 * s, 70 * s * e, -62 * s, -40 * s * e, -46 * s, -72 * s * e);
  // Left shoulder curve into neck
  ctx.quadraticCurveTo(-24 * s, -90 * s * e, -15 * s, -98 * s * e);
  // Right side of neck & shoulder
  ctx.lineTo(15 * s, -98 * s * e);
  ctx.quadraticCurveTo(24 * s, -90 * s * e, 46 * s, -72 * s * e);
  ctx.bezierCurveTo(62 * s, -40 * s * e, 72 * s, 70 * s * e, 66 * s, 210 * s * e);
  ctx.closePath();
  ctx.fill();

  // Head silhouette (slightly oval, softened by penumbra blur)
  ctx.beginPath();
  ctx.ellipse(0, -132 * s * e, 28 * s, 35 * s * e, 0, 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();
}

export function createPasserbyShadows() {
  const goboCanvas = document.createElement("canvas");
  goboCanvas.width = GOBO_SIZE;
  goboCanvas.height = GOBO_SIZE;
  const gctx = goboCanvas.getContext("2d")!;

  const screenCanvas = document.createElement("canvas");
  screenCanvas.width = SCR_W;
  screenCanvas.height = SCR_H;
  const sctx = screenCanvas.getContext("2d")!;

  const deckCanvas = document.createElement("canvas");
  deckCanvas.width = SCR_W;
  deckCanvas.height = SCR_H;
  const dctx = deckCanvas.getContext("2d")!;

  const goboTexture = new THREE.CanvasTexture(goboCanvas);
  goboTexture.colorSpace = THREE.SRGBColorSpace;
  goboTexture.minFilter = THREE.LinearFilter;
  goboTexture.magFilter = THREE.LinearFilter;

  const screenTexture = new THREE.CanvasTexture(screenCanvas);
  screenTexture.colorSpace = THREE.SRGBColorSpace;
  screenTexture.minFilter = THREE.LinearFilter;
  screenTexture.magFilter = THREE.LinearFilter;

  const deckTexture = new THREE.CanvasTexture(deckCanvas);
  deckTexture.colorSpace = THREE.SRGBColorSpace;
  deckTexture.minFilter = THREE.LinearFilter;
  deckTexture.magFilter = THREE.LinearFilter;

  const supportsFilter = "filter" in CanvasRenderingContext2D.prototype;

  // Initialize neutral (100% white gobo, 100% transparent screen & deck veils)
  gctx.fillStyle = "#ffffff";
  gctx.fillRect(0, 0, GOBO_SIZE, GOBO_SIZE);
  goboTexture.needsUpdate = true;
  sctx.clearRect(0, 0, SCR_W, SCR_H);
  screenTexture.needsUpdate = true;
  dctx.clearRect(0, 0, SCR_W, SCR_H);
  deckTexture.needsUpdate = true;

  const walkers: Passerby[] = [];
  let spawnTimer = 0.05; // spawn first passerby immediately once overviewWeight > 0 (intro glide 2.4s)
  let hasSpawnedFirst = false;
  let lastDir: 1 | -1 = -1;

  let gazeSettle = 0;
  let gazeBlurTrigger = 0;
  let wasNeutral = true;
  let paintAccum = 1;
  let lastFrozenKey = "";

  function spawnWalker(forcedDir?: 1 | -1) {
    // Bias slightly toward alternating direction so it feels like people walking back & forth
    const dir: 1 | -1 = forcedDir ?? (Math.random() < 0.72 ? (lastDir === 1 ? -1 : 1) : lastDir);
    lastDir = dir;
    walkers.push({
      x: dir === 1 ? -0.28 : 1.28,
      dir,
      speed: 0.25 + Math.random() * 0.2,
      scale: 0.84 + Math.random() * 0.32,
      opacity: 0.48 + Math.random() * 0.16,
      bobPhase: Math.random() * Math.PI * 2,
      bobFreq: 6.4 + Math.random() * 2.2,
      lean: dir * (0.06 + Math.random() * 0.05),
    });
  }

  function update(dt: number, t: number, input: ShadowUpdateInput) {
    const { overviewWeight, gazeWeight, gazeRetreat, frozen } = input;
    const step = frozen ? 0 : Math.min(dt, 0.05);

    // 1. Update randomized Overview passersby
    if (overviewWeight > 0.02 && !frozen) {
      spawnTimer -= step;
      if (spawnTimer <= 0 && walkers.length < 2) {
        if (!hasSpawnedFirst) {
          hasSpawnedFirst = true;
          spawnWalker(1); // First passerby glides cleanly left -> right during intro pull-back
          spawnTimer = 2.4 + Math.random() * 1.6;
        } else {
          spawnWalker();
          spawnTimer = 1.6 + Math.random() * 2.8;
        }
      }
    }

    for (let i = walkers.length - 1; i >= 0; i--) {
      const w = walkers[i];
      w.x += w.dir * w.speed * step;
      w.bobPhase += w.bobFreq * step;
      if ((w.dir === 1 && w.x > 1.38) || (w.dir === -1 && w.x < -0.38)) {
        walkers.splice(i, 1);
      }
    }

    // 2. Update Chapter 1 lingering shoulder-surfer shadow & 95ms blur trigger
    const targetSettle = gazeRetreat ? 0 : gazeWeight;
    if (frozen) {
      gazeSettle = targetSettle;
    } else {
      const rate = targetSettle > gazeSettle ? 2.4 : 4.2;
      gazeSettle += (targetSettle - gazeSettle) * (1 - Math.exp(-step * rate));
      if (Math.abs(targetSettle - gazeSettle) < 0.002) gazeSettle = targetSettle;
    }

    // Trigger 95ms Privacy Blur once the long shadow settles into the gaze zone (>= 0.66)
    const shouldBlur = gazeSettle >= 0.66 && !gazeRetreat;
    const blurTarget = shouldBlur ? 1 : 0;
    if (frozen) {
      gazeBlurTrigger = blurTarget;
    } else {
      const blurRate = blurTarget > gazeBlurTrigger ? 24 : 11; // ~95ms crisp frost-in, smooth clear
      gazeBlurTrigger += (blurTarget - gazeBlurTrigger) * (1 - Math.exp(-step * blurRate));
      if (Math.abs(blurTarget - gazeBlurTrigger) < 0.003) gazeBlurTrigger = blurTarget;
    }

    const hasWalkers = walkers.length > 0 && overviewWeight > 0.01;
    const hasGazeShadow = gazeSettle > 0.01;

    if (!hasWalkers && !hasGazeShadow) {
      if (!wasNeutral) {
        gctx.fillStyle = "#ffffff";
        gctx.fillRect(0, 0, GOBO_SIZE, GOBO_SIZE);
        goboTexture.needsUpdate = true;
        sctx.clearRect(0, 0, SCR_W, SCR_H);
        screenTexture.needsUpdate = true;
        dctx.clearRect(0, 0, SCR_W, SCR_H);
        deckTexture.needsUpdate = true;
        wasNeutral = true;
      }
      return;
    }

    wasNeutral = false;

    if (frozen) {
      const key = `${overviewWeight.toFixed(3)}:${gazeSettle.toFixed(3)}`;
      if (key === lastFrozenKey) return;
      lastFrozenKey = key;
    } else {
      paintAccum += step;
      if (paintAccum < 1 / 30) return;
      paintAccum = 0;
    }

    // 3. Paint spotlight gobo (512x512, white = full light, black = shadow)
    gctx.save();
    gctx.fillStyle = "#ffffff";
    gctx.fillRect(0, 0, GOBO_SIZE, GOBO_SIZE);
    if (supportsFilter) gctx.filter = "blur(20px)";

    // 4. Paint synchronized glossy screen shadow veil (256x160, transparent = clear)
    sctx.save();
    sctx.clearRect(0, 0, SCR_W, SCR_H);
    if (supportsFilter) sctx.filter = "blur(14px)";

    // 5. Paint synchronized keyboard & trackpad deck shadow veil (256x160, transparent = clear)
    //    y=0 is rear hinge (continuous with bottom of screen), y=SCR_H is front palm rest/trackpad
    dctx.save();
    dctx.clearRect(0, 0, SCR_W, SCR_H);
    if (supportsFilter) dctx.filter = "blur(16px)";

    if (hasWalkers) {
      for (const w of walkers) {
        const edgeFade = Math.min(1, Math.min((w.x + 0.3) / 0.25, (1.3 - w.x) / 0.25));
        const alpha = Math.max(0, edgeFade) * w.opacity * overviewWeight;
        if (alpha <= 0.005) continue;

        const bob = Math.sin(w.bobPhase) * 7;
        const gx = w.x * GOBO_SIZE;
        const gy = GOBO_SIZE * 0.64 + bob;
        drawSilhouette(gctx, gx, gy, w.scale * 1.05, w.lean, Math.min(0.82, alpha * 1.15), 1.15);

        const sx = w.x * SCR_W;
        const sy = SCR_H * 0.72 + bob * 0.35;
        drawSilhouette(sctx, sx, sy, w.scale * 0.48, w.lean * 0.8, alpha * 0.68, 1.05);

        // Elongated continuation across keyboard keys & trackpad, angled subtly along keyLight ray
        const dx = (w.x + 0.03) * SCR_W;
        const dy = SCR_H * 0.56 + bob * 0.25;
        drawSilhouette(dctx, dx, dy, w.scale * 0.52, w.lean * 0.6 - 0.12, alpha * 0.84, 1.35);
      }
    }

    if (hasGazeShadow) {
      // Smoothly sweep a long, looming shadow from left-rear to settle right over the center-left of the MacBook
      const ease = gazeSettle * gazeSettle * (3 - 2 * gazeSettle);
      const breatheX = Math.sin(t * 0.95) * 4.5 * ease;
      const breatheY = Math.sin(t * 1.4 + 0.6) * 3.5 * ease;
      const headLean = -0.14 + 0.06 * ease + Math.sin(t * 0.7) * 0.018 * ease;

      // Sweeps from x = -0.22 -> 0.44 (settling right over the screen & keyboard)
      const normX = THREE.MathUtils.lerp(-0.22, 0.44, ease);
      const gAlpha = Math.min(0.84, ease * 0.78);
      const sAlpha = Math.min(0.56, ease * 0.5);
      const dAlpha = Math.min(0.7, ease * 0.66);

      drawSilhouette(
        gctx,
        normX * GOBO_SIZE + breatheX,
        GOBO_SIZE * 0.68 + breatheY,
        1.24,
        headLean,
        gAlpha,
        1.32,
      );
      drawSilhouette(
        sctx,
        normX * SCR_W + breatheX * 0.45,
        SCR_H * 0.76 + breatheY * 0.4,
        0.58,
        headLean * 0.85,
        sAlpha,
        1.18,
      );
      drawSilhouette(
        dctx,
        (normX + 0.04) * SCR_W + breatheX * 0.45,
        SCR_H * 0.62 + breatheY * 0.35,
        0.64,
        headLean * 0.7 - 0.1,
        dAlpha,
        1.45,
      );
    }

    gctx.restore();
    sctx.restore();
    dctx.restore();
    goboTexture.needsUpdate = true;
    screenTexture.needsUpdate = true;
    deckTexture.needsUpdate = true;
  }

  function isActive() {
    return !wasNeutral || walkers.length > 0 || gazeSettle > 0.01;
  }

  function dispose() {
    goboTexture.dispose();
    screenTexture.dispose();
    deckTexture.dispose();
  }

  return {
    goboTexture,
    screenTexture,
    deckTexture,
    update,
    isActive,
    getGazeBlurTrigger: () => gazeBlurTrigger,
    getGazeSettle: () => gazeSettle,
    dispose,
  };
}
