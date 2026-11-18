# Pupil — Anti-Vibe-Code Redesign Specification (`REDESIGN_SPEC.md`)

**Owner**: `@design-director` → **Implementation Target**: `@ui-engineer`  
**Files in Scope**: `/Users/stevew/Documents/Pupil/docs/index.html`, `/Users/stevew/Documents/Pupil/docs/styles.css`, `/Users/stevew/Documents/Pupil/docs/app.js`, `/Users/stevew/Documents/Pupil/docs/assets/pupil-icon.png`, `/Users/stevew/Documents/Pupil/docs/assets/macos-wallpaper.jpg`  
**Out of Scope (Do Not Break)**: `./companion.html`, `./manifest.json`, `./sw.js`, inline `<head>` QR/PWA redirect script (`?v=`, `?c=`, `?companion=1`, `standalone`), `WAITLIST_CONFIG` / `WAITLIST_ENDPOINT`.

---

## 1. Core User Directives (#55, #58, #59, #61)

1. **Clean Apple White / Light Theme (`color-scheme: light`) + ZERO CSS Gradients**:
   - Set `<meta name="color-scheme" content="light">`, `<meta name="theme-color" content="#FFFFFF">`, and `:root { color-scheme: light; }`.
   - Remove `@media (prefers-color-scheme: dark)` / dark-default page variables.
   - **Zero CSS gradients (`0` occurrences of `gradient(` in `styles.css`, `index.html`, and `app.js`)**:
     - Canvas background: `#FFFFFF`
     - Elevated cards / panels: `#F5F5F7` (Apple alabaster gray) or `#FFFFFF` with crisp `1px solid #E5E5EA` hairline borders (hover/active border `#D2D2D7` or `#0071E3`)
     - Primary ink: `#1D1D1F`
     - Secondary ink: `#6E6E73`
     - Muted ink: `#86868B`
     - Solid semantic accents: `#0071E3` (Apple blue), `#1D9E34` / `#28CD41` (armed green), `#F56300` (amber warning), `#E30000` / `#FF3B30` (alarm red)
   - Keep the physical **MacBook hardware bezel (`#0A0A0C`)** and **Notch (`#000000`)** authentic black so the hardware stage pops with high contrast against the clean `#FFFFFF` page.

2. **Mockup MacBook Display: Authentic macOS Desktop Wallpaper + Clean Menu Bar & Dock**:
   - Generate `/Users/stevew/Documents/Pupil/docs/assets/macos-wallpaper.jpg` from `/System/Library/Desktop Pictures/` using `sips -Z 1600 -s format jpeg ... --out /Users/stevew/Documents/Pupil/docs/assets/macos-wallpaper.jpg`.
   - Remove the fake Xcode code window (`.mac-app-window`) and CS 4410 Notes card (`.mac-notes-card`) from inside `.macbook-screen`.
   - Instead, `.macbook-screen` displays the real **macOS desktop wallpaper** (`background: #0B132B url("./assets/macos-wallpaper.jpg") center / cover no-repeat;`), a clean macOS top menu bar (`.mac-menubar`), the interactive **MacBook Notch (`#sim-notch`)** in the top center, and a clean **macOS Dock (`.mac-dock`)** at the bottom with minimal vector app tiles—so the user clearly sees the Notch wings expand, the Gaze Warning appear, and the frosted `ScreenShieldView` lock screen blur the real macOS desktop.

3. **De-Emphasize YubiKey — Focus on Touch ID, PIN, & iPhone Proximity**:
   - Do **NOT** make YubiKey a main simulator button, scrollytelling chapter, or Bento card headline.
   - **Simulator Button 5 (`data-scenario="yubikey"` or `"disarm"`)**: Label as **`5. Touch ID / Proximity Disarm`** (unlock modal button: `Unlock with Touch ID / PIN`).
   - **Scrollytelling Chapter 03**: Title **`03 / Touch ID & Proximity Disarm`** (`Instant biometric, PIN, or iPhone proximity unlock.`).
   - **Bento Card 3**: Title **`Touch ID, PIN & Proximity`** (`Sub-second unlock via Touch ID, PIN, or paired iPhone.` — mention optional USB key only as a compact secondary tag `Optional USB Key`).

4. **Drastically Less Text (Visual-First, Minimalist Copy)**:
   - Strip out extra sub-cards, multi-line telemetry tables, and dense spec lists inside the Bento cards and Simulator.
   - Headings: `2–5 words`.
   - Descriptions: `1 short phrase (<= 8–10 words)`.

5. **Sharp Machined Border Radii (`4px / 6px / 8px / 10px`) & Zero Emojis (`100% Vector SVGs`)**:
   - `--radius-xs: 4px` (badges, chips, hotspot pins, progress bars)
   - `--radius-sm: 6px` (buttons, nav bar, tabs, form inputs, persona selectors, icon boxes)
   - `--radius-md: 8px` (Bento cards, scenario cards, inspector card, waitlist/build cards, modals)
   - `--radius-lg: 10px` (outer simulator shell, MacBook/iPhone stages, screenshot showcase frame, sticky story stage)
   - Zero `9999px` pills or `20px+` bubbly corners.
   - Zero emojis (`0` matches for `/[\p{Emoji_Presentation}\p{Extended_Pictographic}]/u` in `index.html` and `app.js`).

6. **Official Pupil Web Icon (#59)**:
   - Copy `/Users/stevew/.gemini/antigravity-cli/brain/0f9523ae-e254-43d7-90ca-bda560ea2f85/.user_uploaded/uploaded_media_1794932014317.png` to `/Users/stevew/Documents/Pupil/docs/assets/pupil-icon.png` (plus `docs/icon-192.png` and `docs/icon-512.png`).
   - Wire `./assets/pupil-icon.png` into `<head>` (`rel="icon"` and `rel="apple-touch-icon"`), top nav `.brand-icon`, and footer brand icon.

---

## 2. Apple Light Tokens & Sharp Radius Scale (`docs/styles.css`)

```css
:root {
  color-scheme: light;

  --u: min(100vw / 1440, 100svh / 900);
  --container-max: 1200px;

  /* 4-Tier Machined Radius System */
  --radius-xs: 4px;
  --radius-sm: 6px;
  --radius-md: 8px;
  --radius-lg: 10px;

  --radius-window: var(--radius-lg);
  --radius-card: var(--radius-md);
  --radius-row: var(--radius-sm);
  --radius-pill: var(--radius-sm);

  /* Clean Apple White / Light Architectural Palette — ZERO GRADIENTS */
  --bg-canvas: #FFFFFF;
  --bg-elevated: #F5F5F7;
  --bg-card: #F5F5F7;
  --bg-card-glass: #F5F5F7;
  --bg-nav-glass: rgba(255, 255, 255, 0.92);
  --bg-row: #FFFFFF;
  --bg-row-hover: #EBEBED;
  --bg-input: #FFFFFF;

  /* Crisp 1px Solid Hairline Borders */
  --border-subtle: #E5E5EA;
  --border-strong: #D2D2D7;
  --highlight-top: inset 0 1px 0 #FFFFFF;
  --shadow-card: 0 8px 24px rgba(0, 0, 0, 0.05);

  /* Apple Ink Hierarchy */
  --text-primary: #1D1D1F;
  --text-secondary: #6E6E73;
  --text-tertiary: #86868B;

  /* Solid Semantic Accents */
  --accent-blue: #0071E3;
  --accent-aqua: #0071E3;
  --armed-green: #1D9E34;
  --warning-amber: #F56300;
  --alarm-red: #E30000;
}
```

---

## 3. Minimalist Copy Table (<= 8–10 Words Per Phrase)

### Hero & Simulator
- **Hero Kicker**: `<span class="hero-kicker-badge">Swift 6 Native</span><span>Zero cloud · MacBook notch sentinel</span>`
- **Hero Title**: `Step away without packing up.`
- **Hero Subtitle**: `On-device gaze blur and hardware tripwires in your notch.` *(9 words)*
- **Simulator Buttons**:
  1. `1. Arm (⌃⌥⌘L)`
  2. `2. Gaze Blur`
  3. `3. Unplug Power`
  4. `4. Unplug Display`
  5. `5. Touch ID / Proximity Disarm`
  6. `6. Progressive Siren`
- **MacBook Stage**:
  - Top `.mac-menubar`: Left (`Finder` · `File` · `Edit` · `View`), Center (`#sim-notch`), Right (`#sim-menubar-power` · `14:22`)
  - Center Desktop: Clean macOS wallpaper (`./assets/macos-wallpaper.jpg`) blurred when `data-blurred="true"`
  - Bottom `.mac-dock`: Clean macOS glass dock bar with 5 crisp vector app icons

### Sticky Scrollytelling Section (`#scroll-story`, `260vh` track)
- **Header**: `Defense Sequence` · `Four layers of physical and optical security.`
- **Chapters**:
  - `01 / GAZE SHIELD` — **Peripheral Gaze Blur** — `Blurs your display in memory when someone peeks.`
  - `02 / HARDWARE TRIPWIRES` — **Cable & Display Lock** — `Triggers immediately on MagSafe unplug, display disconnect, or lid close.`
  - `03 / OWNER DISARM` — **Touch ID & Proximity Disarm** — `Unlocks in under a second via Touch ID, PIN, or iPhone.`
  - `04 / PROGRESSIVE SIREN` — **30% → 100% Library Siren** — `Ramps built-in speakers smoothly over 8 seconds.`

### Bento Grid (`#sensors` — No Cluttered Sub-Tables)
- **Header**: `Native Architecture` · `Built on Apple frameworks.`
- **Card 1**: `VisionGazeDetector` · **On-Device Gaze Blur** — `Instant in-memory screen blur when shoulder surfers look in.` (`10 FPS ANE` · `0B Saved`)
- **Card 2**: `PowerAndLidMonitor` · **Cable & Lid Tripwires** — `Latches on power unplug, display disconnect, or clamshell slam.` (`150ms Poll` · `Sleep Hold`)
- **Card 3**: `LocalAuthentication` · **Touch ID, PIN & Proximity** — `Sub-second disarm with Touch ID, PIN, or paired iPhone.` (`Biometric` · `BLE & Optional USB Key`)
- **Card 4**: `SirenEscalation` · **Trusted Wi-Fi & Library Siren** — `Auto-arms off home Wi-Fi with an 8-second volume ramp.` (`45% Library Cap` · `880/660 Hz`)

### Campus & Cafe Scenarios (`#scenarios`)
- **Card 1**: **The 3-Minute Restroom Run** — `Press ⌃⌥⌘L and walk away. Unplugs wake your iPhone.`
- **Card 2**: **The Crowded Communal Table** — `Peripheral gaze tracking blurs private work in 0.5 seconds.`
- **Card 3**: **Dorm-to-Cafe Wi-Fi Boundary** — `Auto-arms on public Wi-Fi with a gentle 30% siren start.`
