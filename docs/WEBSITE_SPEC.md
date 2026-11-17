# Pupil Official Website & Interactive Simulator — Architectural & Design Specification
<!-- uberdesigner & modern-web-guidance specification · pupil-docs-v1.0.0 -->

## 1. Executive Summary & Deployment Architecture

**Pupil** is a 100% native macOS security sentinel built in **Swift 6, SwiftUI, AppKit, Apple Vision, AVFoundation, IOKit, LocalAuthentication, and CryptoKit**. Designed for **college students studying in libraries or dining halls** and **solo remote workers in coffee shops or coworking spaces**, Pupil lives quietly in the macOS menu bar and physical MacBook notch—guarding against shoulder surfers and opportunistic laptop grab-and-walk theft without Electron bloat (`~18 MB` RAM, `< 3%` CPU).

### 1.1. GitHub Pages Hosting & File Tree
The site is hosted directly from the `docs/` folder on `main` via `.github/workflows/pages.yml` (`actions/upload-pages-artifact` with `path: 'docs'` + `actions/deploy-pages`).

```text
/Users/stevew/Documents/Pupil/
├── .github/
│   └── workflows/
│       └── pages.yml                     # Automated GitHub Pages deployment from docs/ on main
└── docs/
    ├── .nojekyll                         # Prevents Jekyll from stripping underscore/dot assets
    ├── WEBSITE_SPEC.md                   # This architectural & design specification
    ├── CODEBASE_KNOWLEDGE_BASE.md        # Persistent codebase architecture index
    ├── index.html                        # Primary marketing website + Interactive Simulator + Companion PWA router
    ├── companion.html                    # Dedicated standalone iPhone Web Push Companion PWA view
    ├── styles.css                        # Complete design system, tokens, layout, and scroll/motion choreography
    ├── app.js                            # Simulator state machine, WebAudio synth, hotspots, waitlist & PWA bridge
    ├── manifest.json                     # iOS 16.4+ Web Push Home Screen PWA manifest
    ├── sw.js                             # W3C Web Push (RFC 8291) & notification click service worker
    ├── favicon.ico
    ├── icon-32.png
    ├── icon-192.png
    ├── icon-512.png
    ├── apple-touch-icon.png
    └── assets/
        └── screenshots/                  # Real 2x Retina SwiftUI/AppKit captures by @app-photographer
            ├── settings-general.png      # GeneralSettingsPage
            ├── settings-gaze.png         # GazeSettingsPage
            ├── settings-sensors.png      # SensorsSettingsPage
            ├── settings-alarm.png        # AlarmSettingsPage
            ├── menubar-popover.png       # MenuBarPopoverView
            └── screen-shield.png         # ScreenShieldView
```

### 1.2. Preserving the Existing iPhone Web Push Companion PWA (`docs/companion.html` + `docs/index.html`)
`Sources/Pupil/Core/WebPushManager.swift` points its in-app pairing QR code (`companionBaseURL`) to `https://stevewong-a.github.io/pupil/?v=<vapidPublicKey>&c=<pairingChannel>`. To ensure **100% backward compatibility** with the macOS app's QR pairing flow and iOS Home Screen Web Push PWA:

1. **Preserve Companion PWA in `docs/companion.html`**:
   - Copy the complete, working Mobile Sentinel Companion PWA (currently in `docs/index.html`) to `docs/companion.html` (with a subtle top-right link `"← Back to Pupil for Mac"` when viewed in a desktop browser).
2. **Immediate Query-Param Persistence & Auto-Routing in `docs/index.html` / `docs/app.js`**:
   - On page load, before any UI rendering, check `new URLSearchParams(window.location.search)` for `v` (`pupil.vapidPublicKey`), `c` (`pupil.pairingChannel`), or `companion=1`, as well as standalone PWA mode (`window.navigator.standalone === true || window.matchMedia('(display-mode: standalone)').matches`).
   - If `v` or `c` is present in the URL, immediately save them to `localStorage` (`pupil.vapidPublicKey`, `pupil.pairingChannel`) and `caches.open('pupil-pairing-v1')` (`./pairing-config.json`), then either:
     - **Option A (Recommended)**: Redirect via `window.location.replace('./companion.html' + window.location.search)` when `?v=`, `?c=`, `?companion=1`, or `standalone` PWA mode is detected, **OR**
     - **Option B**: Dynamically toggle a built-in `#companion-pwa-drawer` / full-screen Companion view inside `index.html`.
   - Keep `<link rel="manifest" href="./manifest.json">` and `navigator.serviceWorker.register('./sw.js')` active so iOS "Add to Home Screen" works from either `index.html` or `companion.html`.
   - Include a direct `"iPhone Companion PWA"` link (`./companion.html`) in the website's top navigation bar and footer.

---

## 2. UI/UX Reference Research Synthesis

### 2.1. Reference 1: `https://www.tryglance.app/#design` (Notch-Native macOS Utility Craft)
- **Visual Language**: Deep obsidian atmospheric canvas (`#050608`) that makes the black MacBook hardware notch and translucent dark-aqua macOS windows feel physically embedded in the page.
- **Surface Anatomy**: Layered dark glass cards (`#0B0D13` / `#0C0E14`) with `1px solid rgba(255, 255, 255, 0.09)` borders and a crisp `1px` top-edge specular highlight (`box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.14)`).
- **Hardware Notch Choreography**: Concave top-corner ear flares (`NotchShape`) flanking the physical FaceTime camera cutout (`NotchOverlayView` minimal wing mode: `46pt` side wings + `12pt` bottom extension, `14pt` bottom radius), expanding smoothly with spring physics (`cubic-bezier(0.22, 1, 0.36, 1)`).
- **Authentic macOS Settings Chrome**: Unified transparent toolbar with `26px` continuous corner radius, `.sidebar` vibrancy material, `16px`-radius grouped rows (`SettingsGroup`), double-ring option tiles (`SettingsOptionTile` with `2.5px` selection outset), and a floating bottom capsule tab bar (`SettingsTabBar`).

### 2.2. Reference 2: `https://www.apple.com/iphone-duo/` & `https://www.apple.com/` (Apple Product Storytelling)
- **Interactive Hardware Stage**: A sticky/centerpiece MacBook Pro hardware viewport coupled with an adjacent iPhone 16 Pro Web Push companion card. Visitors click tactile scenario pills to drive real-time state transitions across both devices simultaneously.
- **Asymmetric Bento Grid Architecture**: 12-column CSS Grid (`gap: 20px`) combining 7-column hero feature showcases, 5-column technical telemetry cards, and 4-column equal narrative cards—each pairing a single high-impact visual diagram or live readout with concise copy.
- **Tabular Metric Callouts**: High-contrast display numerals (`font-variant-numeric: tabular-nums`) for engineering telemetry: `10 FPS` Vision ANE rate, `~18 MB` RAM footprint, `0.35s` blink immunity, `30% → 100%` 8-second progressive siren ramp, `0 Bytes` written to disk.
- **Floating Glassmorphic Pill Navigation**: Fixed top-center pill (`backdrop-filter: blur(20px) saturate(180%)`) with live system status indicator dot, section anchors, Companion PWA link, and primary `"Join Early Access"` / `"Test Live"` CTA.

---

## 3. Codebase Feature Audit & Storytelling Copy Map

Every claim on the website must accurately reflect the production Swift 6 implementation in `/Users/stevew/Documents/Pupil/Sources/Pupil`:

| Pillar | Production Swift Symbols | Exact Technical Behavior & Student / Cafe Value Proposition |
| :--- | :--- | :--- |
| **1. Notch-Native Sentry & Shoulder-Surfer Gaze Detection** | `NotchOverlayView`, `PupilEyeVectorView`, `NotchShape`, `VisionGazeDetector`, `GazeTemporalAggregator`, `ScreenShieldView` | **Why it matters**: In a crowded coffee shop or lecture hall, strangers sitting beside or behind you can read your code, messages, or grades. <br>**How it works**: Runs Apple `Vision` (`VNDetectFaceRectanglesRequest` + `VNDetectFaceLandmarksRequest` tracking pupil/eye landmarks, yaw, and pitch) 100% on-device in memory. Supports 4 detection cones (`Relaxed 0.75`, `Default 0.65`, `Strict 0.52`, `Ultra 0.40` with 90% wide peripheral ROI) and configurable dwell (`0.5s–3.0s`) with `≤ 350ms` blink tolerance and `> 0.18` L2 walk-by rejection. Triggers a subtle notch wing pill and/or instant full-screen frosted **Screen Content Privacy Blur** (`ScreenShieldView`) that clears automatically when they look away. |
| **2. Physical Hardware Tripwires & Debounced Power Sentry** | `PowerAndLidMonitor`, `ChargerFlapDetector`, `DisplayTopologyEvaluator`, `VisionMotionDetector` | **Why it matters**: When you step away for a 3-minute library restroom run, thieves unplug your MagSafe cable, yank your external monitor USB-C cable, or slam your MacBook lid shut to walk off. <br>**How it works**: Polls `IOPSCopyPowerSourcesInfo` every `150ms`. Includes **`ChargerFlapDetector`** (`≥ 3` power transitions within `6.0s` locks out `revertTamperOnPowerRestored` so cable-jiggling cannot reset the countdown). **`DisplayTopologyEvaluator`** latches external `CGDirectDisplayID`s (ignoring built-in display sleep) and triggers tamper on external monitor hot-unplug. Closing the clamshell lid (`AppleClamshellState`) acquires an `IOPMAssertion` to block macOS sleep and fires the siren immediately. Optional **`VisionMotionDetector`** tracks upper-background homography/translation to catch unplugged open-lid grab-and-walk theft. |
| **3. Zero-Friction Owner Disarming & Brute-Force Lockout** | `KeychainManager`, `PinAttemptLimiter`, `USBKeyDisarmEvaluator`, `USBKeyMonitor`, `USBKeyVault`, `BluetoothProximityMonitor` | **Why it matters**: Disarming your own laptop shouldn't feel like a chore—and an attacker shouldn't be able to guess your PIN. <br>**How it works**: Unlock via **Touch ID** (`LocalAuthentication`), **Salted SHA-256 PIN** (constant-time XOR comparison in `0600` local vault), **Physical USB Security Key / YubiKey Fast Disarm** (`USBKeyDisarmEvaluator` matches enrolled Yubico/Nitrokey/Titan/SoloKeys `VID:PID` + serial number on physical insertion edge), or **Bluetooth Proximity** (`BluetoothProximityMonitor` BLE RSSI hysteresis auto-arms on walk-away and auto-disarms on return). **`PinAttemptLimiter`** enforces exponential backoff: `< 5` allowed, `≥ 5` → `15s` lockout, `≥ 8` → `60s` lockout, `≥ 10` → `300s` lockout + immediate `.escalateToAlarm` (`TamperSource.pinBruteForce`). |
| **4. Context-Aware Auto-Arming (Idle & Trusted Wi-Fi Boundary)** | `IdleInactivityEvaluator`, `TrustedNetworkEvaluator`, `TrustedNetworkMonitor` | **Why it matters**: You shouldn't have to remember to press `⌃⌥⌘L` every time you open your laptop at a cafe or get distracted talking to a classmate. <br>**How it works**: **`IdleInactivityEvaluator`** monitors system HID inactivity (`5, 10, 15, 30 min` stops) with streak suppression and **closed-lid / system sleep immunity** (never false-arms during overnight sleep or Power Nap). **`TrustedNetworkEvaluator`** computes domain-separated SHA-256 fingerprints of your home/dorm Wi-Fi SSID (`pupil.wifi.ssid.v1`), AP BSSID, and router gateway L2 MAC (`pupil.wifi.gwmac.v1`). Leaving a trusted network for public Wi-Fi automatically arms Pupil and/or upgrades gaze sensitivity to `Strict` (`TrustedNetworkPolicyMode`), with **Evil Twin SSID spoofing protection**. |
| **5. Progressive Siren Escalation & Location Environments** | `SirenEscalationEvaluator`, `SirenEscalationProfile`, `SirenSynthesizer`, `SystemAudioController`, `EnvironmentPreset` | **Why it matters**: An accidental cable bump in a silent university library shouldn't humiliate you with an instant 100 dB blast—but a real thief needs an un-mutable deterrent. <br>**How it works**: **`SystemAudioController`** overrides headphone routing to force built-in MacBook speakers and unmutes CoreAudio hardware. **`EnvironmentPreset`** provides 1-tap acoustic ceilings for **Quiet Library (45%)**, **Cafe (80%)**, and **Busy Park (100%)**. **`SirenEscalationEvaluator`** starts the dual-tone `880 Hz / 660 Hz` `AVAudioEngine` square-wave siren at **30% volume** and smoothly (or in 3 discrete steps: `30% → 60% → 100%`) ramps to 100% of your preset over **8.0 seconds**. |
| **6. Encrypted iPhone Companion, Tamper Journal & Adaptive Governor** | `WebPushManager`, `TamperJournalStore`, `AdaptiveVisionGovernor` | **Why it matters**: When you're in the library stacks or ordering at the counter, you need instant lock-screen proof on your iPhone and a tamper-evident incident log. <br>**How it works**: **`WebPushManager`** pairs via a one-time QR code with zero accounts, encrypting payloads on your Mac with `CryptoKit` (`P256.KeyAgreement` ECDH + `HKDF-SHA256` + `AES-128-GCM` per RFC 8291 & VAPID ES256 RFC 8292) and pushing straight to `web.push.apple.com`. Supports HMAC-SHA256 authenticated **Remote Disarm** (`pupildisarm://`) and **Remote Camera Snapshot Ping** (`pupilsnapshot://`). **`TamperJournalStore`** seals up to 200 events in an AES-GCM encrypted ring buffer with 1-click Markdown incident report export. **`AdaptiveVisionGovernor`** scales camera FPS (`10 → 5 → 2 FPS`) based on battery `< 30%` and macOS thermal state. |

---

## 4. Design Tokens, Color Palette & Typography System (`docs/styles.css`)

### 4.1. Color Scheme & CSS Custom Properties
`docs/index.html` MUST include `<meta name="color-scheme" content="dark light">` in `<head>`, and `docs/styles.css` MUST declare `:root { color-scheme: dark light; }` with the primary dark obsidian theme as default and a clean high-contrast light mode media query (`@media (prefers-color-scheme: light)`) that preserves the dark hardware bezel stage while adapting page surfaces cleanly.

```css
:root {
  color-scheme: dark light;

  /* Universal Scaling Unit (--u) & Layout Grid */
  --u: min(100vw / 1440, 100svh / 900);
  --container-max: 1240px;
  --radius-window: 26px;
  --radius-card: 20px;
  --radius-row: 16px;
  --radius-pill: 9999px;

  /* Obsidian Surfaces (Glance + Pupil SettingsMetrics) */
  --bg-canvas: #050608;
  --bg-elevated: #0B0D13;
  --bg-card: #0C0E14;
  --bg-card-glass: rgba(14, 17, 24, 0.76);
  --bg-row: rgba(255, 255, 255, 0.06);
  --bg-row-hover: rgba(255, 255, 255, 0.09);

  /* Specular Borders & Highlights */
  --border-subtle: rgba(255, 255, 255, 0.09);
  --border-strong: rgba(255, 255, 255, 0.16);
  --highlight-top: inset 0 1px 0 rgba(255, 255, 255, 0.14);

  /* Typography Hierarchy */
  --text-primary: #EEEEEE;
  --text-secondary: #BFBFBF;
  --text-tertiary: #8E929F;

  /* Semantic Security State Tokens (SettingsMetrics.swift -> PupilTheme) */
  --accent-blue: #3B82F6;
  --accent-aqua: #0A84FF;
  --armed-green: #30D158;
  --warning-amber: #FF9F0A;
  --alarm-red: #FF453A;

  /* Motion Curves */
  --ease-spring: cubic-bezier(0.22, 1, 0.36, 1);
  --ease-smooth: cubic-bezier(0.44, 0, 0.56, 1);
}
```

### 4.2. Typography & Cap-Height Trimming (`uberdesigner` Pillar 2)
Use native macOS / Apple system display & text stacks with `text-box: trim-both cap alphabetic` and an explicit `@supports not (text-box: trim-both cap alphabetic)` fallback:

```css
:root {
  --font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Inter", system-ui, sans-serif;
  --font-mono: "SF Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
}

.trim,
.trim-display {
  display: block;
  line-height: var(--lh, 1.08);
  text-box: trim-both cap alphabetic;
}

@supports not (text-box: trim-both cap alphabetic) {
  .trim {
    margin-block: calc(0.35em - var(--lh, 1.08) / 2) calc(0.36em - var(--lh, 1.08) / 2);
  }
  .trim-display {
    margin-block: calc(0.344em - var(--lh, 1.08) / 2) calc(0.385em - var(--lh, 1.08) / 2);
  }
}

.tabular {
  font-variant-numeric: tabular-nums;
}
```
> **Rule**: Never apply `display: flex` or `display: grid` directly to an element with `.trim` or `.trim-display`; wrap it in a block span/heading inside the flex/grid item.

---

## 5. Interactive "Test Pupil in Your Browser" Live MacBook Stage (`#simulator`)

The centerpiece of the hero/stage is an interactive dual-device hardware simulator (**MacBook Pro 16" Notch & Screen Stage** + **Paired iPhone 16 Pro Lock-Screen Companion Card**) driven by deterministic state in `docs/app.js`.

### 5.1. Required Scenario Control Pills
Render 6 interactive scenario buttons inside `.simulator-controls` (`role="toolbar" aria-label="Simulate Pupil security scenarios"`). Clicking any button immediately transitions the live stage, updates the telemetry bar, logs an entry in the live simulated event feed, and updates the iPhone companion card:

| Button ID & Label | Simulated State (`data-sim-state`) | MacBook Notch Morph (`#sim-notch`) | Screen Workspace (`#sim-screen`) | Live Telemetry Readouts (`tabular-nums`) | iPhone Companion Card (`#sim-iphone`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. `btn-sim-arm`**<br>*"1. Walk Away & Arm (⌃⌥⌘L)"* | `arming` (2.5s fast demo countdown) → `armed` | Expands to `280px × 44px` wing pill: Amber lock icon + `"Arming • Calibrating room"` → settles into compact glowing green Armed wings (`● Armed • 10 FPS`) | Desktop code/notes workspace remains clear and unblurred; subtle green status badge in menu bar | State: `ARMED` · Vision: `10.0 FPS (ANE)` · Power: `MagSafe AC` · Wi-Fi: `Cafe_Guest (Strict)` | Shows `"Paired • Armed Sentinel Active"` with green lock badge |
| **2. `btn-sim-gaze`**<br>*"2. Shoulder Surfer Gaze"* | `gaze-warning` | Widens to `310px × 46px` with animated `PupilEyeVectorView` reticle tracking peripheral gaze (`Score: 0.78 ≥ 0.52 Strict`) + `"Gaze Detected • Privacy Shield"` | **Instant Frosted Privacy Blur** (`backdrop-filter: blur(22px) saturate(160%)` + obsidian scrim) covers workspace with centered `"Privacy Shield Active — Unauthorized gaze in camera ROI"` capsule | State: `GAZE SHIELD` · Dwell: `2.0s / 2.0s` · Cone: `Ultra (90% ROI)` · Blink filter: `≤350ms` | Advisory badge: `"Shoulder surfer gaze blocked locally (0 bytes stored)"` |
| **3. `btn-sim-magsafe`**<br>*"3. Unplug MagSafe Charger"* | `tamper-magsafe` | Expands to `360px × 52px` amber-bordered tamper pill (`#FF9F0A`): `bolt.slash.fill` + `"Power Unplugged • 15s"` + **Charger Flap Debouncer** badge (`Flap Guard: 3x/6s locked`) | Frosted Screen Shield locks with amber perimeter glow (`3.5px` stroke) + centered macOS authentication modal (`"Tamper detected — 15s"` + PIN / Touch ID prompt) | State: `TAMPER (15s)` · Trigger: `IOPSCopyPowerSourcesInfo` · Flap Guard: `ACTIVE` | Push notification slides in: **"⚠️ Power Unplugged on MacBook Pro"** with `"15s grace countdown started"` |
| **4. `btn-sim-monitor`**<br>*"4. Unplug Library Monitor"* | `tamper-display` | Expands to `360px × 52px` amber-bordered tamper pill: `display.trianglebadge.exclamationmark` + `"External Display Unplugged • 15s"` | Frosted Screen Shield locks with amber perimeter glow + authentication modal showing trigger pill `"External Display Unplugged"` | State: `TAMPER (15s)` · Trigger: `DisplayTopologyEvaluator` · External IDs: `1 → 0` | Push notification slides in: **"⚠️ External Monitor Disconnected"** |
| **5. `btn-sim-yubikey`**<br>*"5. Insert YubiKey / Touch ID"* | `disarmed-yubikey` | Smoothly morphs to green confirmation pill (`checkmark.shield.fill` + `"Disarmed via YubiKey 5C Nano (0x1050:0x0407)"`) then retracts into the physical notch (`184px × 32px`) | Frosted Screen Shield dissolves (`opacity: 0`, `backdrop-filter: blur(0px)`), restoring clear access to the desktop workspace | State: `DISARMED` · Auth: `USBKeyDisarmEvaluator (Serial Pinned)` · Lockout: `0s` | Status updates to `"Disarmed by Owner (Hardware Key)"` |
| **6. `btn-sim-siren`**<br>*"6. Trigger Progressive Siren"* | `alarm-siren` | Expands to `380px × 56px` crimson-bordered alarm pill (`#FF453A`): pulsing `bell.badge.fill` + `"ALARM ACTIVE • 880/660 Hz"` + live volume ramp meter (`30% → 60% → 100%`) | Crimson perimeter alert outline (`4.5px` `#FF453A` with `14px` red glow) + locked PIN challenge modal + **Interactive Environment Preset Switcher** (*Quiet Library 45%*, *Cafe 80%*, *Busy Park 100%*) | State: `ALARM LATCHED` · Ramp: `30% → 100% (8.0s)` · Sleep Hold: `IOPMAssertion ACTIVE` | Critical push banner slides in: **"🚨 SIREN ACTIVE — MacBook Tamper Alarm"** with interactive **"Remote Disarm"** and **"Ping Camera Snapshot"** buttons |

### 5.2. Interactive iPhone Companion Actions & Optional WebAudio Synthesizer
1. **Interactive iPhone Buttons inside the Stage**:
   - Clicking **"Remote Disarm"** (`#btn-iphone-disarm`) inside the simulated iPhone card sends a simulated `pupildisarm://` HMAC-SHA256 signed command, immediately disarming the MacBook stage and clearing the alarm!
   - Clicking **"Ping Camera Snapshot"** (`#btn-iphone-snapshot`) simulates a `pupilsnapshot://` request and renders an on-device verification frame preview inside the iPhone card.
2. **Optional WebAudio Siren & Chirp Synthesizer (`#btn-sim-audio-toggle`)**:
   - Default to **Muted (`Audio Preview: Off`)** so the page never plays unsolicited sound (per ` uberdesigner` Decoupled Media / Silent Demo Clock rule).
   - Provide a clear toggle pill (`"🔊 Hear Real 880/660 Hz Siren Ramp"`). When enabled by the user, use `window.AudioContext` to synthesize Pupil's exact `880 Hz` / `660 Hz` alternating square wave (`0.45s` half-cycle) and apply `SirenEscalationEvaluator`'s exact `0.30 + 0.70 * progress` gain ramp over 8 seconds!

---

## 6. Real-World Student & Solo Worker Narrative Cards (`#scenarios`)

Create a 3-card storytelling section tailored specifically to our target users:

1. **Card 1: The Library Restroom Run** (*For College Students in Campus Libraries & Dining Halls*)
   - **Problem**: Packing up a 16" MacBook Pro, iPad, MagSafe brick, and external monitor cable just for a 3-minute restroom or water-fountain run loses your study carrel and breaks your flow.
   - **Pupil Solution**: Press `⌃⌥⌘L` (or simply walk away with your iPhone/Apple Watch via **Bluetooth Proximity**). Pupil arms MagSafe unplug, external monitor hot-unplug, lid-close sleep-hold, and input lockdown—and pushes encrypted alerts straight to your locked iPhone if anyone touches your setup.
2. **Card 2: The Crowded Coffee Shop Table** (*For Solo Remote Workers & Grad Students*)
   - **Problem**: Communal cafe tables and tight airplane/train seats put strangers right over your shoulder while you review private repositories, financial docs, or exams.
   - **Pupil Solution**: **On-Device Apple Vision Gaze Detection** (`Ultra` 90% peripheral cone) spots sustained eyes on your screen in `0.5s–2.0s` and drops an instant frosted **Screen Content Privacy Blur**—clearing the moment they look away, with zero frames ever saved to disk.
3. **Card 3: The Dorm-to-Cafe Wi-Fi Boundary & Silent Library Etiquette** (*Zero-Config Context Awareness*)
   - **Problem**: Forgetting to arm your laptop when you leave your apartment or dorm—or worrying that an accidental cable bump will blast a 100% siren in a dead-silent reading room.
   - **Pupil Solution**: **Trusted Wi-Fi Boundary Sentinel** (SHA-256 SSID + gateway MAC fingerprinting) automatically arms Pupil and upgrades gaze sensitivity to `Strict` the moment you join public Wi-Fi. And **Quiet Library (45%) + Progressive 8s Siren Escalation** starts any alarm at a gentle 30% ramp so you can tap **Touch ID** or insert your **YubiKey** before it ever reaches full volume.

---

## 7. Real Application Screenshot Showcase & Interactive Hotspot Map (`#screenshots`)

### 7.1. Required Screenshots from `@app-photographer`
`@app-photographer` must generate 6 crisp, non-empty 2x Retina dark-mode PNG screenshots in `/Users/stevew/Documents/Pupil/docs/assets/screenshots/`:

| # | Exact File Path | Source SwiftUI View | Required Visual State in Capture |
| :--- | :--- | :--- | :--- |
| 1 | `docs/assets/screenshots/settings-general.png` | `GeneralSettingsPage` | Dark mode Settings window (`500×620pt` @ 2x) showing Launch at login, Lock on keyboard/mouse, Auto-arm on screen lock, Auto-arm on idle inactivity (`10 minutes` slider visible), Global shortcut (`⌃⌥⌘L`), Gaze detection, Blur screen on gaze, Touch ID, OS hardware lockdown, Behaviour sliders, and Passcode group. |
| 2 | `docs/assets/screenshots/settings-gaze.png` | `GazeSettingsPage` | Dark mode Settings window showing Gaze deterrence, Blur screen on gaze, Adaptive vision frame rate, Style option tiles (`Minimal Pill` vs `Silent Log`), Detection cone slider (`Relaxed`, `Default`, `Strict`, `Ultra`), Dwell duration slider (`2.0 seconds`), and Camera ROI preview card. |
| 3 | `docs/assets/screenshots/settings-sensors.png` | `SensorsSettingsPage` | Dark mode Settings window showing Hardware Triggers tiles (`Power Unplug`, `Lid Close`, `Screen Lock`, `Peripheral Unplug`), External display unplug toggle, Hardware Status readouts, One-Time QR Phone Companion, Bluetooth Proximity, USB Security Key enrollment, and Trusted Wi-Fi section. |
| 4 | `docs/assets/screenshots/settings-alarm.png` | `AlarmSettingsPage` | Dark mode Settings window showing Siren tone (`880 Hz`), Force built-in speakers & unmute, Location environment slider (`Quiet Library · 45%`, `Cafe · 80%`, `Busy Park · 100%`), Progressive siren escalation (`Smooth ramp`), Hold to test button, and Encrypted Activity Log with `Export log` button. |
| 5 | `docs/assets/screenshots/menubar-popover.png` | `MenuBarPopoverView` | Native `250pt`-wide dark menu bar popover showing `● Pupil is armed`, `Power Adapter`, `Disarm Pupil…`, quick toggles (`Gaze deterrence`, `Blur screen on gaze`, `Auto-arm on lock`, `Lock on input`), `Settings… ⌘,`, and `Simulate Tamper`. |
| 6 | `docs/assets/screenshots/screen-shield.png` | `ScreenShieldView` | Frosted obsidian Screen Shield with amber/red perimeter glow and the centered `288pt`-wide macOS authentication card (`PupilEyeVectorView` / alert badge, `Tamper detected — 15s`, PIN input field with Touch ID button, `Unlock` button, and `Forgot PIN?`). |

### 7.2. Interactive Tabbed Showcase & Hotspot Pins (`docs/index.html` + `docs/app.js`)
Embed the 6 real screenshots inside a tabbed macOS showcase container (`#screenshot-showcase`) with 6 tab buttons (`data-screenshot-tab="general|gaze|sensors|alarm|menubar|shield"`). Each tab displays its corresponding `<img>` (with explicit `width`, `height`, `loading="lazy"`, and descriptive `alt` text) plus **3 interactive numbered hotspot pins** (`<button class="hotspot-pin" data-hotspot-id="...">`) overlaid at percentage coordinates `(x%, y%)` that update an adjacent **Feature Inspector Card**:

1. **Tab 1: `General` (`assets/screenshots/settings-general.png`)**:
   - Hotspot 1 (`x: 78%, y: 31%`): **Idle Inactivity Auto-Arm (`5–30 min`)** — Polls `CGEventSource` HID idle time with streak suppression and closed-lid sleep immunity.
   - Hotspot 2 (`x: 78%, y: 54%`): **OS Hardware Lockdown** — Blocks Force Quit, `⌘Tab`, Dock, and Logout while the tamper shield is active.
   - Hotspot 3 (`x: 68%, y: 78%`): **Stepped Exit & Grace Timers (`5s, 10s, 15s, 30s`)** — Gives you time to unplug your own charger or cancel an accidental bump.
2. **Tab 2: `Gaze & AI` (`assets/screenshots/settings-gaze.png`)**:
   - Hotspot 1 (`x: 78%, y: 26%`): **Adaptive Vision Governor (`10 → 5 → 2 FPS`)** — Automatically throttles camera analysis on battery `< 30%` or high thermal state, bursting to `10 FPS` on suspected activity.
   - Hotspot 2 (`x: 52%, y: 42%`): **Notch Deterrent Style Tiles** — Choose between Glance-inspired `Minimal Pill` notch wings or `Silent Log` audit mode.
   - Hotspot 3 (`x: 65%, y: 58%`): **4-Stage Peripheral Cone (`Relaxed` → `Ultra`)** — `Ultra` expands the camera ROI to `90% × 90%` and lowers the score threshold to `0.40` to catch side shoulder-surfers.
3. **Tab 3: `Sensors & Keys` (`assets/screenshots/settings-sensors.png`)**:
   - Hotspot 1 (`x: 50%, y: 16%`): **Hardware Tripwire Tiles + Display Unplug** — Monitors `IOPSCopyPowerSourcesInfo`, `AppleClamshellState`, and `DisplayTopologyEvaluator` external `CGDirectDisplayID`s.
   - Hotspot 2 (`x: 45%, y: 52%`): **One-Time QR Web Push Pairing** — Direct Mac-to-APNs RFC 8291 encrypted push delivery with zero user accounts or third-party servers.
   - Hotspot 3 (`x: 65%, y: 78%`): **YubiKey Fast Disarm & Trusted Wi-Fi Boundary** — Enrolls hardware USB tokens (`VID:PID` + serial) in an AES-GCM vault and hashes trusted Wi-Fi SSIDs/gateway MACs with SHA-256.
4. **Tab 4: `Alarm & Log` (`assets/screenshots/settings-alarm.png`)**:
   - Hotspot 1 (`x: 78%, y: 22%`): **Force Built-In Speakers & Unmute** — Overrides AirPods/headphone routing via `CoreAudio` so a thief cannot silence the MacBook by plugging in a dummy jack.
   - Hotspot 2 (`x: 55%, y: 36%`): **Location Environment Presets** — Instant slider stops for **Quiet Library (45%)**, **Cafe (80%)**, and **Busy Park (100%)**.
   - Hotspot 3 (`x: 65%, y: 48%`): **Progressive 8s Siren Escalation & Encrypted Journal** — Ramps from `30% → 100%` over 8 seconds (`Smooth ramp` or `Stepped`) and logs every event to `tamper-journal.enc.json` with Markdown export.
5. **Tab 5: `Menu Bar` (`assets/screenshots/menubar-popover.png`)**:
   - Hotspot 1 (`x: 50%, y: 12%`): **Live Sentinel Status & Power Readout** — Shows armed state, active countdowns, and AC/Battery status at a glance.
   - Hotspot 2 (`x: 50%, y: 48%`): **1-Click Privacy Toggles** — Toggle Gaze Deterrence, Screen Blur on Gaze, Auto-Arm on Lock, and Input Lockdown directly from `NSStatusBar`.
   - Hotspot 3 (`x: 50%, y: 76%`): **Dockless `.accessory` Architecture** — Zero Dock clutter; opens Settings (`⌘,`) on demand and blocks unauthorized `⌘Q` termination while armed.
6. **Tab 6: `Screen Shield` (`assets/screenshots/screen-shield.png`)**:
   - Hotspot 1 (`x: 50%, y: 28%`): **Tamper Source & Timestamp Telemetry** — Displays the exact hardware trigger (e.g., `Power Unplugged`) and trigger timestamp.
   - Hotspot 2 (`x: 50%, y: 55%`): **Touch ID + Brute-Force-Protected PIN (`PinAttemptLimiter`)** — Enforces `15s` (5 fails), `60s` (8 fails), and `300s + Alarm Escalation` (10 fails) lockouts.
   - Hotspot 3 (`x: 50%, y: 78%`): **Mac Password Recovery Fallback** — Forgot your PIN? Verify your macOS account password via `LocalAuthentication` to recover cleanly.

---

## 8. Waitlist, Early Access Pass & Local Build Section (`#waitlist`)

Because the project owner has not created the dedicated waitlist email address yet, `#waitlist` must work **100% out-of-the-box right now** (storing validated signups locally and generating an instant interactive **Pupil Early Access Pass** + **30-Second Local Build & Test** guide), while providing a **1-line configuration constant** at the top of `docs/app.js` for plugging in Formspree, Google Apps Script, a custom webhook, or a `mailto:` address later.

### 8.1. Zero-Code Config Constant in `docs/app.js`
At the very top of `docs/app.js`, define `WAITLIST_CONFIG` (and alias `const WAITLIST_ENDPOINT = WAITLIST_CONFIG;` so both names work):

```javascript
/**
 *Zero-code Waitlist & Early Access configuration.
 * When your email or form endpoint is ready, set `endpointUrl` (Formspree / Google Script / Webhook)
 * or set `mailtoAddress` (e.g. "pupil@yourdomain.com") and change `mode` accordingly.
 */
const WAITLIST_CONFIG = {
  mode: "local", // "local" | "endpoint" | "mailto"
  endpointUrl: "", // e.g. "https://formspree.io/f/your_form_id"
  mailtoAddress: "", // e.g. "earlyaccess@try-pupil.app"
  storageKey: "pupil.waitlist.submissions.v1",
  githubRepoUrl: "https://github.com/stevewong-a/pupil",
  githubReleasesUrl: "https://github.com/stevewong-a/pupil/releases"
};
const WAITLIST_ENDPOINT = WAITLIST_CONFIG;
```

### 8.2. Mandatory Accessible Form Markup (`modern-web-guidance` — `forms`)
`docs/index.html` MUST use semantic, accessible form controls:
1. **Explicit `<label for="waitlist-email">`**: Visible label above the email input (never placeholder-only).
2. **Mobile-Optimized Email Input Attributes**:
   ```html
   <label for="waitlist-email" class="form-label">University or work email</label>
   <input
     type="email"
     id="waitlist-email"
     name="email"
     class="form-input"
     placeholder="you@university.edu"
     autocomplete="email"
     autocorrect="off"
     autocapitalize="none"
     spellcheck="false"
     enterkeyhint="done"
     aria-describedby="waitlist-hint waitlist-error"
     required
   >
   ```
3. **Persona Selection (`<fieldset>` + `<legend>` Radio Pills)**:
   ```html
   <fieldset class="persona-fieldset">
     <legend class="form-label">Where will you use Pupil most?</legend>
     <div class="persona-pills">
       <label class="persona-pill">
         <input type="radio" name="persona" value="College student" checked>
         <span>🎓 College student (Library / Dining hall)</span>
       </label>
       <label class="persona-pill">
         <input type="radio" name="persona" value="Cafe / remote worker">
         <span>☕ Cafe / remote worker</span>
       </label>
       <label class="persona-pill">
         <input type="radio" name="persona" value="Developer / security enthusiast">
         <span>🔐 Developer / security enthusiast</span>
       </label>
     </div>
   </fieldset>
   ```
4. **Validation Choreography (`blur` + `submit`, clear on `input`, `:user-invalid`)**:
   - Style invalid fields in CSS using `.form-input:user-invalid` and `.form-input[aria-invalid="true"]` (NEVER raw `:invalid`, which turns fields red before the user types).
   - Validate on `blur` and `submit`; clear `aria-invalid` and `#waitlist-error` immediately on `input`.
   - Announce validation errors and submission success inside `<div id="waitlist-status" class="sr-status" role="status" aria-live="polite"></div>`.
5. **Instant Confirmation State ("Pupil Early Access Pass" + "Test Locally in 30s")**:
   - On valid submission:
     - Persist `{ email, persona, passNumber, timestamp }` to `localStorage` under `WAITLIST_CONFIG.storageKey`.
     - If `WAITLIST_CONFIG.mode === "endpoint"` and `endpointUrl` is non-empty, `fetch(endpointUrl, { method: "POST", ... })` with graceful fallback to local storage.
     - If `WAITLIST_CONFIG.mode === "mailto"` and `mailtoAddress` is non-empty, trigger `mailto:` link with pre-filled subject/body alongside the confirmation card.
     - Reveal the interactive **Pupil Early Access Pass (`#waitlist-pass-card`)** showing deterministic Pass `#` (e.g. `PASS #0418`), selected persona badge, registered email, a **"Download / Copy Pass Badge"** button, a **"Download Latest `Pupil.dmg` (GitHub Releases)"** button, and an interactive **"Build & Test From Source in 30 Seconds"** terminal card with 1-click Copy:
       ```bash
       git clone https://github.com/stevewong-a/pupil.git && cd pupil
       ./scripts/build-dmg.sh && open ./dist/Pupil.app
       ```

---

## 9. Scroll-Driven Animations, Reduced Motion & Verification Checklist

### 9.1. Progressive Enhancement Scroll Reveal & Reduced Motion
In `docs/styles.css`, implement scroll-driven entry animations gated behind `@supports` and `@media (prefers-reduced-motion: no-preference)`, paired with an `IntersectionObserver` `.is-visible` class fallback in `docs/app.js`:

```css
@media (prefers-reduced-motion: no-preference) {
  @supports ((animation-timeline: view()) and (animation-range: entry)) {
    .reveal-on-scroll {
      animation: pupil-reveal linear both;
      animation-timeline: view();
      animation-range: entry 10% cover 28%;
    }
  }
}

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```
> **Hover Transform Rule (`uberdesigner` Pillar 4)**: Never apply `animation-fill-mode: both` directly to interactive buttons or pills that also use `:hover { transform: scale(...) }`. Use `animation-fill-mode: backwards` or apply scroll reveals to wrapper containers.

### 9.2. GitHub Pages Workflow (`.github/workflows/pages.yml`)
`@web-coder` must create `/Users/stevew/Documents/Pupil/.github/workflows/pages.yml` configured to deploy `/docs` on pushes to `main` (and `workflow_dispatch`), with `permissions: contents: read, pages: write, id-token: write`. Also create `/Users/stevew/Documents/Pupil/docs/.nojekyll`.

### 9.3. "Done When" Verification Contract (for `@app-photographer`, `@web-coder`, and `@web-verifier`)
- [ ] All 6 real application screenshots (`settings-general.png`, `settings-gaze.png`, `settings-sensors.png`, `settings-alarm.png`, `menubar-popover.png`, `screen-shield.png`) exist in `docs/assets/screenshots/`, are non-empty 2x Retina dark-mode PNGs, and return HTTP `200` with zero broken `<img>` links.
- [ ] All 6 interactive simulator scenarios (*Arm*, *Shoulder Surfer Gaze*, *Unplug MagSafe*, *Unplug Library Monitor*, *Insert YubiKey / Touch ID*, *Trigger Progressive Siren*) + iPhone Companion *Remote Disarm* / *Ping Camera Snapshot* + optional WebAudio 880/660 Hz synth work deterministically with zero console errors.
- [ ] All 6 screenshot showcase tabs and their 3 interactive hotspot pins per tab switch cleanly and update the Feature Inspector description.
- [ ] Waitlist form uses explicit `<label for="waitlist-email">`, `autocomplete="email"`, `autocorrect="off"`, `autocapitalize="none"`, `<fieldset>` + `<legend>` persona radios, `:user-invalid` styling, `aria-live="polite"` status region, `WAITLIST_CONFIG` / `WAITLIST_ENDPOINT` in `docs/app.js`, and renders the Early Access Pass confirmation card on submit.
- [ ] Companion PWA (`docs/companion.html` + `?v=`/`?c=` routing in `docs/index.html` + `docs/sw.js` + `docs/manifest.json`) remains 100% functional.
- [ ] `<meta name="color-scheme" content="dark light">`, `:root { color-scheme: dark light; }`, `text-box: trim-both cap alphabetic` with `@supports not` fallback, `@supports ((animation-timeline: view()) and (animation-range: entry))`, and `@media (prefers-reduced-motion: reduce)` are present in `docs/index.html` and `docs/styles.css`.
