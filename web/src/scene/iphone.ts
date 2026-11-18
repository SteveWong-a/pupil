import * as THREE from "three";
import type { MacBookPose } from "./macbook";
import type { SurfaceMaps } from "./proceduralMaps";
import { createPhoneTexture } from "./phoneTexture";

export const PHONE_W = 7.15;
export const PHONE_D = 14.96;
export const PHONE_H = 0.825;
export const PHONE_R = 1.15;
export const PHONE_POS = new THREE.Vector3(22.2, 0.42, 3.8);
export const PHONE_RY = -0.22;

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

function slab(w: number, d: number, h: number, r: number, bevel = 0, segs = 12, holes: THREE.Path[] = [], bevelSegs = 3) {
  const shape = rrect(new THREE.Shape(), w - 2 * bevel, d - 2 * bevel, Math.max(r - bevel, 0.01), 0, 0);
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

export function createIPhone(surface: SurfaceMaps) {
  const group = new THREE.Group();
  const n2 = (v: number) => new THREE.Vector2(v, v);
  const phoneTex = createPhoneTexture();

  const mats = {
    titanium: new THREE.MeshPhysicalMaterial({
      color: 0x1e1d1b,
      roughness: 0.36,
      metalness: 0.82,
      clearcoat: 0.25,
      clearcoatRoughness: 0.35,
      envMapIntensity: 0.9,
      normalMap: surface.metalNormal,
      normalScale: n2(0.06),
      roughnessMap: surface.smudge,
    }),
    bezel: new THREE.MeshPhysicalMaterial({
      color: 0x050507,
      roughness: 0.1,
      metalness: 0.05,
      clearcoat: 1.0,
      clearcoatRoughness: 0.06,
    }),
    screen: new THREE.MeshPhysicalMaterial({
      map: phoneTex.texture,
      emissive: 0xffffff,
      emissiveMap: phoneTex.texture,
      emissiveIntensity: 0.86,
      roughness: 0.09,
      metalness: 0,
      clearcoat: 1.0,
      clearcoatRoughness: 0.06,
      envMapIntensity: 0.45,
    }),
    sapphire: new THREE.MeshPhysicalMaterial({
      color: 0x090c14,
      roughness: 0.04,
      metalness: 0.1,
      clearcoat: 1.0,
      envMapIntensity: 2.2,
    }),
  };

  // 1. Grade 5 Black Titanium Chassis Unibody Slab
  const bodyMesh = new THREE.Mesh(slab(PHONE_W, PHONE_D, PHONE_H, PHONE_R, 0.065, 16, [], 4), mats.titanium);
  bodyMesh.castShadow = bodyMesh.receiveShadow = true;
  group.add(bodyMesh);

  // 2. Ceramic Shield Front Bezel
  const bezelMesh = new THREE.Mesh(slab(PHONE_W - 0.16, PHONE_D - 0.16, 0.02, PHONE_R - 0.08, 0.005, 16), mats.bezel);
  bezelMesh.position.y = PHONE_H / 2 + 0.004;
  group.add(bezelMesh);

  // 3. Super Retina XDR OLED Display
  const sw = PHONE_W - 0.42;
  const sd = PHONE_D - 0.42;
  const sr = PHONE_R - 0.21;
  const screenShape = rrect(new THREE.Shape(), sw, sd, sr);
  const screenGeo = new THREE.ShapeGeometry(screenShape, 16);
  const pos = screenGeo.attributes.position;
  const uvs = new Float32Array(pos.count * 2);
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const y = pos.getY(i);
    uvs[i * 2] = (x + sw / 2) / sw;
    uvs[i * 2 + 1] = (y + sd / 2) / sd;
  }
  screenGeo.setAttribute("uv", new THREE.BufferAttribute(uvs, 2));
  screenGeo.rotateX(-Math.PI / 2);
  const screenMesh = new THREE.Mesh(screenGeo, mats.screen);
  screenMesh.position.y = PHONE_H / 2 + 0.016;
  group.add(screenMesh);

  // 4. Front Camera Lens & Earpiece Micro-Slit
  const lensMesh = new THREE.Mesh(new THREE.CircleGeometry(0.11, 20).rotateX(-Math.PI / 2), mats.sapphire);
  lensMesh.position.set(0.68, PHONE_H / 2 + 0.019, -PHONE_D / 2 + 0.78);
  const speakerSlit = new THREE.Mesh(slab(0.95, 0.07, 0.008, 0.03), mats.bezel);
  speakerSlit.position.set(0, PHONE_H / 2 + 0.018, -PHONE_D / 2 + 0.24);
  group.add(lensMesh, speakerSlit);

  // 5. Left Titanium Buttons & Right Side Button
  const actionBtn = new THREE.Mesh(slab(0.08, 0.58, 0.18, 0.03, 0.015, 6), mats.titanium);
  actionBtn.position.set(-PHONE_W / 2 - 0.02, 0.02, -3.6);
  const volUp = new THREE.Mesh(slab(0.08, 1.08, 0.18, 0.03, 0.015, 6), mats.titanium);
  volUp.position.set(-PHONE_W / 2 - 0.02, 0.02, -2.3);
  const volDown = new THREE.Mesh(slab(0.08, 1.08, 0.18, 0.03, 0.015, 6), mats.titanium);
  volDown.position.set(-PHONE_W / 2 - 0.02, 0.02, -0.9);
  const powerBtn = new THREE.Mesh(slab(0.08, 1.65, 0.18, 0.03, 0.015, 6), mats.titanium);
  powerBtn.position.set(PHONE_W / 2 + 0.02, 0.02, -1.8);
  group.add(actionBtn, volUp, volDown, powerBtn);

  group.position.copy(PHONE_POS);
  group.rotation.y = PHONE_RY;

  function update(pose: MacBookPose) {
    phoneTex.update(pose);
  }

  function dispose() {
    phoneTex.dispose();
    group.traverse((o) => {
      if (o instanceof THREE.Mesh) o.geometry.dispose();
    });
    for (const m of Object.values(mats)) m.dispose();
  }

  return { group, update, dispose };
}
