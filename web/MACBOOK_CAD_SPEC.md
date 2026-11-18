# CNC-Machined 16" MacBook Pro Unibody — 3D CAD, PBR Shader & Scroll Choreography Specification

## 0. Architectural Mandate & Visual Fidelity Rules

1. **100% Procedural Mathematical CAD (Vibetyper Standard)**:
   - Every new component (Unibody palm-rest deck, recessed Force Touch glass trackpad, laser-drilled flanking speaker grilles, Touch ID sapphire biometric key ring, Apple Silicon M4 SoC package, detachable CNC MagSafe 3 connector + braided cord, and hinged 16" Liquid Retina XDR display assembly) MUST be constructed using `rrect()`, `slab()`, `outline()`, `loft()`, `ExtrudeGeometry`, `TubeGeometry`, `RingGeometry`, and `CylinderGeometry` with micro-bevels (`0.008–0.045 cm`) that catch `createStudioEnvironment()` softboxes and `N8AOPostPass` contact shadows.
   - **Zero** external `.glb`/`.obj` models and **zero** sci-fi primitives (no translucent cones, no wireframe spheres, no floating HUD rings).
2. **100% Preservation of Vibetyper's 80-Key Mechanical Internals**:
   - Keep `KEYS` (`w`, `d`, `x`, `z` in `web/src/lib/layout.ts`) **unchanged** so `atlasRects()` in `web/src/lib/textures.ts` maps every keycap legend in `legends.png` with zero UV drift.
   - Keep all 80 dished PBT keycaps (`capGeometry`), smoked polycarbonate top housings (`topHousingGeometry`), bottom housings (`bottomHousingGeometry`), stems (`stemGeometry`), steel coil springs (`springGeometry`), Cherry stabilizers (`stabGeometries`), per-key north-facing LEDs/diodes, `light-pool.png` pads, and the `glowRT` mipmap spill shader (`addSpill`).
3. **World-Centimetre UV Tiling**:
   - All aluminium chassis surfaces (`deckMesh`, `walls`, `lidShell`, `magsafeBody`) use `slab()` whose `ExtrudeGeometry` UVs are in world centimetres, paired with `surface.metalNormal` (`grain-normal.png` tiled at `1.6 cm`) and `surface.smudge` (`smudge.png` tiled at `14 cm`).

---

## 1. Layout & Coordinate System (`web/src/lib/layout.ts` & `web/src/lib/keyboard.ts`)

### 1.1 `web/src/lib/layout.ts` Exports
Keep all 80 `KEYS` and their dimensions untouched. Export `rowsWidth`, `rowsDepth`, and `HERO_KEY`:

```ts
export const rowsDepth = ROWS.reduce((s, r) => s + r.h, 0) * U; // 10.545 cm
export const rowsWidth = 14.5 * U;                               // 27.550 cm

// Keyboard well outer bounds (used by glowRT & uGlowSize)
export const BODY_W = rowsWidth + MARGIN * 2;                    // 28.750 cm
export const BODY_D = rowsDepth + MARGIN * 2;                    // 11.745 cm

const indexOf = (id: string) => KEYS.findIndex((k) => k.id === id);
export const VIBE = (["prompt", "talk", "reject", "accept"] as const).map(indexOf);
// Top-right Touch ID / power key (index 13: x = 12.825, z = -4.75, w = 1.52, d = 0.665)
export const HERO_KEY = indexOf("power");                        // 13
export const ACCEPT_INDEX = HERO_KEY;                            // 13 (alias so scroll.ts & labels.ts target Touch ID)
```

### 1.2 Extended 16" MacBook Pro Unibody Constants (`web/src/lib/keyboard.ts`)
The 80-key mechanical keyboard well stays centered at `(x = 0, z = 0)`. The CNC unibody expands laterally by `SIDE_DECK` on left and right for the speaker grilles, and forward (`+z`) by `FRONT_DECK` for the palm rest and Force Touch trackpad:

```ts
export const SIDE_DECK = 1.6;                                    // 16 mm speaker grille deck each side
export const FRONT_DECK = 8.6;                                   // 86 mm palm rest & Force Touch trackpad deck
export const REAR_DECK = 0.45;                                   // 4.5 mm rear hinge deck margin

export const Z_REAR = -BODY_D / 2 - REAR_DECK;                   // -6.3225 cm (rear edge of unibody)
export const Z_FRONT = BODY_D / 2 + FRONT_DECK;                  // +14.4725 cm (front edge of unibody)
export const Z_CENTER = (Z_REAR + Z_FRONT) / 2;                  // +4.0750 cm (Z midpoint of unibody)

export const DECK_W = BODY_W + SIDE_DECK * 2;                    // 31.950 cm (full unibody width)
export const DECK_D = Z_FRONT - Z_REAR;                          // 20.795 cm (full unibody depth)
export const HINGE_Z = Z_REAR + 0.22;                            // -6.1025 cm (lid hinge pivot Z)
export const Z_TRACKPAD = BODY_D / 2 + FRONT_DECK * 0.48;        // +10.000 cm (Force Touch trackpad center Z)
```

### 1.3 Offset-Aware `slab()` Helper (`web/src/lib/keyboard.ts`)
Add an optional `cz = 0` parameter to `slab()` so any unibody layer centered at `Z_CENTER` is generated directly at `z = cz` in 3D space while keeping all `holes` (`plateHoles`, `foamHoles`, etc.) in standard `(x, -z)` root coordinates:

```ts
function slab(
  w: number,
  d: number,
  h: number,
  r: number,
  bevel = 0,
  segs = 8,
  holes: THREE.Path[] = [],
  bevelSegs = 3,
  cz = 0,
) {
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
```

### 1.4 Clamp Backlight Spill to the Keyboard Well (`addSpill` in `web/src/lib/keyboard.ts`)
Keep `uGlowSize` equal to `(BODY_W, BODY_D)` (`28.75 × 11.745 cm`) so `glowRT` resolution is concentrated 100% on the 80 keys. In `addSpill`'s fragment shader replacement, mask out spill outside the keyboard well so the palm rest and speaker grilles never pick up edge-clamped glow:

```glsl
    vec2 guv = vec2(vKbPos.x / uGlowSize.x + 0.5, 0.5 - vKbPos.z / uGlowSize.y);
    float inWell = smoothstep(0.5, 0.46, max(abs(guv.x - 0.5), abs(guv.y - 0.5)));
    vec3 glow = (texture2D(glowMap, clamp(guv, 0.01, 0.99), 1.0).rgb * 0.55
               + texture2D(glowMap, clamp(guv, 0.01, 0.99), 3.5).rgb * 0.9) * inWell;
```

---

## 2. Seven-Layer Stack & Live Pose State (`web/src/lib/keyboard.ts`)

### 2.1 `LAYERS` & `LAYER_ORDER`
Update `LAYERS` and `LAYER_ORDER` to include `lid` at the top of the stack:

```ts
export const LAYERS = {
  lid:     { y: 1.15,  lift: 11.2 }, // Hinged 16" Liquid Retina XDR Display Assembly
  caps:    { y: 1.93,  lift: 8.6  }, // 80-Key Dished PBT Keycaps & Touch ID Ring
  switch:  { y: 1.12,  lift: 5.8  }, // Smoked Polycarbonate Switches & Stabilizers
  plate:   { y: 1.045, lift: 3.1  }, // CNC Unibody Top Deck, Trackpad & Speaker Grilles
  foam:    { y: 0.825, lift: 0.5  }, // Poron & IXPE Acoustic Dampening Shield
  pcb:     { y: 0.60,  lift: -2.3 }, // Apple Silicon M4 Logic Board & ANE
  battery: { y: 0.30,  lift: -5.0 }, // 100Wh Six-Cell Lithium-Polymer Battery Array
  base:    { y: 0.575, lift: -7.8 }, // CNC Unibody Lower Enclosure & MagSafe 3
};
export type LayerName = keyof typeof LAYERS;
export const LAYER_ORDER: LayerName[] = ["lid", "caps", "switch", "plate", "foam", "pcb", "battery", "base"];
```

### 2.2 `pose` State on `Keyboard`
Expose a mutable `pose` object on the returned `kb` instance for the MacBook Pro lid, MagSafe 3 connector, and Retina screen state:

```ts
export interface MacBookPose {
  lidAngle: number;      // 0 = open at 106° (-0.28 rad from vertical), 1 = closed flat (+Math.PI / 2 rad)
  magsafeSlide: number;  // 0 = seated in left port, 1 = detached & slid -3.8 cm along -X
  screenMode: number;    // 0 = Armed desktop, 1 = Gaze Shield blur, 2 = 15s MagSafe countdown, 3 = Lid-slam siren, 4 = Disarmed
  shieldBlur: number;    // 0..1 continuous frost blur intensity on the 3D Retina display
  countdown: number;     // 15..0 seconds shown during Stage 2 tamper grace window
  sirenPulse: number;    // 0..1 crimson/amber pulse intensity during Stage 3 lid-slam escalation
}
```
Initialize `pose`:
```ts
const pose: MacBookPose = {
  lidAngle: 0,
  magsafeSlide: 0,
  screenMode: 0,
  shieldBlur: 0,
  countdown: 15,
  sirenPulse: 0,
};
```

---

## 3. Detailed CAD Geometry for Every New MacBook Pro Component (`web/src/lib/keyboard.ts`)

### 3.1 Additional PBR Materials in `mats`
Add these materials to `mats` inside `createKeyboard`:

```ts
    // Satin glass Force Touch trackpad with finger-oil roughness variation
    trackpad: new THREE.MeshPhysicalMaterial({
      color: 0x181512,
      roughness: 0.24,
      metalness: 0.08,
      clearcoat: 0.55,
      clearcoatRoughness: 0.28,
      envMapIntensity: 1.1,
      normalMap: surface.metalNormal,
      normalScale: n2(0.02),
      roughnessMap: surface.smudge,
    }),
    // Diamond-cut CNC chamfer rim around trackpad & Touch ID ring
    chamfer: new THREE.MeshPhysicalMaterial({
      color: 0x48433e,
      roughness: 0.2,
      metalness: 0.9,
      clearcoat: 0.4,
      envMapIntensity: 1.6,
    }),
    // Recessed dark sapphire crystal lens on Touch ID & camera lens
    sapphire: new THREE.MeshPhysicalMaterial({
      color: 0x07080c,
      roughness: 0.05,
      metalness: 0.05,
      clearcoat: 1.0,
      clearcoatRoughness: 0.04,
      envMapIntensity: 2.2,
    }),
    // Apple Silicon M4 mirror-polished die & rear lid emblem
    siliconDie: new THREE.MeshPhysicalMaterial({
      color: 0x161920,
      roughness: 0.06,
      metalness: 0.94,
      clearcoat: 1.0,
      clearcoatRoughness: 0.04,
      envMapIntensity: 2.0,
    }),
    // Glossy black display glass perimeter bezel
    displayBezel: new THREE.MeshPhysicalMaterial({
      color: 0x050507,
      roughness: 0.14,
      metalness: 0.05,
      clearcoat: 0.9,
      clearcoatRoughness: 0.1,
    }),
    // Active Liquid Retina XDR screen surface
    screen: new THREE.MeshPhysicalMaterial({
      map: screenTex.texture,
      emissive: 0xffffff,
      emissiveMap: screenTex.texture,
      emissiveIntensity: 0.92,
      roughness: 0.12,
      metalness: 0,
      clearcoat: 0.85,
      clearcoatRoughness: 0.08,
      envMapIntensity: 0.5,
    }),
    magsafeLed: new THREE.MeshBasicMaterial({ color: 0x30d158 }),
    camLed: new THREE.MeshBasicMaterial({ color: 0x30d158 }),
```

### 3.2 `plate` Layer: Extended Unibody Top Deck, Recessed Force Touch Trackpad & Speaker Grilles
Keep `plateMesh` (`slab(PW, PD, PLATE_H, 0.5, 0.02, 5, plateHoles, 1)` at `y = 0, z = 0`) as the sunken switch plate. Add to `plate`:

1. **Unibody Palm-Rest & Speaker Top Deck (`deckMesh`)**:
   - Outer dimensions: `w = DECK_W - 0.35` (`31.60 cm`), `d = DECK_D - 0.35` (`20.445 cm`), `h = 0.68 cm`, corner radius `r = 0.82 cm`, bevel `0.038 cm`, `cz = Z_CENTER`.
   - Hole for the sunken 80-key mechanical well:
     `const wellHole = rrect(new THREE.Path(), BODY_W - 0.82, BODY_D - 0.82, 0.32, 0, 0);`
   - Mesh: `const deckMesh = new THREE.Mesh(slab(DECK_W - 0.35, DECK_D - 0.35, 0.68, 0.82, 0.038, 8, [wellHole], 3, Z_CENTER), mats.base);`
   - Position: `deckMesh.position.y = 0.36;` (top surface of palm rest sits at `0.36 + 0.34 = 0.70 cm` in `plate` space, creating a realistic sunken well around the switches and keycaps).
   - Enable shadows: `deckMesh.castShadow = deckMesh.receiveShadow = true; plate.add(deckMesh);`

2. **Recessed Force Touch Glass Trackpad (`Z_TRACKPAD = +10.00 cm`)**:
   - Dimensions: `TP_W = 11.4 cm`, `TP_D = 6.8 cm`, `TP_R = 0.36 cm`, deck top `Y_DECK = 0.70 cm`.
   - **CNC Chamfer Rim (`tpRim`)**:
     `new THREE.Mesh(slab(TP_W + 0.14, TP_D + 0.14, 0.028, TP_R + 0.04, 0.01, 8, [rrect(new THREE.Path(), TP_W, TP_D, TP_R)], 2), mats.chamfer)`
     positioned at `(0, Y_DECK + 0.006, Z_TRACKPAD)`.
   - **Satin Glass Surface (`tpGlass`)**:
     `new THREE.Mesh(slab(TP_W - 0.02, TP_D - 0.02, 0.022, TP_R - 0.01, 0.006, 8), mats.trackpad)`
     positioned at `(0, Y_DECK + 0.002, Z_TRACKPAD)`.
   - `tpGlass.receiveShadow = true; plate.add(tpRim, tpGlass);`

3. **Flanking Laser-Drilled Speaker Grilles (`x = ±14.95 cm`)**:
   - On left (`sx = -1`) and right (`sx = +1`) of the keyboard well, centered at `x = sx * 14.95 cm`, `z = 0`:
   - Build a merged micro-perforation geometry (`6 columns × 54 rows = 324` holes per side, `648` total, pitch `dx = 0.14 cm, dz = 0.175 cm`, each `new THREE.CylinderGeometry(0.032, 0.032, 0.012, 8)`):
     ```ts
     const grilleDots: THREE.BufferGeometry[] = [];
     for (const sx of [-1, 1]) {
       const gx = sx * (BODY_W / 2 + SIDE_DECK * 0.42);
       for (let c = 0; c < 6; c++) {
         for (let r = 0; r < 54; r++) {
           const dx = (c - 2.5) * 0.145;
           const dz = (r - 26.5) * 0.178;
           grilleDots.push(new THREE.CylinderGeometry(0.032, 0.032, 0.012, 8).translate(gx + dx, Y_DECK + 0.004, dz));
         }
       }
     }
     const grilleMesh = new THREE.Mesh(merge(grilleDots.map(flat)), mats.port);
     plate.add(grilleMesh);
     ```

### 3.3 Touch ID Biometric Ring & Sapphire Sensor on `HERO_KEY = 13` (`caps` Layer)
Note: `KEYS[13]` (`id: "power"`, top-right key) has `w = 1.52 cm` and `d = 0.665 cm` (half-height function row). Its top dished plateau is `1.14 × 0.38 cm`.
- Create a `touchIdGroup = new THREE.Group()` added to `root`:
  1. **Diamond-Cut Metallic Biometric Ring (`touchRing`)**:
     `new THREE.Mesh(slab(0.46, 0.46, 0.018, 0.229, 0.005, 12, [rrect(new THREE.Path(), 0.37, 0.37, 0.184)], 2), mats.chamfer)`
     positioned at `(0, CAP_H / 2 - 0.006, 0)`.
  2. **Recessed Dark Sapphire Crystal Sensor Disc (`touchDisc`)**:
     `new THREE.Mesh(new THREE.CylinderGeometry(0.185, 0.185, 0.012, 36), mats.sapphire)`
     positioned at `(0, CAP_H / 2 - 0.010, 0)`.
  3. Add both to `touchIdGroup` (`touchIdGroup.add(touchRing, touchDisc); root.add(touchIdGroup);`).
- Inside `kb.update()`'s per-key loop, when `i === HERO_KEY`:
  - Sync `touchIdGroup` directly to `KEYS[HERO_KEY]`'s composed cap transform `(p, qj, s)`:
    ```ts
    if (i === HERO_KEY) {
      touchIdGroup.position.copy(p);
      touchIdGroup.quaternion.copy(qj);
      touchIdGroup.scale.copy(s);
    }
    ```
  - And scale the legend plane on `HERO_KEY` by `0.55` (`const lScale = i === HERO_KEY ? 0.55 : 1; m2.makeScale((k.w - 2 * faceInset) * lScale, 1, (k.d - 2 * faceInset) * lScale)...`) so the glowing fingerprint glyph sits cleanly inside the `0.37 cm` sapphire sensor!

### 3.4 Expanded `foam`, `pcb` (with Apple Silicon M4 SoC) & `battery` Layers
1. **`foam` Layer**:
   - Keep `foamMesh` (`slab(BODY_W - 1.2, BODY_D - 1.2, 0.25, 0.45, 0, 4, foamHoles)`) under the keyboard well, and add a front palm-rest acoustic shield pad:
     ```ts
     const frontFoam = new THREE.Mesh(slab(DECK_W - 2.2, FRONT_DECK - 1.0, 0.2, 0.45, 0, 4, [], 1, BODY_D / 2 + FRONT_DECK / 2), mats.foam);
     frontFoam.receiveShadow = true;
     foam.add(frontFoam);
     ```
2. **`pcb` Layer (Extended Logic Board + Central Apple Silicon M4 SoC Package)**:
   - Add a front logic board bridge (`slab(DECK_W - 2.4, 3.2, 0.16, 0.4, 0.012, 6, [], 1, BODY_D / 2 + 1.4)` in `mats.pcb`).
   - Add the **Apple Silicon M4 Pro / ANE Package (`socGroup`)** at `(0, 0, 1.2)`:
     - Substrate: `new THREE.Mesh(slab(3.2, 3.2, 0.08, 0.12, 0.015), mats.pcb)` at `(0, 0.11, 1.2)`.
     - Heat-spreader rim: `new THREE.Mesh(slab(2.9, 2.9, 0.04, 0.08, 0.008, 4, [rrect(new THREE.Path(), 2.0, 2.0, 0.05)]), mats.can)` at `(0, 0.15, 1.2)`.
     - Mirror-polished M4 Silicon Die: `new THREE.Mesh(slab(1.96, 1.96, 0.048, 0.04, 0.008), mats.siliconDie)` at `(0, 0.158, 1.2)`.
     - Dual Unified Memory modules: `new THREE.Mesh(slab(0.76, 1.8, 0.044, 0.04, 0.006), mats.chip)` at `(±1.55, 0.148, 1.2)`.
     - Add all to `pcb`.
3. **`battery` Layer (Six-Cell 100Wh Lithium-Polymer Array)**:
   - Keep the 2 rear cells at `x = ±6.7, z = -1.4`.
   - Add 3 front palm-rest pouch cells at `x = -9.4, 0, +9.4` and `z = Z_TRACKPAD` (`+10.0 cm`):
     ```ts
     for (const [bx, bw] of [[-9.4, 8.8], [0, 9.2], [9.4, 8.8]] as [number, number][]) {
       const cell = new THREE.Mesh(slab(bw, 6.2, 0.22, 0.3, 0.035), mats.batteryEdge);
       cell.position.set(bx, 0, Z_TRACKPAD);
       const label = new THREE.Mesh(flatPlane(bw - 0.3, 5.9), mats.battery);
       label.position.set(bx, 0.112, Z_TRACKPAD);
       battery.add(cell, label);
     }
     ```

### 3.5 Extended Unibody `base` Layer, I/O Ports & Detachable CNC MagSafe 3 Connector
1. **Expanded Unibody Tray (`walls` & `floor`)**:
   - Replace `walls` and `floor` in `base` with full `DECK_W × DECK_D` geometry centered at `Z_CENTER`:
     ```ts
     const CASE_H = 1.15;
     const walls = new THREE.Mesh(
       slab(DECK_W, DECK_D, CASE_H, 0.9, 0.045, 8, [rrect(new THREE.Path(), DECK_W - 0.9, DECK_D - 0.9, 0.5, 0, -Z_CENTER)], 3, Z_CENTER),
       mats.base,
     );
     const floor = new THREE.Mesh(slab(DECK_W - 0.4, DECK_D - 0.4, 0.15, 0.72, 0, 8, [], 1, Z_CENTER), mats.baseInner);
     floor.position.y = -CASE_H / 2 + 0.075;
     ```
2. **Front Thumb-Scoop Lip (`scoop`)**:
   - `const scoop = new THREE.Mesh(slab(5.2, 0.34, 0.20, 0.14, 0.02), mats.baseInner);`
   - `scoop.position.set(0, CASE_H / 2 - 0.09, Z_FRONT - 0.05); base.add(scoop);`
3. **4 Machined Rubber Feet**:
   - Place at `[-13.4, Z_REAR + 2.2]`, `[13.4, Z_REAR + 2.2]`, `[-13.4, Z_FRONT - 2.2]`, `[13.4, Z_FRONT - 2.2]`, radius `0.55 cm`, height `0.06 cm` at `y = -CASE_H / 2 - 0.03`.
4. **Left-Side I/O Port Cutouts (`x = -DECK_W / 2 - 0.005`)**:
   - **MagSafe 3 Recessed Socket** at `z = -3.8 cm, y = 0.04`: `new THREE.ShapeGeometry(rrect(new THREE.Shape(), 1.18, 0.34, 0.12), 8)` rotated `rotation.y = -Math.PI / 2`.
   - **2× Thunderbolt 4 (USB-C) Ports** at `z = -1.9 cm` and `z = -0.6 cm, y = 0.04`: `new THREE.ShapeGeometry(rrect(new THREE.Shape(), 0.74, 0.26, 0.13), 8)` rotated `rotation.y = -Math.PI / 2`.
5. **Detachable CNC MagSafe 3 Magnetic Connector (`magsafe` Group inside `base`)**:
   - Home position: `MAGSAFE_X = -DECK_W / 2 - 0.36` (`-16.335 cm`), `y = 0.04`, `z = -3.8 cm`.
   - Sub-meshes inside `magsafe`:
     - **Anodised Aluminium Body**: `new THREE.Mesh(slab(0.76, 1.22, 0.36, 0.14, 0.03, 6), mats.base)` at `(0, 0, 0)`.
     - **Magnetic Contact Tip**: `new THREE.Mesh(slab(0.22, 1.04, 0.26, 0.08, 0.015, 6), mats.can)` at `(+0.40, 0, 0)`.
     - **Status Indicator LED Pill**: `new THREE.Mesh(slab(0.14, 0.26, 0.02, 0.05), mats.magsafeLed)` at `(-0.04, 0.185, 0)`.
     - **Strain-Relief Boot**: `new THREE.Mesh(new THREE.CylinderGeometry(0.125, 0.14, 0.44, 16).rotateZ(Math.PI / 2), mats.rubber)` at `(-0.56, 0, 0)`.
     - **Braided Power Cord (`TubeGeometry`)**:
       ```ts
       const cordCurve = new THREE.CatmullRomCurve3([
         new THREE.Vector3(-0.75, 0, 0),
         new THREE.Vector3(-2.3, -0.16, 0.25),
         new THREE.Vector3(-4.6, -0.30, 1.1),
         new THREE.Vector3(-7.4, -0.34, 2.7),
       ]);
       const cord = new THREE.Mesh(new THREE.TubeGeometry(cordCurve, 32, 0.11, 12, false), mats.foam);
       magsafe.add(cord);
       ```
   - Inside `kb.update()`:
     ```ts
     magsafe.position.set(MAGSAFE_X - pose.magsafeSlide * 3.8, 0.04, -3.8);
     mats.magsafeLed.color.setHex(pose.magsafeSlide > 0.08 ? 0xff453a : 0x30d158);
     ```

### 3.6 Hinged 16" Liquid Retina XDR Display Assembly (`lid` Layer)
Build `lid = new THREE.Group()` in the **upright vertical coordinate system** (origin at the hinge axis `(0, 0, 0)`, `+y` up along the display height `0 .. LID_H`, `+z` forward toward the viewer, `-z` backward):
- Constants:
  - `LID_W = DECK_W` (`31.95 cm`)
  - `LID_H = DECK_D - 0.22` (`20.575 cm`)
  - `LID_T = 0.26 cm`
  - `SCREEN_W = 30.72 cm`, `SCREEN_H = 19.20 cm` (exact `16:10` aspect ratio matching `2048 × 1280`!)
- Meshes inside `lid`:
  1. **CNC Machined Aluminium Outer Shell (`lidShell`)**:
     ```ts
     const lidShellGeo = slab(LID_W, LID_H, LID_T, 0.9, 0.045, 8);
     lidShellGeo.rotateX(Math.PI / 2);
     lidShellGeo.translate(0, LID_H / 2, -LID_T / 2);
     const lidShell = new THREE.Mesh(lidShellGeo, mats.base);
     lidShell.castShadow = lidShell.receiveShadow = true;
     ```
  2. **Rear Mirror-Polished Optic Emblem (`lidEmblem`)**:
     ```ts
     const emblemDisc = new THREE.Mesh(new THREE.CylinderGeometry(1.4, 1.4, 0.012, 48).rotateX(Math.PI / 2), mats.siliconDie);
     emblemDisc.position.set(0, LID_H * 0.52, -LID_T - 0.002);
     ```
  3. **Display Perimeter Glass Bezel (`lidBezel`)**:
     ```ts
     const bezelGeo = slab(LID_W - 0.24, LID_H - 0.24, 0.02, 0.78, 0.006, 8);
     bezelGeo.rotateX(Math.PI / 2);
     bezelGeo.translate(0, LID_H / 2, 0.004);
     const lidBezel = new THREE.Mesh(bezelGeo, mats.displayBezel);
     ```
  4. **Active 16" Liquid Retina XDR Screen (`screenMesh`)**:
     ```ts
     const screenMesh = new THREE.Mesh(new THREE.PlaneGeometry(SCREEN_W, SCREEN_H), mats.screen);
     screenMesh.position.set(0, LID_H / 2 + 0.10, 0.018);
     ```
  5. **Physical Notch Camera Lens & Green Privacy LED**:
     ```ts
     const notchY = LID_H / 2 + 0.10 + SCREEN_H / 2 - 0.28;
     const camLens = new THREE.Mesh(new THREE.CircleGeometry(0.11, 24), mats.sapphire);
     camLens.position.set(-0.36, notchY, 0.024);
     const camLed = new THREE.Mesh(new THREE.CircleGeometry(0.042, 16), mats.camLed);
     camLed.position.set(0.42, notchY, 0.024);
     ```
  6. **Clutched Hinge Barrel (`hingeBarrel`)**:
     ```ts
     const hingeBarrel = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.24, 18.4, 24).rotateZ(Math.PI / 2), mats.baseInner);
     hingeBarrel.position.set(0, 0.06, -0.08);
     lid.add(lidShell, emblemDisc, lidBezel, screenMesh, camLens, camLed, hingeBarrel);
     root.add(lid);
     ```
- **Per-Frame Transform of `lid` inside `kb.update()`**:
  - When `pose.lidAngle === 0` (open at `106°`), `lid.rotation.x = -0.28` rad (`-16°` reclined back from vertical).
  - When `pose.lidAngle === 1` (closed flat onto the palm rest), `lid.rotation.x = +Math.PI / 2` (`+1.5708` rad).
  - During the 7-layer explosion (`explode.lid: 0 → 1`), `lid` lifts vertically by `LAYERS.lid.lift * explode.lid` (`+11.2 cm`):
    ```ts
    lid.position.set(0, LAYERS.lid.y + LAYERS.lid.lift * explode.lid, HINGE_Z);
    lid.rotation.x = THREE.MathUtils.lerp(-0.28, Math.PI / 2, pose.lidAngle);
    screenTex.update(pose);
    ```
- **Label Anchor Corners (`layerCorners` in `web/src/lib/keyboard.ts`)**:
  - Update `layerCorners(name: LayerName)` so `lid` anchors to the mid-height of the display bezel (`y = LAYERS.lid.y + LAYERS.lid.lift * explode.lid + 6.5`, `z = HINGE_Z - 1.5`), and all other layers use `hx = DECK_W / 2 - 0.4`, `hz = DECK_D / 2 - 0.5` centered around `Z_CENTER`!

---

## 4. Retina macOS Display Renderer (`web/src/lib/screenTexture.ts` & `web/src/lib/textures.ts`)

### 4.1 Loading `macos-wallpaper.jpg` in `web/src/lib/textures.ts`
In `loadTextures()`, load `./assets/macos-wallpaper.jpg` as an `HTMLImageElement` (with a safe fallback `null` on error so it never blocks or logs a console error):

```ts
async function loadWallpaper(): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = "./assets/macos-wallpaper.jpg";
  });
}
```
Pass `wallpaper: HTMLImageElement | null` in `KeyboardInputs`.

### 4.2 `createScreenTexture(wallpaper: HTMLImageElement | null)` (`web/src/lib/screenTexture.ts`)
Create a `2048 × 1280` offscreen `<canvas>` wrapped in `new THREE.CanvasTexture(canvas)` (`colorSpace = THREE.SRGBColorSpace`, `anisotropy = 8`).
Cache the last drawn `{ screenMode, shieldBlur, countdown, sirenPulse }` and only redraw + set `texture.needsUpdate = true` when any value changes by `> 0.003`.

Draw layers in `update(pose: MacBookPose)`:
1. **macOS Sequoia Wallpaper & Desktop Window**:
   - Draw `wallpaper` covering `(0, 0, 2048, 1280)` (or rich Sequoia deep-blue/amber geometric canvas fallback if `null`).
   - Draw a crisp dark-mode macOS window (`x = 340, y = 180, w = 1368, h = 820, r = 24`) showing Pupil's live dashboard (`PUPIL HARDWARE SENTINEL · M4 ANE`, `Apple Vision Gaze Monitor: 10.0 FPS · 0 Bytes Saved`, `IOKit Tripwires: MagSafe 3 · Clamshell Lid · HID Lock`, `Owner Disarm: Touch ID · Companion Push · PIN`).
2. **Frosted Privacy Blur (`pose.shieldBlur > 0.01` or `pose.screenMode >= 1 && pose.screenMode < 4`)**:
   - Overlay a dark frosted glass veil (`rgba(8, 10, 16, 0.88 * blurAlpha)`) with subtle horizontal/vertical grid lines and a centered lock card (`w = 920, h = 480, r = 28`):
     - **`screenMode === 1` (Shoulder Surfer Gaze Shield)**:
       - Amber badge `#FF9F0A`: `GAZE DETECTED · PRIVACY SHIELD ACTIVE`
       - Headline: `Screen Blurred in 95ms`
       - Subtitle: `Unrecognized face in camera field · Touch ID required to unblur`
     - **`screenMode === 2` (MagSafe 3 Unplug & 15s Tamper Grace Countdown)**:
       - Amber/Red ring + giant tabular countdown: `15s` (or `${Math.ceil(pose.countdown)}s`)
       - Badge: `⚡ MAGSAFE 3 DISCONNECTED · GRACE WINDOW`
       - Subtitle: `Disarm via Touch ID or iPhone Companion before acoustic siren`
     - **`screenMode === 3` (Lid-Slam Attempt & Progressive Siren)**:
       - Crimson/Ember badge `#FF453A`: `🚨 SLEEP BLOCKED (IOPMAssertion) · SIREN ESCALATING`
       - Animated waveform bars + `30% → 60% → 100% Progressive Library-Safe Siren Active`
       - Subtitle: `RFC 8291 Encrypted Push Dispatched to Owner iPhone`
3. **Retina Top Menu Bar & Physical Notch Pill**:
   - Top bar `(0, 0, 2048, 52)` in `rgba(12, 12, 16, 0.72)`:
     - Left: `   Pupil   File   Edit   Shield   Window`
     - Right: `Wi-Fi   100%  Charged   Tue 9:41 AM`
   - Center **Pupil Notch Pill** (`x = 1024 - 240, y = 0, w = 480, h = 68, r = 22` in `#050507` with glowing status border):
     - Status dot + label:
       - Mode 0: `#30D158` `● ARMED · 10 FPS ANE`
       - Mode 1: `#FF9F0A` `● GAZE SHIELDED`
       - Mode 2: `#FF9F0A` `● UNPLUGGED · 15s GRACE`
       - Mode 3: `#FF453A` `● SIREN ACTIVE · NO SLEEP`
       - Mode 4: `#30D158` `● DISARMED · TOUCH ID`
4. **Bottom macOS Glass Dock**:
   - Rounded dock `(564, 1172, 920, 84, r = 24)` with crisp app icons including the Pupil shield icon.

---

## 5. Camera Rig, Preloader & 12-Unit Scroll Timeline (`flight.ts`, `preloader.ts`, `scroll.ts`, `Labels.tsx`)

### 5.1 `web/src/lib/flight.ts` & `web/src/lib/preloader.ts`
1. In `flight.ts`, update `HERO` so the full open 16" MacBook Pro (display + keyboard well + Force Touch trackpad + left MagSafe 3 connector) is framed cleanly in the hero viewport:
   ```ts
   export const HERO = { target: [0, 7.6, 2.2], az: -0.18, el: 0.22, dist: 62, fov: 30 };
   ```
2. In `preloader.ts`:
   - Initialize `cam` to match `HERO`:
     `Object.assign(cam, { tx: 0, ty: 7.6, tz: 2.2, az: -0.18, el: 0.22, dist: 62, fov: 30, roll: 0, fit: 1, shiftX: 0, shiftY: -0.06, parallax: 0, shake: 0 });`
   - Start `kb.pose.lidAngle = 0.75` during the internal switch-lane flight and smoothly open the display lid to `0` (`106°` open) as the camera pulls back into the hero:
     `tl.to(kb.pose, { lidAngle: 0, duration: 1.4, ease: "power2.out" }, T.out);`
   - Reduce `stage.kbPose.rx` at the end of the preloader from `0.36` to `0.14` (`tl.to(stage.kbPose, { rx: 0.14, ... })`) so the upright 16" Retina display and the keyboard/trackpad deck both read clearly in the hero!

### 5.2 `web/src/lib/scroll.ts` (12-Unit Timeline & Exact Verification Checkpoints)
Ensure the 12-unit timeline hits every single Playwright verification checkpoint (`?p=0`, `?p=0.22`, `?p=0.57`, `?p=0.61`, `?p=0.65`, `?p=0.80`, `?p=1.0`):

1. **7-Layer MacBook Teardown Split (`0.0 → 4.8`, verified at `?p=0.22` / `t = 2.64` & `?p=0.34` / `t = 4.08`)**:
   - `tl.to(stage.kbPose, { rx: 0, duration: 1.4 }, 0);`
   - `tl.to(cam, { tx: 1.2, ty: kbY + 2.6, tz: 2.5, az: -0.44, el: 0.26, dist: 84, fov: 30, shiftX: -0.04, shiftY: 0.02, parallax: 0.5, duration: 1.6 }, 0);`
   - Stagger `LAYER_ORDER` (`lid`, `caps`, `switch`, `plate`, `foam`, `pcb`, `battery`, `base`) so all layers are 100% exploded (`explode[name] === 1`) and `glow.labels === 1` by `t = 2.40` (`?p=0.20`):
     ```ts
     LAYER_ORDER.forEach((name, i) => {
       tl.to(kb.explode, { [name]: 1, duration: 1.5, ease: "power3.inOut" }, 0.35 + i * 0.08);
     });
     tl.to(glow, { labels: 1, duration: 0.01 }, 1.6);
     tl.fromTo(ui.inside, { autoAlpha: 0, y: 30 }, { autoAlpha: 1, y: 0, duration: 0.7, ease: "power3.out" }, 1.7);
     ```
   - At `?p=0.22` (`t = 2.64`), `0.35 + 7 * 0.08 + 1.5 = 2.41 < 2.64`, so every layer has `kb.explode[name] === 1.0`, `glow.labels === 1`, and all 7 left-column leader-line labels are 100% opaque!

2. **Reassemble & 4-Stage Robbery Defense Sequence (`4.8 → 8.35`, verified at `?p=0.57`, `?p=0.61`, `?p=0.65`)**:
   - `4.8 → 6.2`: Close all 8 layers back to `0` (`duration: 1.2, start: 4.85 + i * 0.05`) and frame the complete open MacBook Pro + left MagSafe 3 port + Retina screen:
     ```ts
     tl.to(cam, { tx: -1.2, ty: kbY + 5.0, tz: 2.0, az: -0.28, el: 0.24, dist: 54, shiftX: 0.12, shiftY: 0.01, fit: 0.85, parallax: 0.35, duration: 1.5, ease: "power3.inOut" }, 4.85);
     tl.to(fx, { bokeh: 0.8, focusRange: 28, duration: 1.4 }, 4.9);
     tl.fromTo(ui.vibeCopy, { autoAlpha: 0, y: 30 }, { autoAlpha: 1, y: 0, duration: 0.5, ease: "power3.out" }, 6.2);
     ```
   - **Stage 1 — Shoulder Surfer Gaze Shield (`t = 6.45 → 7.05`, pinned at `?p=0.57` / `t = 6.84`)**:
     - `tl.set(kb.pose, { screenMode: 1 }, 6.45);`
     - `tl.to(kb.pose, { shieldBlur: 1, duration: 0.25, ease: "power2.out" }, 6.45);`
   - **Stage 2 — MagSafe 3 Physical Unplug & 15s Countdown (`t = 7.05 → 7.55`, pinned at `?p=0.61` / `t = 7.32`)**:
     - `tl.set(kb.pose, { screenMode: 2 }, 7.05);`
     - `tl.to(kb.pose, { magsafeSlide: 1, countdown: 15, duration: 0.22, ease: "power2.out" }, 7.05);`
     - `tl.to(cam, { tx: -2.4, az: -0.34, duration: 0.4, ease: "sine.inOut" }, 7.05);`
   - **Stage 3 — Lid-Slam Attempt & Progressive Siren (`t = 7.55 → 8.10`, pinned at `?p=0.65` / `t = 7.80`)**:
     - `tl.set(kb.pose, { screenMode: 3 }, 7.55);`
     - `tl.to(kb.pose, { lidAngle: 0.48, sirenPulse: 1, duration: 0.22, ease: "power2.inOut" }, 7.55);`
   - **Stage 4 — Recovery before Touch ID Macro (`t = 8.10 → 8.40`)**:
     - `tl.to(kb.pose, { lidAngle: 0, magsafeSlide: 0, sirenPulse: 0, duration: 0.28, ease: "power2.inOut" }, 8.10);`

3. **Touch ID Biometric Key 4-Part Macro Split (`8.35 → 10.80`, verified at `?p=0.80` / `t = 9.60` & `?p=0.88` / `t = 10.56`)**:
   - Must be **100% split with `partLabels = 1` and `ui.keyCopy` visible by `t = 9.50` (`p = 0.79`)** so both `?p=0.80` and `?p=0.88` show the full 4-part Touch ID split and its 4 right-column leader callouts:
     ```ts
     tl.to(ui.vibeCopy, { autoAlpha: 0, y: -20, duration: 0.35, ease: "power1.in" }, 8.35);
     tl.to(cam, {
       tx: hero.x + 0.3,
       ty: kbY + 2.3,
       tz: hero.z,
       az: -0.38,
       el: 0.22,
       dist: 10.4,
       shiftX: 0.05,
       shiftY: -0.12,
       fit: 0.32,
       portraitLift: 0.2,
       duration: 0.95,
       ease: "power3.inOut",
     }, 8.4);
     tl.to(fx, { bokeh: 4.2, focusRange: 5.0, duration: 0.9 }, 8.45);
     tl.to(stage, { tilt: 0.25, duration: 0.9 }, 8.45);
     tl.to(heroKey, { parts: 1, duration: 0.01 }, 8.75);
     tl.to(heroKey.lift, { cap: SPLIT.cap, switch: SPLIT.switch, spring: SPLIT.spring, duration: 0.65, ease: "power3.inOut" }, 8.8);
     tl.to(glow, { key: 2.4, duration: 0.6 }, 8.85);
     tl.to(glow, { partLabels: 1, duration: 0.01 }, 9.35);
     tl.fromTo(ui.keyCopy, { autoAlpha: 0, y: 30 }, { autoAlpha: 1, y: 0, duration: 0.45, ease: "power3.out" }, 9.35);
     ```

4. **Final Touch ID Press, Disarm Wave & Unblurred Desktop (`10.85 → 12.0`, verified at `?p=1.0`)**:
   ```ts
   tl.to(glow, { partLabels: 0, duration: 0.01 }, 10.85);
   tl.to(ui.keyCopy, { autoAlpha: 0, y: -20, duration: 0.4, ease: "power1.in" }, 10.85);
   tl.to(heroKey.lift, { cap: 0, switch: 0, spring: 0, duration: 0.55, ease: "power3.inOut" }, 10.9);
   tl.set(kb.pose, { screenMode: 4 }, 11.35);
   tl.to(kb.pose, { shieldBlur: 0, duration: 0.45, ease: "power2.out" }, 11.35);
   tl.to(glow, { press: 0.09, duration: 0.15, ease: "power2.in" }, 11.4);
   tl.to(glow, { wave: 1, duration: 0.5, ease: "none" }, 11.4);
   tl.to(glow, { backlight: 1.2, duration: 0.5 }, 11.4);
   tl.to(cam, { tx: 0, ty: kbY + 4.8, tz: 2.2, az: -0.22, el: 0.26, dist: 58, fit: 0.75, shiftX: 0, shiftY: -0.14, portraitLift: 0, parallax: 1, duration: 1.0, ease: "power2.inOut" }, 10.9);
   tl.to(fx, { bokeh: 1.2, focusRange: 18, duration: 1.0 }, 10.9);
   tl.to(stage, { tilt: 1, duration: 1.0 }, 10.9);
   tl.fromTo(ui.final, { autoAlpha: 0, y: 30, filter: "blur(10px)" }, { autoAlpha: 1, y: 0, filter: "blur(0px)", duration: 0.45, ease: "power3.out" }, 11.5);
   tl.set(heroKey, { parts: 0 }, 11.5);
   ```

### 5.3 Seven Hardware Layer Callouts & Four Touch ID Part Callouts (`web/src/components/Labels.tsx`)
Update `LAYER_LABELS` in `web/src/components/Labels.tsx` so the 7 left-column callouts correspond to the 7 physical MacBook Pro layers (`lid`, `caps`, `switch`, `plate`, `foam`, `pcb`, `base`):

```ts
const LAYER_LABELS: { layer: LayerName; title: string; note: string }[] = [
  { layer: "lid",    title: "Retina Display & Notch",    note: "10 FPS Vision ANE · 95ms privacy blur" },
  { layer: "caps",   title: "80-Key PBT & Touch ID",     note: "Sapphire biometric ring · input lock" },
  { layer: "switch", title: "Mechanical Switch Matrix",  note: "150ms MagSafe, lid & HID tripwires" },
  { layer: "plate",  title: "CNC Unibody & Trackpad",    note: "Force Touch glass · laser speaker grilles" },
  { layer: "foam",   title: "Acoustic & Thermal Shield", note: "10 → 5 → 2 FPS adaptive governor" },
  { layer: "pcb",    title: "Apple Silicon Logic Board", note: "M4 SoC · SHA-256 Wi-Fi · zero cloud" },
  { layer: "base",   title: "100Wh Base & MagSafe 3",    note: "30–100% siren · AES-GCM vault · RFC 8291" },
];

const PART_LABELS: { part: KeyPart; title: string; note: string }[] = [
  { part: "cap",    title: "Sapphire Touch ID Cap",     note: "Sub-second biometric disarm · lockout" },
  { part: "switch", title: "iPhone Companion",          note: "RFC 8291 push · remote disarm & snapshot" },
  { part: "spring", title: "Proximity & Idle",          note: "Walk-away auto-arm · closed-lid sleep safe" },
  { part: "pad",    title: "Quiet Library Mode",        note: "45% cap · 8-second progressive ramp" },
];
```
