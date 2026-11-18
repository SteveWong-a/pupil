import * as THREE from "three";
import { KEYS, HERO_KEY, type ArrowDir, type KeyLegendDef } from "./ansiLayout";

export interface ScreenshotAtlas {
  menubarPopover: HTMLImageElement | null;
  screenShield: HTMLImageElement | null;
  settingsGeneral: HTMLImageElement | null;
  settingsGaze: HTMLImageElement | null;
  settingsSensors: HTMLImageElement | null;
  settingsAlarm: HTMLImageElement | null;
}

export interface LegendAtlas {
  texture: THREE.Texture;
  rects: [number, number, number, number][];
}

export interface SurfaceMaps {
  metalNormal: THREE.Texture;
  capNormal: THREE.Texture;
  smudge: THREE.Texture;
  capSmudge: THREE.Texture;
}

export interface SceneAssets {
  legend: LegendAtlas;
  padTexture: THREE.Texture;
  wallpaper: HTMLImageElement | null;
  screenshots: ScreenshotAtlas;
  surface: SurfaceMaps;
}

const SANS_STACK = '"Instrument Sans", -apple-system, BlinkMacSystemFont, sans-serif';

function roundRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  const rad = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rad, y);
  ctx.lineTo(x + w - rad, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + rad);
  ctx.lineTo(x + w, y + h - rad);
  ctx.quadraticCurveTo(x + w, y + h, x + w - rad, y + h);
  ctx.lineTo(x + rad, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - rad);
  ctx.lineTo(x, y + rad);
  ctx.quadraticCurveTo(x, y, x + rad, y);
  ctx.closePath();
}

function drawTriangle(ctx: CanvasRenderingContext2D, pts: [number, number][]) {
  ctx.beginPath();
  ctx.moveTo(pts[0][0], pts[0][1]);
  ctx.lineTo(pts[1][0], pts[1][1]);
  ctx.lineTo(pts[2][0], pts[2][1]);
  ctx.closePath();
  ctx.fill();
}

function drawFunctionIcon(ctx: CanvasRenderingContext2D, fkey: number, ix: number, iy: number) {
  ctx.save();
  ctx.strokeStyle = "#FFFFFF";
  ctx.fillStyle = "#FFFFFF";
  ctx.lineWidth = 1.8;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  switch (fkey) {
    case 1:
    case 2: {
      const r = fkey === 1 ? 2.4 : 3.4;
      const r0 = r + 2.2;
      const r1 = r + (fkey === 1 ? 4.2 : 5.6);
      ctx.beginPath();
      ctx.arc(ix, iy, r, 0, Math.PI * 2);
      ctx.stroke();
      for (let a = 0; a < 8; a++) {
        const ang = (a * Math.PI) / 4;
        ctx.beginPath();
        ctx.moveTo(ix + Math.cos(ang) * r0, iy + Math.sin(ang) * r0);
        ctx.lineTo(ix + Math.cos(ang) * r1, iy + Math.sin(ang) * r1);
        ctx.stroke();
      }
      break;
    }
    case 3: {
      for (const [rx, ry, rw, rh] of [
        [-8, -5, 9, 6],
        [1, -6, 8, 5],
        [-5, 2, 11, 5],
      ]) {
        roundRectPath(ctx, ix + rx, iy + ry, rw, rh, 1.4);
        ctx.stroke();
      }
      break;
    }
    case 4: {
      ctx.beginPath();
      ctx.arc(ix - 1.5, iy - 1.5, 4.8, 0, Math.PI * 2);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(ix + 1.9, iy + 1.9);
      ctx.lineTo(ix + 6, iy + 6);
      ctx.stroke();
      break;
    }
    case 5: {
      roundRectPath(ctx, ix - 2.2, iy - 5.25, 4.4, 7.5, 2.2);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(ix, iy - 1.0, 4.8, 0.15 * Math.PI, 0.85 * Math.PI, false);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(ix, iy + 3.8);
      ctx.lineTo(ix, iy + 6.4);
      ctx.moveTo(ix - 3.2, iy + 6.4);
      ctx.lineTo(ix + 3.2, iy + 6.4);
      ctx.stroke();
      break;
    }
    case 6: {
      // Crescent moon rendered cleanly on a tiny offscreen scratch path via quadratic curves
      ctx.beginPath();
      ctx.arc(ix, iy, 5.5, 0.32 * Math.PI, 1.68 * Math.PI, false);
      ctx.arc(ix + 3.1, iy - 1.6, 4.6, 1.48 * Math.PI, 0.52 * Math.PI, true);
      ctx.closePath();
      ctx.fill();
      break;
    }
    case 7: {
      drawTriangle(ctx, [
        [ix - 7.5, iy],
        [ix - 1.0, iy - 4.2],
        [ix - 1.0, iy + 4.2],
      ]);
      drawTriangle(ctx, [
        [ix - 0.5, iy],
        [ix + 6.0, iy - 4.2],
        [ix + 6.0, iy + 4.2],
      ]);
      break;
    }
    case 8: {
      drawTriangle(ctx, [
        [ix - 6.8, iy - 4.3],
        [ix - 6.8, iy + 4.3],
        [ix + 0.2, iy],
      ]);
      ctx.fillRect(ix + 2.2, iy - 4.0, 2.0, 8.0);
      ctx.fillRect(ix + 5.6, iy - 4.0, 2.0, 8.0);
      break;
    }
    case 9: {
      drawTriangle(ctx, [
        [ix - 6.0, iy - 4.2],
        [ix - 6.0, iy + 4.2],
        [ix + 0.5, iy],
      ]);
      drawTriangle(ctx, [
        [ix + 1.0, iy - 4.2],
        [ix + 1.0, iy + 4.2],
        [ix + 7.5, iy],
      ]);
      break;
    }
    case 10:
    case 11:
    case 12: {
      ctx.beginPath();
      ctx.moveTo(ix - 7.2, iy - 2.3);
      ctx.lineTo(ix - 4.5, iy - 2.3);
      ctx.lineTo(ix - 1.0, iy - 5.2);
      ctx.lineTo(ix - 1.0, iy + 5.2);
      ctx.lineTo(ix - 4.5, iy + 2.3);
      ctx.lineTo(ix - 7.2, iy + 2.3);
      ctx.closePath();
      ctx.fill();
      if (fkey === 11) {
        ctx.beginPath();
        ctx.arc(ix + 0.2, iy, 4.5, -0.35 * Math.PI, 0.35 * Math.PI);
        ctx.stroke();
      } else if (fkey === 12) {
        ctx.beginPath();
        ctx.arc(ix + 0.2, iy, 4.2, -0.35 * Math.PI, 0.35 * Math.PI);
        ctx.stroke();
        ctx.beginPath();
        ctx.arc(ix + 0.2, iy, 7.2, -0.38 * Math.PI, 0.38 * Math.PI);
        ctx.stroke();
      }
      break;
    }
  }
  ctx.restore();
}

function drawArrowGlyph(ctx: CanvasRenderingContext2D, dir: ArrowDir, cx: number, cy: number) {
  const s = 6.5;
  const h = s * 0.85;
  ctx.save();
  ctx.fillStyle = "#FFFFFF";
  if (dir === "left") {
    drawTriangle(ctx, [
      [cx - h, cy],
      [cx + h * 0.65, cy - s * 0.78],
      [cx + h * 0.65, cy + s * 0.78],
    ]);
  } else if (dir === "right") {
    drawTriangle(ctx, [
      [cx + h, cy],
      [cx - h * 0.65, cy - s * 0.78],
      [cx - h * 0.65, cy + s * 0.78],
    ]);
  } else if (dir === "up") {
    drawTriangle(ctx, [
      [cx, cy - h],
      [cx - s * 0.78, cy + h * 0.65],
      [cx + s * 0.78, cy + h * 0.65],
    ]);
  } else {
    drawTriangle(ctx, [
      [cx, cy + h],
      [cx - s * 0.78, cy - h * 0.65],
      [cx + s * 0.78, cy - h * 0.65],
    ]);
  }
  ctx.restore();
}

function drawLegendCell(ctx: CanvasRenderingContext2D, legend: KeyLegendDef, cx0: number, cy0: number, cw: number, ch: number) {
  ctx.save();
  ctx.fillStyle = "#FFFFFF";
  ctx.strokeStyle = "#FFFFFF";

  if (legend.c) {
    ctx.font = `500 34px ${SANS_STACK}`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(legend.c, cx0 + cw / 2, cy0 + ch / 2 + 1);
  }

  if (legend.t !== undefined && legend.b !== undefined) {
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.font = `500 22px ${SANS_STACK}`;
    ctx.fillText(legend.t, cx0 + cw / 2, cy0 + ch * 0.3);
    ctx.font = `500 25px ${SANS_STACK}`;
    ctx.fillText(legend.b, cx0 + cw / 2, cy0 + ch * 0.71);
  }

  if (legend.fkey !== undefined) {
    drawFunctionIcon(ctx, legend.fkey, cx0 + cw / 2, cy0 + ch * 0.36);
    ctx.font = `600 13px ${SANS_STACK}`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(`F${legend.fkey}`, cx0 + cw / 2, cy0 + ch - 10);
  }

  if (legend.arrow) {
    drawArrowGlyph(ctx, legend.arrow, cx0 + cw / 2, cy0 + ch / 2);
  }

  const labelFont = (word: string) => {
    const narrow = word === "control" || word === "option" || word === "command";
    return `500 ${narrow ? "13.5" : "15"}px ${SANS_STACK}`;
  };

  const isSymbol = (s: string) => /^[⌘⌥⌃⇧⇥]$/.test(s);

  if (legend.tl) {
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.font = isSymbol(legend.tl) ? `500 20px ${SANS_STACK}` : labelFont(legend.tl);
    ctx.fillText(legend.tl, cx0 + (isSymbol(legend.tl) ? 12 : 10), cy0 + (isSymbol(legend.tl) ? 11 : 10));
  }
  if (legend.tr) {
    ctx.textAlign = "right";
    ctx.textBaseline = "top";
    ctx.font = isSymbol(legend.tr) ? `500 20px ${SANS_STACK}` : labelFont(legend.tr);
    ctx.fillText(legend.tr, cx0 + cw - (isSymbol(legend.tr) ? 12 : 10), cy0 + (isSymbol(legend.tr) ? 11 : 10));
  }
  if (legend.bl) {
    ctx.textAlign = "left";
    ctx.textBaseline = "bottom";
    ctx.font = isSymbol(legend.bl) ? `500 20px ${SANS_STACK}` : labelFont(legend.bl);
    ctx.fillText(legend.bl, cx0 + (isSymbol(legend.bl) ? 12 : 10), cy0 + ch - 10);
  }
  if (legend.br) {
    ctx.textAlign = "right";
    ctx.textBaseline = "bottom";
    ctx.font = isSymbol(legend.br) ? `500 20px ${SANS_STACK}` : labelFont(legend.br);
    ctx.fillText(legend.br, cx0 + cw - (isSymbol(legend.br) ? 12 : 10), cy0 + ch - 10);
  }
  if (legend.bc) {
    ctx.textAlign = "center";
    ctx.textBaseline = "bottom";
    ctx.font = labelFont(legend.bc);
    ctx.fillText(legend.bc, cx0 + cw / 2, cy0 + ch - 10);
  }

  if (legend.icon === "globe") {
    const gx = cx0 + 18;
    const gy = cy0 + ch - 18;
    const r = 6.8;
    ctx.lineWidth = 1.4;
    ctx.beginPath();
    ctx.arc(gx, gy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(gx - r, gy);
    ctx.lineTo(gx + r, gy);
    ctx.stroke();
    ctx.beginPath();
    ctx.ellipse(gx, gy, 3.4, r, 0, 0, Math.PI * 2);
    ctx.stroke();
  }

  if (legend.led) {
    ctx.fillStyle = "rgba(255, 255, 255, 0.55)";
    ctx.beginPath();
    ctx.arc(cx0 + 14, cy0 + 14, 2.4, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
}

export function createKeyLegendAtlas(): LegendAtlas {
  const PX = 84;
  const W = 2048;
  const H = 1024;
  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext("2d")!;
  ctx.clearRect(0, 0, W, H);

  const rects: [number, number, number, number][] = [];
  let x = 0;
  let y = 0;
  let shelf = 0;

  for (let i = 0; i < KEYS.length; i++) {
    const k = KEYS[i];
    const w = Math.ceil(k.w * PX) + 4;
    const h = Math.ceil(k.d * PX) + 4;
    if (x + w > W) {
      x = 0;
      y += shelf;
      shelf = 0;
    }
    const cx0 = x + 2;
    const cy0 = y + 2;
    const cw = w - 4;
    const ch = h - 4;

    if (i === HERO_KEY) {
      rects.push([0, 0, 0, 0]);
    } else {
      drawLegendCell(ctx, k.legend, cx0, cy0, cw, ch);
      rects.push([cx0 / W, 1 - (cy0 + ch) / H, cw / W, ch / H]);
    }

    x += w;
    shelf = Math.max(shelf, h);
  }

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 16;
  return { texture, rects };
}

export function createBacklightPoolTexture(): THREE.CanvasTexture {
  const S = 256;
  const canvas = document.createElement("canvas");
  canvas.width = S;
  canvas.height = S;
  const ctx = canvas.getContext("2d")!;

  ctx.fillStyle = "#000000";
  ctx.fillRect(0, 0, S, S);

  const radial = ctx.createRadialGradient(S / 2, S / 2, 0, S / 2, S / 2, 124);
  radial.addColorStop(0, "rgba(220, 235, 255, 0.42)");
  radial.addColorStop(0.55, "rgba(220, 235, 255, 0.55)");
  radial.addColorStop(1, "rgba(0, 0, 0, 0)");
  ctx.fillStyle = radial;
  ctx.fillRect(0, 0, S, S);

  roundRectPath(ctx, 24, 24, 208, 208, 42);
  ctx.fillStyle = "rgba(225, 238, 255, 0.45)";
  ctx.fill();

  for (const [lw, alpha] of [
    [36, 0.35],
    [22, 0.75],
    [12, 1.0],
  ] as const) {
    roundRectPath(ctx, 24, 24, 208, 208, 42);
    ctx.strokeStyle = `rgba(240, 247, 255, ${alpha})`;
    ctx.lineWidth = lw;
    ctx.stroke();
  }

  const texture = new THREE.CanvasTexture(canvas);
  texture.anisotropy = 4;
  return texture;
}

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function tileableValueNoise(size: number, period: number, rand: () => number): Float32Array {
  const grid = new Float32Array(period * period);
  for (let i = 0; i < grid.length; i++) grid[i] = rand();
  const out = new Float32Array(size * size);
  const scale = period / size;
  const smooth = (t: number) => t * t * (3 - 2 * t);

  for (let y = 0; y < size; y++) {
    const gy = y * scale;
    const y0 = Math.floor(gy) % period;
    const y1 = (y0 + 1) % period;
    const fy = smooth(gy - Math.floor(gy));
    for (let x = 0; x < size; x++) {
      const gx = x * scale;
      const x0 = Math.floor(gx) % period;
      const x1 = (x0 + 1) % period;
      const fx = smooth(gx - Math.floor(gx));

      const a = grid[y0 * period + x0];
      const b = grid[y0 * period + x1];
      const c = grid[y1 * period + x0];
      const d = grid[y1 * period + x1];
      const top = a + (b - a) * fx;
      const bot = c + (d - c) * fx;
      out[y * size + x] = top + (bot - top) * fy;
    }
  }
  return out;
}

export function createMicroGrainNormalMap(): THREE.DataTexture {
  const S = 512;
  const rand = mulberry32(0x50757069);
  const oct1 = tileableValueNoise(S, 256, rand);
  const oct2 = tileableValueNoise(S, 512, rand);
  const h = new Float32Array(S * S);
  for (let i = 0; i < h.length; i++) h[i] = oct1[i] * 0.6 + oct2[i] * 0.4;

  const data = new Uint8Array(S * S * 4);
  const clampByte = (v: number) => Math.max(0, Math.min(255, Math.round(v)));
  const at = (x: number, y: number) => h[((y + S) % S) * S + ((x + S) % S)];

  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const gx = at(x + 1, y) - at(x - 1, y);
      const gy = at(x, y + 1) - at(x, y - 1);
      const idx = (y * S + x) * 4;
      data[idx] = clampByte(128 + gx * 48);
      data[idx + 1] = clampByte(128 + gy * 48);
      data[idx + 2] = 248;
      data[idx + 3] = 255;
    }
  }

  const tex = new THREE.DataTexture(data, S, S, THREE.RGBAFormat);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.generateMipmaps = true;
  tex.needsUpdate = true;
  return tex;
}

export function createSurfaceWearMap(): THREE.CanvasTexture {
  const S = 512;
  const canvas = document.createElement("canvas");
  canvas.width = S;
  canvas.height = S;
  const ctx = canvas.getContext("2d")!;
  ctx.fillStyle = "#848484";
  ctx.fillRect(0, 0, S, S);

  const rand = mulberry32(0x50757070);
  for (let i = 0; i < 180; i++) {
    const cx = rand() * S;
    const cy = rand() * S;
    const r = 24 + rand() * 56;
    const tone = i % 2 === 0 ? "rgba(155,155,155,0.04)" : "rgba(110,110,110,0.04)";
    for (const ox of [-S, 0, S]) {
      for (const oy of [-S, 0, S]) {
        const px = cx + ox;
        const py = cy + oy;
        if (px + r < 0 || px - r > S || py + r < 0 || py - r > S) continue;
        const grad = ctx.createRadialGradient(px, py, 0, px, py, r);
        grad.addColorStop(0, tone);
        grad.addColorStop(1, "rgba(132,132,132,0)");
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.arc(px, py, r, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  const tex = new THREE.CanvasTexture(canvas);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.anisotropy = 4;
  return tex;
}

export function createStudioEnvironment(renderer: THREE.WebGLRenderer): THREE.Texture {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x000000);
  const softbox = (w: number, h: number, color: number, intensity: number, pos: [number, number, number], look: [number, number, number]) => {
    const m = new THREE.Mesh(
      new THREE.PlaneGeometry(w, h),
      new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(intensity), side: THREE.DoubleSide }),
    );
    m.position.set(...pos);
    m.lookAt(...look);
    scene.add(m);
  };
  softbox(7, 3, 0xf6f8ff, 3.0, [0, 8, -3], [0, 0, 0]);
  softbox(14, 1.6, 0xffffff, 2.2, [0, 6.5, -10], [0, 0, 0]);
  softbox(14, 0.8, 0xffffff, 0.7, [0, 2.2, -10], [0, 0, 0]);
  softbox(2.2, 6, 0xdde6ff, 1.5, [-10, 3, 3], [0, 0, 0]);
  softbox(2.5, 4, 0xe8f0ff, 1.3, [10, 2, -1], [0, 0, 0]);
  softbox(10, 1, 0xffffff, 0.6, [0, 1.5, 11], [0, 0, 0]);
  softbox(40, 40, 0x161a22, 0.35, [0, -8, 0], [0, 0, 0]);

  const pmrem = new THREE.PMREMGenerator(renderer);
  const env = pmrem.fromScene(scene, 0.02).texture;
  pmrem.dispose();
  scene.traverse((o) => {
    if (o instanceof THREE.Mesh) {
      o.geometry.dispose();
      (o.material as THREE.Material).dispose();
    }
  });
  return env;
}

function loadImage(src: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = src;
  });
}

export async function loadSceneAssets(): Promise<SceneAssets> {
  const legend = createKeyLegendAtlas();
  const padTexture = createBacklightPoolTexture();
  const grain = createMicroGrainNormalMap();
  const smudge = createSurfaceWearMap();

  const [wallpaper, menubarPopover, screenShield, settingsGeneral, settingsGaze, settingsSensors, settingsAlarm] = await Promise.all([
    loadImage("./assets/macos-wallpaper.jpg"),
    loadImage("./assets/screenshots/menubar-popover.png"),
    loadImage("./assets/screenshots/screen-shield.png"),
    loadImage("./assets/screenshots/settings-general.png"),
    loadImage("./assets/screenshots/settings-gaze.png"),
    loadImage("./assets/screenshots/settings-sensors.png"),
    loadImage("./assets/screenshots/settings-alarm.png"),
  ]);

  const configureTiled = (tex: THREE.Texture, cm: number) => {
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(1 / cm, 1 / cm);
    tex.needsUpdate = true;
    return tex;
  };

  const surface: SurfaceMaps = {
    metalNormal: configureTiled(grain, 1.6),
    capNormal: configureTiled(grain.clone(), 0.9),
    smudge: configureTiled(smudge, 14),
    capSmudge: configureTiled(smudge.clone(), 6),
  };

  return {
    legend,
    padTexture,
    wallpaper,
    screenshots: {
      menubarPopover,
      screenShield,
      settingsGeneral,
      settingsGaze,
      settingsSensors,
      settingsAlarm,
    },
    surface,
  };
}
