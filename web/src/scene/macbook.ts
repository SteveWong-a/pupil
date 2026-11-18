import * as THREE from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import { BODY_D, BODY_W, HERO_KEY, KEYS } from "./ansiLayout";
import { createIPhone, PHONE_H, PHONE_W } from "./iphone";
import type { SceneAssets } from "./proceduralMaps";
import { createScreenTexture } from "./screenTexture";

// CNC-machined 16-inch MacBook Pro unibody (Space Black) with a 1.4mm scissor-switch
// Magic Keyboard, boosted cool-white (#E8F0FF) backlighting, circular Touch ID sensor,
// Force Touch glass trackpad, detachable MagSafe 3 connector, and companion iPhone 16 Pro.
export const SIDE_DECK = 1.6;
export const FRONT_DECK = 8.6;
export const REAR_DECK = 0.45;
export const Z_REAR = -BODY_D / 2 - REAR_DECK;
export const Z_FRONT = BODY_D / 2 + FRONT_DECK;
export const Z_CENTER = (Z_REAR + Z_FRONT) / 2;
export const DECK_W = BODY_W + SIDE_DECK * 2;
export const DECK_D = Z_FRONT - Z_REAR;
export const HINGE_Z = Z_REAR + 0.22;
export const Z_TRACKPAD = BODY_D / 2 + FRONT_DECK * 0.48;

export const LAYERS = {
  lid: { y: 1.76, lift: 9.8 },
  caps: { y: 1.69, lift: 8.6 },
  plate: { y: 1.045, lift: 3.1 },
  base: { y: 0.575, lift: -7.8 },
};
export type LayerName = keyof typeof LAYERS;

export interface MacBookPose {
  lidAngle: number;
  magsafeSlide: number;
  screenMode: number;
  shieldBlur: number;
  countdown: number;
  sirenPulse: number;
  phoneMode: number;
  phonePress: number;
}

export type FeatureId =
  | "gaze-cam"
  | "gaze-notch"
  | "gaze-shield"
  | "tamper-magsafe"
  | "tamper-hinge"
  | "tamper-siren"
  | "phone-push"
  | "phone-disarm"
  | "phone-ble"
  | "macos-touchid"
  | "macos-popover"
  | "macos-settings";

const CAP = { h: 0.14, inset: 0.022, rBot: 0.12, rTop: 0.13, fillet: 0.022, dish: 0.004, wall: 0.04 };
export const CAP_H = CAP.h;
const PLATE_H = 0.15;
const HOVER_LIFT = 0.05;
const PAD_Y = 0.482;

export const BACKLIGHT_WHITE = new THREE.Color(0.91, 0.95, 1.0); // Cool-white #E8F0FF Apple backlight
const CAP_BLACK = new THREE.Color(0x0b0b0e);

/* ------------------------------------------------------------- geometry */

function rrect<P extends THREE.Path>(p: P, w: number, h: number, r: number, cx = 0, cy = 0): P {
  r = Math.min(r, w / 2 - 1e-4, h / 2 - 1e-4);
  const x0 = cx - w / 2;
  const x1 = cx + w / 2;
  const y0 = cy - h / 2;
  const y1 = cy + h / 2;
  p.moveTo(x0 + r, y0);
  p.lineTo(x1 - r, y0);
  p.absarc(x1 - r, y0 + r, r, -Math.PI / 2, 0, false);
  p.lineTo(x1, y1 - r);
  p.absarc(x1 - r, y1 - r, r, 0, Math.PI / 2, false);
  p.lineTo(x0 + r, y1);
  p.absarc(x0 + r, y1 - r, r, Math.PI / 2, Math.PI, false);
  p.lineTo(x0, y0 + r);
  p.absarc(x0 + r, y0 + r, r, Math.PI, Math.PI * 1.5, false);
  return p;
}

function slab(w: number, d: number, h: number, r: number, bevel = 0, segs = 8, holes: THREE.Path[] = [], bevelSegs = 3, cz = 0) {
  const shape = rrect(new THREE.Shape(), w - 2 * bevel, d - 2 * bevel, Math.max(r - bevel, 0.01), 0, -cz);
  shape.holes = holes;
  const depth = h - 2 * bevel;
  const g = new THREE.ExtrudeGeometry(shape, {
    depth,
    bevelEnabled: bevel > 0,
    bevelThickness: bevel,
    bevelSize: bevel,
    bevelSegments: bevel > 0 ? bevelSegs : 0,
    curveSegments: segs,
  });
  g.rotateX(-Math.PI / 2);
  g.translate(0, -depth / 2, 0);
  g.computeVertexNormals();
  return g;
}

const flat = (g: THREE.BufferGeometry) => (g.index ? g.toNonIndexed() : g);
const merge = (list: THREE.BufferGeometry[]) => mergeGeometries(list)!;
const flatPlane = (w = 1, d = 1) => new THREE.PlaneGeometry(w, d).rotateX(-Math.PI / 2);

type P2 = [number, number];
type P3 = [number, number, number];

const PER_CORNER = 5;
function outline(w: number, d: number, r: number): P2[] {
  r = Math.max(0.005, Math.min(r, w / 2 - 1e-3, d / 2 - 1e-3));
  const pts: P2[] = [];
  const cs: P3[] = [
    [w / 2 - r, d / 2 - r, 0],
    [-(w / 2 - r), d / 2 - r, Math.PI / 2],
    [-(w / 2 - r), -(d / 2 - r), Math.PI],
    [w / 2 - r, -(d / 2 - r), Math.PI * 1.5],
  ];
  for (const [cx, cz, a0] of cs) {
    for (let i = 0; i <= PER_CORNER; i++) {
      const a = a0 + (i / PER_CORNER) * (Math.PI / 2);
      pts.push([cx + Math.cos(a) * r, cz + Math.sin(a) * r]);
    }
  }
  return pts;
}

function loft(rings: P3[][], { out = true } = {}) {
  const pos: number[] = [];
  const uvs: number[] = [];
  const idx: number[] = [];
  const starts: number[] = [];
  rings.forEach((ringPts, r) => {
    starts.push(pos.length / 3);
    ringPts.forEach(([x, y, z], i) => {
      pos.push(x, y, z);
      uvs.push(i / ringPts.length, r / (rings.length - 1));
    });
  });
  for (let r = 0; r < rings.length - 1; r++) {
    const A = starts[r];
    const B = starts[r + 1];
    const n = rings[r].length;
    const m = rings[r + 1].length;
    for (let i = 0; i < Math.max(n, m); i++) {
      const a0 = A + (i % n);
      const a1 = A + ((i + 1) % n);
      const b0 = B + (i % m);
      const b1 = B + ((i + 1) % m);
      const tris: P3[] = [];
      if (n > 1) tris.push([a0, b0, a1]);
      if (m > 1) tris.push([a1, b0, b1]);
      for (const [p, q, s] of tris) idx.push(...(out ? [p, q, s] : [p, s, q]));
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g.toNonIndexed();
}

const ring = (pts: P2[], y: number): P3[] => pts.map(([x, z]) => [x, y, z]);
const centre = (y: number): P3[] => [[0, y, 0]];
const dishAt = (x: number, z: number, hw: number, hd: number) => CAP.dish * Math.max(0, 1 - (x / hw) ** 2 - (z / hd) ** 2);

function capGeometry(w: number, d: number) {
  const { h, inset, rBot, rTop, fillet: f, wall } = CAP;
  const wt = w - 2 * inset;
  const dt = d - 2 * inset;
  const rings: P3[][] = [];

  for (let k = 0; k <= 5; k++) {
    const t = k / 5;
    const bulge = 0.012 * Math.sin(Math.PI * t);
    rings.push(ring(outline(w + (wt - w) * t + bulge * 2, d + (dt - d) * t + bulge * 2, rBot + (rTop - rBot) * t), t * (h - f)));
  }
  for (let j = 1; j <= 3; j++) {
    const a = (j / 3) * (Math.PI / 2);
    const s = f * (1 - Math.cos(a));
    rings.push(ring(outline(wt - 2 * s, dt - 2 * s, rTop - s), h - f + f * Math.sin(a)));
  }

  const fw = wt - 2 * f;
  const fd = dt - 2 * f;
  const face = outline(fw, fd, rTop - f);
  for (let m = 1; m <= 4; m++) {
    const s = 1 - m / 5;
    rings.push(face.map(([x, z]): P3 => [x * s, h - dishAt(x * s, z * s, fw / 2, fd / 2), z * s]));
  }
  rings.push(centre(h - CAP.dish));
  const shell = loft(rings, { out: true });

  const iw = w - 2 * wall;
  const id = d - 2 * wall;
  const iwt = wt - 2 * wall;
  const idt = dt - 2 * wall;
  const ceil = h - wall - CAP.dish;
  const inner = loft([ring(outline(iw, id, rBot - wall / 2), 0), ring(outline(iwt, idt, rTop - wall / 2), ceil), centre(ceil)], { out: false });
  const rim = loft([ring(outline(w, d, rBot), 0), ring(outline(iw, id, rBot - wall / 2), 0)], { out: false });

  const g = merge([shell, inner, rim]);
  g.translate(0, -h / 2, 0);
  return g;
}

function legendGeometry() {
  const g = new THREE.PlaneGeometry(1, 1, 10, 10).rotateX(-Math.PI / 2);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) p.setY(i, -dishAt(p.getX(i), p.getZ(i), 0.5, 0.5));
  g.computeVertexNormals();
  return g;
}

/* ------------------------------------------------------------ glow spill */

type SpillUniforms = Record<string, THREE.IUniform>;

function attachBacklightSpill(mat: THREE.Material, kind: "FRAME" | "CAP", uniforms: SpillUniforms) {
  mat.defines = { ...(mat.defines ?? {}), [`SPILL_${kind}`]: "" };
  mat.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, uniforms);
    sh.vertexShader = sh.vertexShader
      .replace("#include <common>", "#include <common>\nuniform mat4 uKbInv;\nvarying vec3 vKbPos;\nvarying vec3 vKbNormal;")
      .replace(
        "#include <worldpos_vertex>",
        `#include <worldpos_vertex>
  mat4 kbM = uKbInv * modelMatrix;
  #ifdef USE_INSTANCING
    kbM = kbM * instanceMatrix;
  #endif
  vKbPos = (kbM * vec4(transformed, 1.0)).xyz;
  vKbNormal = mat3(kbM) * objectNormal;`,
      );
    sh.fragmentShader = sh.fragmentShader
      .replace(
        "#include <common>",
        "#include <common>\nuniform sampler2D glowMap;\nuniform vec2 uGlowSize;\nuniform float uSpill;\nuniform float uCapTop;\nvarying vec3 vKbPos;\nvarying vec3 vKbNormal;",
      )
      .replace(
        "#include <emissivemap_fragment>",
        `#include <emissivemap_fragment>
  {
    vec2 guv = vec2(vKbPos.x / uGlowSize.x + 0.5, 0.5 - vKbPos.z / uGlowSize.y);
    float inWell = 1.0 - smoothstep(0.46, 0.5, max(abs(guv.x - 0.5), abs(guv.y - 0.5)));
    vec3 glow = (texture2D(glowMap, clamp(guv, 0.01, 0.99), 1.0).rgb * 0.55 + texture2D(glowMap, clamp(guv, 0.01, 0.99), 3.5).rgb * 0.9) * inWell;
    vec3 kbN = vKbNormal / max(length(vKbNormal), 1e-4);
    float wall = 1.0 - abs(kbN.y);
    #ifdef SPILL_FRAME
      float f = wall * 0.6 + (1.0 - wall) * 0.12 * step(0.0, kbN.y);
    #else
      float f = (wall * 0.6 + max(-kbN.y, 0.0)) * (1.0 - smoothstep(1.62, uCapTop, vKbPos.y));
    #endif
    totalEmissiveRadiance += glow * f * uSpill;
  }`,
      );
  };
  mat.customProgramCacheKey = () => `spill-${kind}`;
}

/* -------------------------------------------------------------- builder */

export interface KeyState {
  off: THREE.Vector3;
  q: THREE.Quaternion;
  s: number;
  press: number;
  white: number;
  orange: number;
  inner: number;
  led: number;
  hover: number;
  lift: { cap: number; pad: number };
}

export type MacBook = ReturnType<typeof createMacBook>;

export function createMacBook(assets: SceneAssets) {
  const { legend, padTexture, wallpaper, screenshots, surface } = assets;
  const root = new THREE.Group();
  const N = KEYS.length;
  const n2 = (v: number) => new THREE.Vector2(v, v);
  const screenTex = createScreenTexture(wallpaper, screenshots);
  const iphone = createIPhone(surface);
  root.add(iphone.group);

  const mats = {
    cap: new THREE.MeshPhysicalMaterial({
      color: 0xffffff,
      roughness: 0.58,
      metalness: 0,
      clearcoat: 0.08,
      clearcoatRoughness: 0.65,
      sheen: 0.22,
      sheenRoughness: 0.85,
      sheenColor: new THREE.Color(0.42, 0.44, 0.48),
      envMapIntensity: 1.35,
      normalMap: surface.capNormal,
      normalScale: n2(0.05),
      roughnessMap: surface.capSmudge,
    }),
    frame: new THREE.MeshPhysicalMaterial({
      color: 0x08080a,
      roughness: 0.58,
      metalness: 0.45,
      envMapIntensity: 0.5,
      normalMap: surface.metalNormal,
      normalScale: n2(0.06),
      roughnessMap: surface.smudge,
    }),
    base: new THREE.MeshPhysicalMaterial({
      color: 0x1d1a17,
      roughness: 0.44,
      metalness: 0.72,
      envMapIntensity: 0.55,
      normalMap: surface.metalNormal,
      normalScale: n2(0.08),
      roughnessMap: surface.smudge,
    }),
    baseInner: new THREE.MeshStandardMaterial({ color: 0x0e0d0c, roughness: 0.8, metalness: 0.5 }),
    rubber: new THREE.MeshStandardMaterial({ color: 0x0a0a0a, roughness: 0.9 }),
    port: new THREE.MeshBasicMaterial({ color: 0x020202 }),
    cord: new THREE.MeshStandardMaterial({
      color: 0x3b3937,
      roughness: 0.92,
      metalness: 0,
      normalMap: surface.capNormal,
      normalScale: n2(0.4),
    }),
    legend: new THREE.MeshStandardMaterial({
      map: legend.texture,
      color: 0xe6ecf8,
      roughness: 0.55,
      emissive: 0xffffff,
      emissiveMap: legend.texture,
      transparent: true,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -2,
      polygonOffsetUnits: -2,
    }),
    pad: new THREE.MeshBasicMaterial({
      map: padTexture,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    }),
    can: new THREE.MeshStandardMaterial({ color: 0xa6a9ad, roughness: 0.3, metalness: 1 }),
    trackpad: new THREE.MeshPhysicalMaterial({
      color: 0x181512,
      roughness: 0.34,
      metalness: 0.08,
      clearcoat: 0.35,
      clearcoatRoughness: 0.38,
      envMapIntensity: 0.65,
      normalMap: surface.metalNormal,
      normalScale: n2(0.02),
      roughnessMap: surface.smudge,
    }),
    chamfer: new THREE.MeshPhysicalMaterial({
      color: 0x6c6e74,
      roughness: 0.18,
      metalness: 0.92,
      clearcoat: 0.5,
      envMapIntensity: 1.8,
    }),
    sapphire: new THREE.MeshPhysicalMaterial({
      color: 0x07080c,
      roughness: 0.05,
      metalness: 0.05,
      clearcoat: 1.0,
      clearcoatRoughness: 0.04,
      envMapIntensity: 2.2,
    }),
    siliconDie: new THREE.MeshPhysicalMaterial({
      color: 0x161920,
      roughness: 0.06,
      metalness: 0.94,
      clearcoat: 1.0,
      clearcoatRoughness: 0.04,
      envMapIntensity: 2.0,
    }),
    displayBezel: new THREE.MeshPhysicalMaterial({
      color: 0x050507,
      roughness: 0.14,
      metalness: 0.05,
      clearcoat: 0.9,
      clearcoatRoughness: 0.1,
    }),
    screen: new THREE.MeshPhysicalMaterial({
      map: screenTex.texture,
      emissive: 0xffffff,
      emissiveMap: screenTex.texture,
      emissiveIntensity: 0.78,
      roughness: 0.16,
      metalness: 0,
      clearcoat: 0.65,
      clearcoatRoughness: 0.12,
      envMapIntensity: 0.35,
    }),
    magsafeLed: new THREE.MeshBasicMaterial({ color: 0x30d158 }),
    camLed: new THREE.MeshBasicMaterial({ color: 0x30d158 }),
  };

  mats.legend.onBeforeCompile = (sh) => {
    sh.vertexShader = sh.vertexShader
      .replace("#include <common>", "#include <common>\nattribute vec4 aUvRect;")
      .replace("#include <uv_vertex>", "#include <uv_vertex>\nvMapUv = aUvRect.xy + uv * aUvRect.zw;\nvEmissiveMapUv = vMapUv;");
    sh.fragmentShader = sh.fragmentShader
      .replace("#include <color_fragment>", "")
      .replace("#include <emissivemap_fragment>", "#include <emissivemap_fragment>\n#ifdef USE_COLOR\ntotalEmissiveRadiance *= vColor.rgb;\n#endif");
  };

  const spillShared: SpillUniforms = {
    glowMap: { value: null },
    uKbInv: { value: new THREE.Matrix4() },
    uGlowSize: { value: new THREE.Vector2(BODY_W, BODY_D) },
  };
  const spillFrame: SpillUniforms = { ...spillShared, uSpill: { value: 1.95 }, uCapTop: { value: 1.84 } };
  const spillCap: SpillUniforms = { ...spillShared, uSpill: { value: 1.75 }, uCapTop: { value: 1.84 } };
  attachBacklightSpill(mats.frame, "FRAME", spillFrame);
  attachBacklightSpill(mats.cap, "CAP", spillCap);

  const instanced = (geo: THREE.BufferGeometry, mat: THREE.Material, count: number, { shadow = false } = {}) => {
    const m = new THREE.InstancedMesh(geo, mat, count);
    m.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    m.frustumCulled = false;
    m.castShadow = shadow;
    m.receiveShadow = shadow;
    root.add(m);
    return m;
  };

  /* 1. Scissor-switch 1.4 mm keycaps + laser-etched legends */
  const capRefs: { mesh: THREE.InstancedMesh; slot: number }[] = new Array(N);
  const bySize = new Map<string, { w: number; d: number; keys: number[] }>();
  KEYS.forEach((k, i) => {
    const id = `${k.w.toFixed(3)}x${k.d.toFixed(3)}`;
    if (!bySize.has(id)) bySize.set(id, { w: k.w, d: k.d, keys: [] });
    bySize.get(id)!.keys.push(i);
  });
  const capMeshes: THREE.InstancedMesh[] = [];
  for (const { w, d, keys: groupKeys } of bySize.values()) {
    const mesh = instanced(capGeometry(w, d), mats.cap, groupKeys.length, { shadow: true });
    groupKeys.forEach((ki, slot) => {
      capRefs[ki] = { mesh, slot };
      mesh.setColorAt(slot, CAP_BLACK);
    });
    capMeshes.push(mesh);
  }

  const legendGeo = legendGeometry();
  const uvRects = new Float32Array(N * 4);
  legend.rects.forEach((r, i) => uvRects.set(r, i * 4));
  legendGeo.setAttribute("aUvRect", new THREE.InstancedBufferAttribute(uvRects, 4));
  const legendMesh = instanced(legendGeo, mats.legend, N);
  legendMesh.renderOrder = 2;

  /* 2. Circular Touch ID metallic ring & sapphire disc on HERO_KEY */
  const touchIdGroup = new THREE.Group();
  const ringShape = new THREE.Shape().absarc(0, 0, 0.3, 0, Math.PI * 2, false);
  const ringHole = new THREE.Path().absarc(0, 0, 0.242, 0, Math.PI * 2, true);
  ringShape.holes.push(ringHole);
  const touchRingGeo = new THREE.ExtrudeGeometry(ringShape, {
    depth: 0.012,
    bevelEnabled: true,
    bevelThickness: 0.0025,
    bevelSize: 0.0025,
    bevelSegments: 2,
    curveSegments: 48,
  });
  touchRingGeo.rotateX(-Math.PI / 2);
  const touchRingMat = new THREE.MeshPhysicalMaterial({
    color: 0xc8d0dc,
    roughness: 0.16,
    metalness: 0.92,
    clearcoat: 0.6,
    emissive: new THREE.Color(0xdbe8ff),
    emissiveIntensity: 0.28,
    envMapIntensity: 2.2,
  });
  const touchRing = new THREE.Mesh(touchRingGeo, touchRingMat);
  touchRing.position.set(0, CAP_H / 2 + 0.003, 0);
  const touchDisc = new THREE.Mesh(new THREE.CylinderGeometry(0.242, 0.242, 0.006, 48), mats.sapphire);
  touchDisc.position.set(0, CAP_H / 2 + 0.004, 0);
  touchIdGroup.add(touchRing, touchDisc);
  root.add(touchIdGroup);

  /* 3. Per-key backlight pools on the anodized well floor */
  const padMesh = instanced(flatPlane(), mats.pad, N);
  padMesh.renderOrder = 1;
  padMesh.layers.enable(1);

  const glowRT = new THREE.WebGLRenderTarget(256, Math.round((256 * BODY_D) / BODY_W), {
    type: THREE.HalfFloatType,
    generateMipmaps: true,
    minFilter: THREE.LinearMipmapLinearFilter,
    magFilter: THREE.LinearFilter,
    depthBuffer: false,
  });
  spillShared.glowMap.value = glowRT.texture;
  const glowCam = new THREE.OrthographicCamera(-BODY_W / 2, BODY_W / 2, BODY_D / 2, -BODY_D / 2, 0.1, 40);
  glowCam.up.set(0, 0, -1);
  glowCam.position.set(0, 20, 0);
  glowCam.lookAt(0, 0, 0);
  glowCam.layers.set(1);
  root.add(glowCam);

  /* 4. Anodized keyboard well plate, palm-rest deck, Force Touch trackpad & 648 speaker dots */
  const PW = BODY_W - 1.1;
  const PD = BODY_D - 1.1;
  const plateMesh = new THREE.Mesh(slab(PW, PD, PLATE_H, 0.5, 0.02, 5, [], 1), mats.frame);
  plateMesh.castShadow = plateMesh.receiveShadow = true;
  const plate = new THREE.Group().add(plateMesh);

  const wellHole = rrect(new THREE.Path(), BODY_W - 0.82, BODY_D - 0.82, 0.32, 0, 0);
  const deckMesh = new THREE.Mesh(
    slab(DECK_W - 0.35, DECK_D - 0.35, 0.68, 0.82, 0.038, 8, [wellHole], 3, Z_CENTER),
    mats.base,
  );
  deckMesh.position.y = 0.36;
  deckMesh.castShadow = deckMesh.receiveShadow = true;
  plate.add(deckMesh);

  const wellFloor = new THREE.Mesh(slab(BODY_W - 0.8, BODY_D - 0.8, 0.02, 0.32, 0, 6), mats.frame);
  wellFloor.position.y = 1.585 - LAYERS.plate.y;
  wellFloor.receiveShadow = true;
  plate.add(wellFloor);

  // Subtle inter-key grid dividers around the recessed keyboard well perimeter
  const Y_DECK = 0.7;
  const TP_W = 11.4;
  const TP_D = 6.8;
  const TP_R = 0.36;
  const tpRim = new THREE.Mesh(
    slab(TP_W + 0.14, TP_D + 0.14, 0.028, TP_R + 0.04, 0.01, 8, [rrect(new THREE.Path(), TP_W, TP_D, TP_R)], 2),
    mats.chamfer,
  );
  tpRim.position.set(0, Y_DECK + 0.006, Z_TRACKPAD);
  const tpGlass = new THREE.Mesh(slab(TP_W - 0.02, TP_D - 0.02, 0.022, TP_R - 0.01, 0.006, 8), mats.trackpad);
  tpGlass.position.set(0, Y_DECK + 0.002, Z_TRACKPAD);
  tpGlass.receiveShadow = true;
  plate.add(tpRim, tpGlass);

  const grilleDots: THREE.BufferGeometry[] = [];
  for (const sx of [-1, 1]) {
    const gx = sx * (BODY_W / 2 + SIDE_DECK * 0.42);
    for (let c = 0; c < 6; c++) {
      for (let r = 0; r < 54; r++) {
        const dx = (c - 2.5) * 0.145;
        const dz = (r - 26.5) * 0.178;
        grilleDots.push(new THREE.CylinderGeometry(0.032, 0.032, 0.012, 8).translate(gx + dx, Y_DECK + 0.002, dz));
      }
    }
  }
  const grilleMesh = new THREE.Mesh(merge(grilleDots.map(flat)), mats.port);
  plate.add(grilleMesh);

  /* 5. Lower CNC unibody enclosure, front thumb scoop, 4 feet, left ports & detachable MagSafe 3 */
  const base = new THREE.Group();
  const CASE_H = 1.15;
  const walls = new THREE.Mesh(
    slab(DECK_W, DECK_D, CASE_H, 0.9, 0.045, 8, [rrect(new THREE.Path(), DECK_W - 0.9, DECK_D - 0.9, 0.5, 0, -Z_CENTER)], 3, Z_CENTER),
    mats.base,
  );
  const floor = new THREE.Mesh(slab(DECK_W - 0.4, DECK_D - 0.4, 0.15, 0.72, 0, 8, [], 1, Z_CENTER), mats.baseInner);
  floor.position.y = -CASE_H / 2 + 0.075;
  const scoop = new THREE.Mesh(slab(5.2, 0.34, 0.2, 0.14, 0.02), mats.baseInner);
  scoop.position.set(0, CASE_H / 2 - 0.09, Z_FRONT - 0.05);
  base.add(walls, floor, scoop);

  const feet: P2[] = [
    [-13.4, Z_REAR + 2.2],
    [13.4, Z_REAR + 2.2],
    [-13.4, Z_FRONT - 2.2],
    [13.4, Z_FRONT - 2.2],
  ];
  for (const [x, z] of feet) {
    const foot = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.58, 0.06, 24), mats.rubber);
    foot.position.set(x, -CASE_H / 2 - 0.03, z);
    base.add(foot);
  }

  const portX = -DECK_W / 2 - 0.005;
  const magsafePort = new THREE.Mesh(new THREE.ShapeGeometry(rrect(new THREE.Shape(), 1.18, 0.34, 0.12), 8), mats.port);
  magsafePort.rotation.y = -Math.PI / 2;
  magsafePort.position.set(portX, 0.04, -3.8);
  base.add(magsafePort);
  for (const tz of [-1.9, -0.6]) {
    const tbPort = new THREE.Mesh(new THREE.ShapeGeometry(rrect(new THREE.Shape(), 0.74, 0.26, 0.13), 8), mats.port);
    tbPort.rotation.y = -Math.PI / 2;
    tbPort.position.set(portX, 0.04, tz);
    base.add(tbPort);
  }

  const MAGSAFE_X = -DECK_W / 2 - 0.36;
  const magsafe = new THREE.Group();
  const magBody = new THREE.Mesh(slab(0.76, 1.22, 0.36, 0.14, 0.03, 6), mats.base);
  const magTip = new THREE.Mesh(slab(0.22, 1.04, 0.26, 0.08, 0.015, 6), mats.can);
  magTip.position.set(0.4, 0, 0);
  const magLed = new THREE.Mesh(slab(0.14, 0.26, 0.02, 0.05), mats.magsafeLed);
  magLed.position.set(-0.04, 0.185, 0);
  const magBoot = new THREE.Mesh(new THREE.CylinderGeometry(0.125, 0.14, 0.44, 16).rotateZ(Math.PI / 2), mats.rubber);
  magBoot.position.set(-0.56, 0, 0);
  const cordCurve = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-0.75, 0, 0),
    new THREE.Vector3(-2.3, -0.16, 0.25),
    new THREE.Vector3(-4.6, -0.3, 1.1),
    new THREE.Vector3(-7.4, -0.34, 2.7),
  ]);
  const magCord = new THREE.Mesh(new THREE.TubeGeometry(cordCurve, 32, 0.11, 12, false), mats.cord);
  magsafe.add(magBody, magTip, magLed, magBoot, magCord);
  magsafe.position.set(MAGSAFE_X, 0.04, -3.8);
  base.add(magsafe);

  base.traverse((o) => {
    if (o instanceof THREE.Mesh && o.material !== mats.port) {
      o.castShadow = o.receiveShadow = true;
    }
  });

  /* 6. Hinged 16" Liquid Retina XDR display lid */
  const LID_W = DECK_W;
  const LID_H = DECK_D - 0.22;
  const LID_T = 0.26;
  const SCREEN_W = 30.72;
  const SCREEN_H = 19.2;
  const lid = new THREE.Group();
  const lidShellGeo = slab(LID_W, LID_H, LID_T, 0.9, 0.045, 8);
  lidShellGeo.rotateX(Math.PI / 2);
  lidShellGeo.translate(0, LID_H / 2, -LID_T / 2);
  const lidShell = new THREE.Mesh(lidShellGeo, mats.base);
  lidShell.castShadow = lidShell.receiveShadow = true;

  const emblemDisc = new THREE.Mesh(new THREE.CylinderGeometry(1.4, 1.4, 0.012, 48).rotateX(Math.PI / 2), mats.siliconDie);
  emblemDisc.position.set(0, LID_H * 0.52, -LID_T - 0.002);

  const bezelGeo = slab(LID_W - 0.24, LID_H - 0.24, 0.02, 0.78, 0.006, 8);
  bezelGeo.rotateX(Math.PI / 2);
  bezelGeo.translate(0, LID_H / 2, 0.004);
  const lidBezel = new THREE.Mesh(bezelGeo, mats.displayBezel);

  const screenMesh = new THREE.Mesh(new THREE.PlaneGeometry(SCREEN_W, SCREEN_H), mats.screen);
  screenMesh.position.set(0, LID_H / 2 + 0.1, 0.018);

  const notchY = LID_H / 2 + 0.1 + SCREEN_H / 2 - 0.28;
  const camLens = new THREE.Mesh(new THREE.CircleGeometry(0.11, 24), mats.sapphire);
  camLens.position.set(-0.36, notchY, 0.024);
  const camLed = new THREE.Mesh(new THREE.CircleGeometry(0.042, 16), mats.camLed);
  camLed.position.set(0.42, notchY, 0.024);

  const hingeBarrel = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.24, 18.4, 24).rotateZ(Math.PI / 2), mats.baseInner);
  hingeBarrel.position.set(0, 0.06, -0.08);
  hingeBarrel.castShadow = hingeBarrel.receiveShadow = true;
  lid.add(lidShell, emblemDisc, lidBezel, screenMesh, camLens, camLed, hingeBarrel);
  lid.position.set(0, LAYERS.lid.y, HINGE_Z);
  root.add(lid);

  const layerGroups = { plate, base };
  for (const [name, grp] of Object.entries(layerGroups) as [keyof typeof layerGroups, THREE.Group][]) {
    grp.position.y = LAYERS[name].y;
    root.add(grp);
  }

  /* --------------------------------------------------------- live state */

  const keys: KeyState[] = KEYS.map(() => ({
    off: new THREE.Vector3(),
    q: new THREE.Quaternion(),
    s: 1,
    press: 0,
    white: 0,
    orange: 0,
    inner: 1,
    led: 1,
    hover: 0,
    lift: { cap: 0, pad: 0 },
  }));

  const look = { legendGlow: 1, capGlowTop: 1.84 };
  const pose: MacBookPose = {
    lidAngle: 0,
    magsafeSlide: 0,
    screenMode: 0,
    shieldBlur: 0,
    countdown: 15,
    sirenPulse: 0,
    phoneMode: 0,
    phonePress: 0,
  };

  let seed = 3;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647 - 0.5;
  const jitter = KEYS.map(() => ({
    q: new THREE.Quaternion().setFromEuler(new THREE.Euler(rnd() * 0.005, 0, rnd() * 0.005)),
    y: rnd() * 0.004,
  }));

  const m = new THREE.Matrix4();
  const m2 = new THREE.Matrix4();
  const p = new THREE.Vector3();
  const s = new THREE.Vector3();
  const qI = new THREE.Quaternion();
  const qj = new THREE.Quaternion();
  const col = new THREE.Color();
  const clamp01 = (t: number) => Math.min(1, Math.max(0, t));
  const faceInset = CAP.inset + CAP.fillet;
  const plateTop = () => LAYERS.plate.y + PLATE_H / 2;
  const animated = [...capMeshes, legendMesh, padMesh];

  function update() {
    const padBase = plateTop() + PAD_Y;
    for (let i = 0; i < N; i++) {
      const k = KEYS[i];
      const st = keys[i];

      const capY = LAYERS.caps.y + st.lift.cap - st.press + st.hover * HOVER_LIFT;
      p.set(k.x + st.off.x, capY + st.off.y + jitter[i].y, k.z + st.off.z);
      s.setScalar(st.s);
      m.compose(p, qj.copy(st.q).multiply(jitter[i].q), s);
      capRefs[i].mesh.setMatrixAt(capRefs[i].slot, m);

      if (i === HERO_KEY) {
        touchIdGroup.position.copy(p);
        touchIdGroup.quaternion.copy(qj);
        touchIdGroup.scale.copy(s);
      }

      const lScale = i === HERO_KEY ? 0 : 1;
      const lY = CAP_H / 2 + 0.003;
      m2.makeScale((k.w - 2 * faceInset) * lScale, 1, (k.d - 2 * faceInset) * lScale).setPosition(0, lY, 0);
      m2.premultiply(m);
      legendMesh.setMatrixAt(i, m2);

      const g = clamp01(Math.max(st.white, st.orange) * 0.92) * look.legendGlow;
      col.copy(BACKLIGHT_WHITE).multiplyScalar(g * 2.65);
      legendMesh.setColorAt(i, col);

      p.set(k.x, padBase + st.lift.pad, k.z);
      s.set(k.w * 1.18 * st.inner, 1, k.d * 1.22 * st.inner);
      m.compose(p, qI, s);
      padMesh.setMatrixAt(i, m);
      const padGlow = Math.max(st.white, st.orange);
      col.copy(BACKLIGHT_WHITE).multiplyScalar(padGlow * 1.55);
      padMesh.setColorAt(i, col);
    }

    for (const mesh of animated) {
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor && mesh.material !== mats.cap) mesh.instanceColor.needsUpdate = true;
    }

    lid.position.set(0, LAYERS.lid.y, HINGE_Z);
    lid.rotation.x = THREE.MathUtils.lerp(-0.28, Math.PI / 2, pose.lidAngle);
    magsafe.position.set(MAGSAFE_X - pose.magsafeSlide * 3.8, 0.04, -3.8);
    mats.magsafeLed.color.setHex(pose.magsafeSlide > 0.08 ? 0xff453a : 0x30d158);
    mats.camLed.color.setHex(Math.round(pose.screenMode) <= 1 ? 0x30d158 : 0x0b160e);
    screenTex.update(pose);
    iphone.update(pose);

    spillFrame.uSpill.value = 1.95;
    spillCap.uSpill.value = 1.75;
    spillCap.uCapTop.value = look.capGlowTop;
    root.updateMatrixWorld();
  }

  let glowFrame = 0;
  function renderGlow(renderer: THREE.WebGLRenderer, scene: THREE.Scene) {
    (spillShared.uKbInv.value as THREE.Matrix4).copy(root.matrixWorld).invert();
    if (glowFrame++ % 2) return;
    const auto = renderer.shadowMap.autoUpdate;
    const target = renderer.getRenderTarget();
    renderer.shadowMap.autoUpdate = false;
    renderer.setRenderTarget(glowRT);
    renderer.clear();
    renderer.render(scene, glowCam);
    renderer.setRenderTarget(target);
    renderer.shadowMap.autoUpdate = auto;
  }

  const featurePoint = (id: FeatureId, out: THREE.Vector3) => {
    const heroK = KEYS[HERO_KEY];
    switch (id) {
      case "gaze-cam":
        out.set(-0.4, notchY, 0.05);
        lid.localToWorld(out);
        return out;
      case "gaze-notch":
        out.set(-3.2, notchY - 0.45, 0.05);
        lid.localToWorld(out);
        return out;
      case "gaze-shield":
        out.set(-15.0, LID_H * 0.5, 0.05);
        lid.localToWorld(out);
        return out;

      case "tamper-magsafe":
        out.set(MAGSAFE_X - pose.magsafeSlide * 3.8, LAYERS.base.y + 0.1, -3.8);
        return root.localToWorld(out);
      case "tamper-hinge":
        out.set(-DECK_W / 2 + 0.8, LAYERS.lid.y + 2.2, HINGE_Z + 1.2);
        return root.localToWorld(out);
      case "tamper-siren":
        out.set(-(BODY_W / 2 + SIDE_DECK * 0.45), LAYERS.plate.y + Y_DECK + 0.05, 1.4);
        return root.localToWorld(out);

      case "phone-push":
        out.set(PHONE_W / 2 - 0.2, PHONE_H / 2 + 0.05, -2.6);
        iphone.group.localToWorld(out);
        return out;
      case "phone-disarm":
        out.set(PHONE_W / 2 - 0.2, PHONE_H / 2 + 0.05, 1.4);
        iphone.group.localToWorld(out);
        return out;
      case "phone-ble":
        out.set(PHONE_W / 2 - 0.2, PHONE_H / 2 + 0.05, 5.2);
        iphone.group.localToWorld(out);
        return out;

      case "macos-popover":
        out.set(11.8, LID_H * 0.72, 0.05);
        lid.localToWorld(out);
        return out;
      case "macos-settings":
        out.set(4.5, LID_H * 0.44, 0.05);
        lid.localToWorld(out);
        return out;
      case "macos-touchid":
        out.set(heroK.w / 2, CAP_H / 2, 0);
        return touchIdGroup.localToWorld(out);
    }
  };

  function dispose() {
    glowRT.dispose();
    screenTex.dispose();
    iphone.dispose();
    touchRingMat.dispose();
    legend.texture.dispose();
    padTexture.dispose();
    surface.metalNormal.dispose();
    surface.capNormal.dispose();
    surface.smudge.dispose();
    surface.capSmudge.dispose();
    root.traverse((o) => {
      if (o instanceof THREE.Mesh) o.geometry.dispose();
      if (o instanceof THREE.InstancedMesh) o.dispose();
    });
    for (const mat of Object.values(mats)) mat.dispose();
  }

  update();
  return { root, keys, look, pose, update, renderGlow, featurePoint, mats, dispose };
}
