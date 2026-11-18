/**
 * Zero-code Waitlist & Early Access configuration.
 * When your email or form endpoint is ready, set `endpointUrl` (Formspree / Google Script / Webhook)
 * or set `mailtoAddress` (e.g. "earlyaccess@try-pupil.app") and change `mode` accordingly.
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

(function () {
  "use strict";

  // Register Service Worker so "Add to Home Screen" PWA stays ready
  if ("serviceWorker" in navigator && window.isSecureContext) {
    navigator.serviceWorker.register("./sw.js").catch(function () {});
  }

  // =========================================================================
  // Shared Crisp Monochrome Vector Icons (Zero Emojis)
  // =========================================================================
  const ICONS = {
    volumeOff:
      '<svg class="icon-svg" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 5L6 9H2v6h4l5 4V5z"/><line x1="23" y1="9" x2="17" y2="15"/><line x1="17" y1="9" x2="23" y2="15"/></svg>',
    volumeOn:
      '<svg class="icon-svg" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 5L6 9H2v6h4l5 4V5z"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/></svg>',
    eye:
      '<svg class="icon-svg icon-svg-lg" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>',
    plug:
      '<svg class="icon-svg icon-svg-lg" viewBox="0 0 24 24" aria-hidden="true"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg>',
    monitor:
      '<svg class="icon-svg icon-svg-lg" viewBox="0 0 24 24" aria-hidden="true"><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>',
    siren:
      '<svg class="icon-svg icon-svg-lg" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="M20 12h2"/><path d="m19.07 4.93-1.41 1.41"/><path d="M2 12h2"/><path d="M7 18v-5a5 5 0 0 1 10 0v5"/><rect x="5" y="18" width="14" height="4" rx="1"/></svg>'
  };

  // =========================================================================
  // 1. Interactive MacBook Notch & iPhone Companion Simulator
  // =========================================================================
  const macbookEl = document.getElementById("sim-macbook");
  const notchEl = document.getElementById("sim-notch");
  const notchLeftEl = document.getElementById("sim-notch-left");
  const notchRightEl = document.getElementById("sim-notch-right");
  const notchLeftText = document.getElementById("sim-notch-left-text");
  const notchRightText = document.getElementById("sim-notch-right-text");
  const shieldOverlay = document.getElementById("sim-shield-overlay");
  const shieldIcon = document.getElementById("sim-shield-icon");
  const shieldTitle = document.getElementById("sim-shield-title");
  const shieldDetail = document.getElementById("sim-shield-detail");
  const sirenMeterEl = document.getElementById("sim-siren-meter");
  const sirenEnvLabel = document.getElementById("sim-siren-env-label");
  const sirenPctLabel = document.getElementById("sim-siren-pct");
  const sirenBarFill = document.getElementById("sim-siren-bar-fill");
  const envPillsWrap = document.getElementById("sim-env-pills");
  const modalUnlockBtn = document.getElementById("btn-sim-modal-unlock");

  const telState = document.getElementById("tel-state");
  const telVision = document.getElementById("tel-vision");
  const telTrigger = document.getElementById("tel-trigger");
  const telSiren = document.getElementById("tel-siren");
  const menubarPower = document.getElementById("sim-menubar-power");

  const iphoneBanner = document.getElementById("sim-iphone-banner");
  const iphoneTime = document.getElementById("sim-iphone-time");
  const iphoneTitle = document.getElementById("sim-iphone-title");
  const iphoneBody = document.getElementById("sim-iphone-body");
  const snapshotEmpty = document.getElementById("sim-iphone-snapshot-empty");
  const snapshotPreview = document.getElementById("sim-iphone-snapshot-preview");
  const btnIphoneSnapshot = document.getElementById("btn-iphone-snapshot");
  const btnIphoneDisarm = document.getElementById("btn-iphone-disarm");

  const journalCode = document.getElementById("sim-journal-code");
  const journalText = document.getElementById("sim-journal-text");
  const scenarioButtons = Array.from(document.querySelectorAll(".sim-pill[data-scenario]"));
  const envButtons = Array.from(document.querySelectorAll(".sim-env-pill[data-env]"));

  const audioToggleBtn = document.getElementById("btn-sim-audio-toggle");
  const audioIcon = document.getElementById("sim-audio-icon");
  const audioLabel = document.getElementById("sim-audio-label");

  const ENV_PRESETS = {
    library: { name: "Library", cap: 45 },
    cafe: { name: "Cafe", cap: 80 },
    park: { name: "Park", cap: 100 }
  };

  const sim = {
    scenario: "arm",
    env: "cafe",
    countdownTimer: null,
    sirenInterval: null,
    armingTimer: null,
    graceRemaining: 15,
    sirenStartMs: 0,
    sirenCurrentPct: 0,
    audioEnabled: false,
    audioCtx: null,
    oscillator: null,
    gainNode: null,
    toneTimer: null,
    toneHigh: true
  };

  function clearSimTimers() {
    if (sim.countdownTimer) {
      clearInterval(sim.countdownTimer);
      sim.countdownTimer = null;
    }
    if (sim.sirenInterval) {
      clearInterval(sim.sirenInterval);
      sim.sirenInterval = null;
    }
    if (sim.armingTimer) {
      clearTimeout(sim.armingTimer);
      sim.armingTimer = null;
    }
  }

  function stopSirenAudio() {
    if (sim.toneTimer) {
      clearInterval(sim.toneTimer);
      sim.toneTimer = null;
    }
    if (sim.gainNode && sim.audioCtx) {
      try {
        sim.gainNode.gain.setTargetAtTime(0, sim.audioCtx.currentTime, 0.03);
      } catch (_) {}
    }
    if (sim.oscillator) {
      try {
        sim.oscillator.stop(sim.audioCtx.currentTime + 0.08);
      } catch (_) {}
      sim.oscillator = null;
    }
    sim.gainNode = null;
  }

  function startSirenAudioIfEnabled() {
    if (!sim.audioEnabled) return;
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return;

    if (!sim.audioCtx) {
      sim.audioCtx = new AudioCtx();
    }
    if (sim.audioCtx.state === "suspended") {
      sim.audioCtx.resume().catch(function () {});
    }
    stopSirenAudio();

    const osc = sim.audioCtx.createOscillator();
    const gain = sim.audioCtx.createGain();
    osc.type = "square";
    osc.frequency.setValueAtTime(880, sim.audioCtx.currentTime);
    const capScalar = ENV_PRESETS[sim.env].cap / 100;
    gain.gain.setValueAtTime(0.015 * capScalar, sim.audioCtx.currentTime);

    osc.connect(gain);
    gain.connect(sim.audioCtx.destination);
    osc.start();

    sim.oscillator = osc;
    sim.gainNode = gain;
    sim.toneHigh = true;

    sim.toneTimer = setInterval(function () {
      if (!sim.oscillator || !sim.audioCtx) return;
      sim.toneHigh = !sim.toneHigh;
      sim.oscillator.frequency.setValueAtTime(sim.toneHigh ? 880 : 660, sim.audioCtx.currentTime);
    }, 450);
  }

  function updateSirenAudioGain(effectivePct) {
    if (!sim.audioEnabled || !sim.gainNode || !sim.audioCtx) return;
    const targetGain = Math.max(0.008, (effectivePct / 100) * 0.055);
    try {
      sim.gainNode.gain.setTargetAtTime(targetGain, sim.audioCtx.currentTime, 0.08);
    } catch (_) {}
  }

  function setNotch(tone, leftMsg, rightMsg, expanded) {
    notchEl.dataset.tone = tone;
    notchEl.dataset.expanded = expanded ? "true" : "false";
    notchLeftEl.className = "sim-notch-left notch-wing-" + tone;
    notchRightEl.className = "sim-notch-right notch-wing-" + tone + " tabular";
    notchLeftText.textContent = leftMsg;
    notchRightText.textContent = rightMsg;
  }

  function setActiveScenarioButton(scenario) {
    scenarioButtons.forEach(function (btn) {
      btn.classList.toggle("is-active", btn.dataset.scenario === scenario);
    });
  }

  function setIphoneState(severity, title, body, timeText) {
    iphoneBanner.dataset.severity = severity;
    iphoneTitle.textContent = title;
    iphoneBody.textContent = body;
    iphoneTime.textContent = timeText || "just now";
  }

  function setJournal(code, message) {
    journalCode.textContent = code;
    journalText.textContent = message;
  }

  function setEnvPreset(envKey) {
    if (!ENV_PRESETS[envKey]) return;
    sim.env = envKey;
    envButtons.forEach(function (btn) {
      btn.classList.toggle("is-active", btn.dataset.env === envKey);
    });
    const preset = ENV_PRESETS[envKey];
    sirenEnvLabel.textContent = preset.name + " Preset (" + preset.cap + "% max)";
    if (sim.scenario !== "siren") {
      telSiren.textContent = "0% (" + preset.name + " " + preset.cap + "%)";
    }
  }

  function runScenario(scenario) {
    clearSimTimers();
    stopSirenAudio();
    sim.scenario = scenario;
    setActiveScenarioButton(scenario);

    const preset = ENV_PRESETS[sim.env];
    sirenMeterEl.hidden = true;
    envPillsWrap.hidden = true;

    if (scenario === "arm") {
      macbookEl.dataset.simState = "arming";
      macbookEl.dataset.blurred = "false";
      shieldOverlay.classList.remove("is-visible");
      menubarPower.textContent = "MagSafe AC";
      setNotch("amber", "Arming…", "2s", true);
      telState.textContent = "ARMING";
      telVision.textContent = "Calibrating";
      telTrigger.textContent = "Shortcut ⌃⌥⌘L";
      telSiren.textContent = "0% (" + preset.name + " " + preset.cap + "%)";
      setIphoneState("safe", "Arming MacBook Pro…", "Exit delay started.", "now");
      setJournal("ArmingStarted", "Exit countdown active via ⌃⌥⌘L.");

      sim.armingTimer = setTimeout(function () {
        if (sim.scenario !== "arm") return;
        macbookEl.dataset.simState = "armed";
        setNotch("green", "Armed", "10.0 FPS", true);
        telState.textContent = "ARMED";
        telVision.textContent = "10.0 FPS";
        telTrigger.textContent = "4 active";
        setIphoneState("safe", "Armed Sentinel Active", "Instant APNs alerts over Wi-Fi or 5G.", "now");
        setJournal("SystemArmed", "MagSafe, Display, Lid, and Gaze armed.");
      }, 900);
      return;
    }

    if (scenario === "gaze") {
      macbookEl.dataset.simState = "gaze-warning";
      macbookEl.dataset.blurred = "true";
      shieldOverlay.classList.add("is-visible");
      shieldIcon.innerHTML = ICONS.eye;
      shieldTitle.textContent = "Privacy Shield Active";
      shieldDetail.textContent = "Peripheral gaze locked. Clears on look-away.";
      modalUnlockBtn.textContent = "Dismiss Preview Blur";
      menubarPower.textContent = "MagSafe AC";
      setNotch("amber", "Gaze Detected", "Score 0.78", true);
      telState.textContent = "GAZE SHIELD";
      telVision.textContent = "90% ROI";
      telTrigger.textContent = "2.0s dwell";
      telSiren.textContent = "0% (Silent)";
      setIphoneState("warning", "Shoulder Surfer Blocked", "Workspace blurred in RAM. Zero frames saved.", "just now");
      setJournal("GazeWarning", "Peripheral gaze dwell reached 2.0s; blur active.");
      return;
    }

    if (scenario === "magsafe" || scenario === "monitor") {
      const isMagSafe = scenario === "magsafe";
      sim.graceRemaining = 15;
      macbookEl.dataset.simState = isMagSafe ? "tamper-magsafe" : "tamper-display";
      macbookEl.dataset.blurred = "true";
      shieldOverlay.classList.add("is-visible");
      shieldIcon.innerHTML = isMagSafe ? ICONS.plug : ICONS.monitor;
      shieldTitle.textContent = "Tamper detected — 15s";
      shieldDetail.textContent = isMagSafe
        ? "AC power unplugged. Anti-flap guard active."
        : "External display unplugged. 15s grace timer active.";
      modalUnlockBtn.textContent = "Unlock via Touch ID / PIN";
      menubarPower.textContent = isMagSafe ? "Battery" : "MagSafe AC";
      setNotch("amber", isMagSafe ? "Power Unplugged" : "Monitor Unplugged", "15s", true);

      telState.textContent = "TAMPER (15s)";
      telVision.textContent = "10.0 FPS";
      telTrigger.textContent = isMagSafe ? "Power Unplug" : "Display Unplug";
      telSiren.textContent = "Grace (0%)";

      setIphoneState(
        "warning",
        isMagSafe ? "Power Unplugged" : "Monitor Unplugged",
        "15s grace timer active. Tap Remote Disarm to cancel.",
        "just now"
      );
      setJournal(
        isMagSafe ? "TamperPowerUnplugged" : "TamperDisplayUnplugged",
        "Hardware tripwire triggered — 15s grace timer running."
      );

      sim.countdownTimer = setInterval(function () {
        sim.graceRemaining -= 1;
        if (sim.graceRemaining <= 0) {
          runScenario("siren");
          return;
        }
        shieldTitle.textContent = "Tamper detected — " + sim.graceRemaining + "s";
        notchRightText.textContent = sim.graceRemaining + "s";
        telState.textContent = "TAMPER (" + sim.graceRemaining + "s)";
      }, 1000);
      return;
    }

    if (scenario === "touchid") {
      macbookEl.dataset.simState = "disarmed-touchid";
      macbookEl.dataset.blurred = "false";
      shieldOverlay.classList.remove("is-visible");
      menubarPower.textContent = "MagSafe AC";
      setNotch("green", "Touch ID Verified", "Disarmed", true);
      telState.textContent = "DISARMED";
      telVision.textContent = "Idle";
      telTrigger.textContent = "Touch ID / BLE";
      telSiren.textContent = "0% (Silenced)";
      setIphoneState("safe", "Disarmed by Owner", "Touch ID & iPhone proximity verified.", "just now");
      setJournal("DisarmedOwner", "Disarmed instantly via Touch ID & proximity.");
      return;
    }

    if (scenario === "siren") {
      macbookEl.dataset.simState = "alarm-siren";
      macbookEl.dataset.blurred = "true";
      shieldOverlay.classList.add("is-visible");
      shieldIcon.innerHTML = ICONS.siren;
      shieldTitle.textContent = "ALARM ACTIVE — 880 / 660 Hz";
      shieldDetail.textContent = "Built-in speakers forced. Ramps 30% → 100% over 8s.";
      modalUnlockBtn.textContent = "Disarm Siren (Touch ID / PIN)";
      sirenMeterEl.hidden = false;
      envPillsWrap.hidden = false;
      setNotch("red", "ALARM ACTIVE", "30% → " + preset.cap + "%", true);

      sim.sirenStartMs = performance.now();
      startSirenAudioIfEnabled();

      const tickSiren = function () {
        const elapsedSec = (performance.now() - sim.sirenStartMs) / 1000;
        const progress = Math.min(1, elapsedSec / 8);
        const curveScalar = 0.30 + 0.70 * progress;
        const activeCap = ENV_PRESETS[sim.env].cap;
        const effectivePct = Math.round(curveScalar * activeCap);
        sim.sirenCurrentPct = effectivePct;

        sirenPctLabel.textContent = effectivePct + "% (of " + activeCap + "% cap)";
        sirenBarFill.style.width = Math.max(8, effectivePct) + "%";
        notchRightText.textContent = effectivePct + "%";
        telState.textContent = "ALARM";
        telVision.textContent = "10.0 FPS";
        telTrigger.textContent = "Sleep Blocked";
        telSiren.textContent = effectivePct + "% (" + ENV_PRESETS[sim.env].name + ")";
        updateSirenAudioGain(effectivePct);
      };

      tickSiren();
      sim.sirenInterval = setInterval(tickSiren, 180);

      setIphoneState(
        "critical",
        "SIREN ACTIVE — Tamper Alarm",
        "880/660 Hz siren latched. Ping snapshot or disarm.",
        "now"
      );
      setJournal("AlarmEscalated", "Progressive siren active (30% → 100%). Sleep blocked.");
    }
  }

  scenarioButtons.forEach(function (btn) {
    btn.addEventListener("click", function () {
      runScenario(btn.dataset.scenario);
    });
  });

  envButtons.forEach(function (btn) {
    btn.addEventListener("click", function () {
      setEnvPreset(btn.dataset.env);
    });
  });

  modalUnlockBtn.addEventListener("click", function () {
    runScenario("touchid");
  });

  btnIphoneDisarm.addEventListener("click", function () {
    clearSimTimers();
    stopSirenAudio();
    sim.scenario = "touchid";
    setActiveScenarioButton("touchid");
    macbookEl.dataset.simState = "disarmed-touchid";
    macbookEl.dataset.blurred = "false";
    shieldOverlay.classList.remove("is-visible");
    sirenMeterEl.hidden = true;
    envPillsWrap.hidden = true;
    menubarPower.textContent = "MagSafe AC";
    setNotch("green", "Remote Disarm", "Verified", true);
    telState.textContent = "DISARMED";
    telTrigger.textContent = "HMAC-SHA256";
    telSiren.textContent = "0% (Silenced)";
    setIphoneState("safe", "Disarmed Remotely", "Authenticated disarm verified on MacBook.", "just now");
    setJournal("DisarmedRemotely", "Authenticated disarm command received from iPhone.");
  });

  btnIphoneSnapshot.addEventListener("click", function () {
    snapshotEmpty.hidden = true;
    snapshotPreview.hidden = false;
    setJournal("RemoteSnapshotSent", "Verification frame pushed to iPhone companion.");
  });

  audioToggleBtn.addEventListener("click", function () {
    sim.audioEnabled = !sim.audioEnabled;
    audioToggleBtn.setAttribute("aria-pressed", sim.audioEnabled ? "true" : "false");
    audioLabel.textContent = sim.audioEnabled ? "Audio Preview: On (880/660 Hz)" : "Audio Preview: Off";
    audioIcon.innerHTML = sim.audioEnabled ? ICONS.volumeOn : ICONS.volumeOff;

    if (sim.audioEnabled && sim.scenario === "siren") {
      startSirenAudioIfEnabled();
    } else if (!sim.audioEnabled) {
      stopSirenAudio();
    }
  });

  // =========================================================================
  // 2. Interactive App Screenshot Showcase & Hotspot Inspector
  // =========================================================================
  const SCREENSHOT_DATA = {
    general: {
      src: "./assets/screenshots/settings-general.png",
      alt: "Pupil General Settings window showing auto-arm, OS hardware lockdown, and stepped timers",
      width: 1000,
      height: 2214,
      wide: false,
      file: "GeneralSettingsPage.swift",
      hotspots: [
        {
          x: 78,
          y: 24,
          title: "Idle Auto-Arm (5–30m)",
          desc: "Arms after HID inactivity; ignores closed-lid sleep."
        },
        {
          x: 78,
          y: 48,
          title: "OS Hardware Lockdown",
          desc: "Blocks Force Quit, Command-Tab, and Dock during tamper."
        },
        {
          x: 68,
          y: 72,
          title: "Stepped Grace Timers",
          desc: "5s–30s window to cancel accidental cable bumps."
        }
      ]
    },
    gaze: {
      src: "./assets/screenshots/settings-gaze.png",
      alt: "Pupil Gaze Settings window showing adaptive frame rate, Minimal Pill vs Silent Log tiles, and Detection Cone slider",
      width: 1000,
      height: 2158,
      wide: false,
      file: "GazeSettingsPage.swift",
      hotspots: [
        {
          x: 78,
          y: 17,
          title: "Adaptive Frame Governor",
          desc: "Scales 10 → 5 → 2 FPS on low battery."
        },
        {
          x: 70,
          y: 28,
          title: "Notch Deterrent Modes",
          desc: "Switch between live notch wings and silent audit log."
        },
        {
          x: 65,
          y: 42,
          title: "4-Stage Peripheral Cone",
          desc: "Expands camera ROI up to 90% for side angles."
        }
      ]
    },
    sensors: {
      src: "./assets/screenshots/settings-sensors.png",
      alt: "Pupil Sensors Settings window showing Hardware Triggers, One-Time QR Phone Companion, Bluetooth Proximity, and Trusted Wi-Fi",
      width: 1000,
      height: 4086,
      wide: false,
      file: "SensorsSettingsPage.swift",
      hotspots: [
        {
          x: 56,
          y: 6,
          title: "Hardware Tripwire Matrix",
          desc: "Monitors MagSafe, USB-C displays, lid state, and input."
        },
        {
          x: 45,
          y: 39,
          title: "One-Time QR Pairing",
          desc: "Direct RFC 8291 Web Push encryption without cloud relays."
        },
        {
          x: 65,
          y: 75,
          title: "Proximity, Wi-Fi & Keys",
          desc: "Bluetooth proximity disarm, trusted Wi-Fi, and optional USB keys."
        }
      ]
    },
    alarm: {
      src: "./assets/screenshots/settings-alarm.png",
      alt: "Pupil Alarm Settings window showing Siren tone, Force built-in speakers, Location environment presets, Progressive escalation, and Encrypted Activity Log",
      width: 1000,
      height: 2442,
      wide: false,
      file: "AlarmSettingsPage.swift",
      hotspots: [
        {
          x: 78,
          y: 12,
          title: "Speaker Route Override",
          desc: "Bypasses headphones and unmutes built-in MacBook speakers."
        },
        {
          x: 64,
          y: 18,
          title: "Acoustic Ceiling Presets",
          desc: "Caps siren at 45% (Library), 80% (Cafe), or 100%."
        },
        {
          x: 68,
          y: 50,
          title: "Encrypted Tamper Journal",
          desc: "200-event AES-GCM ring buffer with Markdown export."
        }
      ]
    },
    menubar: {
      src: "./assets/screenshots/menubar-popover.png",
      alt: "Pupil Menu Bar popover showing armed status, Power Adapter readout, quick toggles, and Simulate Tamper",
      width: 564,
      height: 676,
      wide: false,
      file: "MenuBarPopoverView.swift",
      hotspots: [
        {
          x: 50,
          y: 13,
          title: "Live NSStatusBar Header",
          desc: "Real-time armed state, grace timer, and AC status."
        },
        {
          x: 65,
          y: 47,
          title: "1-Click Quick Toggles",
          desc: "Flip gaze blur and auto-arm without opening Settings."
        },
        {
          x: 50,
          y: 75,
          title: "Dockless Accessory Mode",
          desc: "Zero Dock clutter; blocks unauthorized Quit while armed."
        }
      ]
    },
    shield: {
      src: "./assets/screenshots/screen-shield.png",
      alt: "Pupil Screen Shield overlay showing Tamper detected 15s, AC Charger Unplugged badge, PIN field with Touch ID, Unlock button, and Forgot PIN recovery",
      width: 1440,
      height: 920,
      wide: true,
      file: "ScreenShieldView.swift",
      hotspots: [
        {
          x: 50,
          y: 42,
          title: "Tamper Source Telemetry",
          desc: "Displays exact hardware trigger and timestamp on lock screen."
        },
        {
          x: 59,
          y: 61,
          title: "Touch ID & PIN Backoff",
          desc: "Instant biometric unlock with exponential brute-force lockouts."
        },
        {
          x: 50,
          y: 90,
          title: "macOS Password Recovery",
          desc: "LocalAuthentication fallback resets PIN lockout cleanly."
        }
      ]
    }
  };

  const tabButtons = Array.from(document.querySelectorAll(".showcase-tab[data-tab]"));
  const showcaseViewport = document.getElementById("showcase-viewport");
  const showcaseStage = document.getElementById("showcase-image-stage");
  const showcaseImg = document.getElementById("showcase-img");
  const hotspotPins = Array.from(document.querySelectorAll(".hotspot-pin[data-hotspot]"));
  const inspectorMeta = document.getElementById("inspector-meta");
  const inspectorTitle = document.getElementById("inspector-title");
  const inspectorDesc = document.getElementById("inspector-desc");
  const inspectorList = document.getElementById("inspector-hotspot-list");

  let activeTabKey = "general";
  let activeHotspotIndex = 0;

  function renderHotspotInspector(shouldScrollIntoView) {
    const data = SCREENSHOT_DATA[activeTabKey];
    const hotspot = data.hotspots[activeHotspotIndex] || data.hotspots[0];

    inspectorMeta.textContent = data.file + " · Hotspot " + (activeHotspotIndex + 1) + " of " + data.hotspots.length;
    inspectorTitle.textContent = hotspot.title;
    inspectorDesc.textContent = hotspot.desc;

    hotspotPins.forEach(function (pin, idx) {
      const hs = data.hotspots[idx];
      if (!hs) return;
      pin.style.left = hs.x + "%";
      pin.style.top = hs.y + "%";
      pin.classList.toggle("is-active", idx === activeHotspotIndex);
      pin.setAttribute("aria-label", "Hotspot " + (idx + 1) + ": " + hs.title);
    });

    inspectorList.innerHTML = "";
    data.hotspots.forEach(function (hs, idx) {
      const itemBtn = document.createElement("button");
      itemBtn.type = "button";
      itemBtn.className = "inspector-hotspot-item" + (idx === activeHotspotIndex ? " is-active" : "");
      itemBtn.innerHTML = '<span class="inspector-num">' + (idx + 1) + "</span><span>" + hs.title + "</span>";
      itemBtn.addEventListener("click", function () {
        activeHotspotIndex = idx;
        renderHotspotInspector(true);
      });
      inspectorList.appendChild(itemBtn);
    });

    if (shouldScrollIntoView && hotspotPins[activeHotspotIndex]) {
      try {
        hotspotPins[activeHotspotIndex].scrollIntoView({ behavior: "smooth", block: "nearest" });
      } catch (_) {}
    }
  }

  function switchScreenshotTab(tabKey) {
    const data = SCREENSHOT_DATA[tabKey];
    if (!data) return;
    activeTabKey = tabKey;
    activeHotspotIndex = 0;

    tabButtons.forEach(function (btn) {
      const selected = btn.dataset.tab === tabKey;
      btn.classList.toggle("is-active", selected);
      btn.setAttribute("aria-selected", selected ? "true" : "false");
    });

    showcaseStage.dataset.wide = data.wide ? "true" : "false";
    showcaseImg.src = data.src;
    showcaseImg.alt = data.alt;
    showcaseImg.width = data.width;
    showcaseImg.height = data.height;
    showcaseViewport.scrollTop = 0;

    renderHotspotInspector(false);
  }

  tabButtons.forEach(function (btn) {
    btn.addEventListener("click", function () {
      switchScreenshotTab(btn.dataset.tab);
    });
  });

  hotspotPins.forEach(function (pin) {
    pin.addEventListener("click", function () {
      activeHotspotIndex = Number(pin.dataset.hotspot) || 0;
      renderHotspotInspector(false);
    });
  });

  renderHotspotInspector(false);

  // =========================================================================
  // 3. Accessible Waitlist Form & Early Access Pass
  // =========================================================================
  const waitlistForm = document.getElementById("waitlist-form");
  const emailInput = document.getElementById("waitlist-email");
  const emailError = document.getElementById("waitlist-error");
  const waitlistStatus = document.getElementById("waitlist-status");
  const passCard = document.getElementById("waitlist-pass-card");
  const passNumberBadge = document.getElementById("pass-number-badge");
  const passMetaText = document.getElementById("pass-meta-text");
  const btnCopyPass = document.getElementById("btn-copy-pass");
  const btnCopyBuildCmd = document.getElementById("btn-copy-build-cmd");
  const buildCmdCode = document.getElementById("build-cmd-code");

  function computePassCode(email) {
    let hash = 418;
    for (let i = 0; i < email.length; i += 1) {
      hash = (hash * 31 + email.charCodeAt(i)) % 9000;
    }
    return "PASS #" + String(1000 + hash).padStart(4, "0");
  }

  function clearEmailValidation() {
    emailInput.removeAttribute("aria-invalid");
    emailError.hidden = true;
    emailError.textContent = "";
  }

  function validateEmailField() {
    const val = emailInput.value.trim();
    if (!val) {
      emailInput.setAttribute("aria-invalid", "true");
      emailError.textContent = "Please enter your university or work email address.";
      emailError.hidden = false;
      return false;
    }
    if (!emailInput.checkValidity() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(val)) {
      emailInput.setAttribute("aria-invalid", "true");
      emailError.textContent = "Enter a valid email address (for example, name@university.edu).";
      emailError.hidden = false;
      return false;
    }
    clearEmailValidation();
    return true;
  }

  function renderEarlyAccessPass(record) {
    passNumberBadge.textContent = record.passNumber;
    passMetaText.textContent = "Reserved for " + record.email + " · " + record.persona;
    passCard.hidden = false;
  }

  try {
    const existingRaw = localStorage.getItem(WAITLIST_CONFIG.storageKey);
    if (existingRaw) {
      const parsed = JSON.parse(existingRaw);
      if (Array.isArray(parsed) && parsed.length > 0) {
        renderEarlyAccessPass(parsed[parsed.length - 1]);
      }
    }
  } catch (_) {}

  emailInput.addEventListener("blur", function () {
    if (emailInput.value.trim().length > 0) {
      validateEmailField();
    }
  });

  emailInput.addEventListener("input", function () {
    clearEmailValidation();
    waitlistStatus.textContent = "";
  });

  waitlistForm.addEventListener("submit", async function (event) {
    event.preventDefault();
    if (!validateEmailField()) {
      waitlistStatus.textContent = emailError.textContent;
      emailInput.focus();
      return;
    }

    const email = emailInput.value.trim();
    const checkedPersona = waitlistForm.querySelector('input[name="persona"]:checked');
    const persona = checkedPersona ? checkedPersona.value : "College student";
    const passNumber = computePassCode(email);
    const record = {
      email: email,
      persona: persona,
      passNumber: passNumber,
      timestamp: new Date().toISOString()
    };

    try {
      const existing = JSON.parse(localStorage.getItem(WAITLIST_CONFIG.storageKey) || "[]");
      const list = Array.isArray(existing) ? existing : [];
      list.push(record);
      localStorage.setItem(WAITLIST_CONFIG.storageKey, JSON.stringify(list.slice(-20)));
    } catch (_) {}

    if (WAITLIST_CONFIG.mode === "endpoint" && WAITLIST_CONFIG.endpointUrl) {
      try {
        await fetch(WAITLIST_CONFIG.endpointUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json", Accept: "application/json" },
          body: JSON.stringify(record)
        });
      } catch (_) {}
    } else if (WAITLIST_CONFIG.mode === "mailto" && WAITLIST_CONFIG.mailtoAddress) {
      const subject = encodeURIComponent("Pupil Early Access Request (" + passNumber + ")");
      const body = encodeURIComponent("Email: " + email + "\nUse case: " + persona + "\nPass: " + passNumber);
      window.location.href = "mailto:" + WAITLIST_CONFIG.mailtoAddress + "?subject=" + subject + "&body=" + body;
    }

    renderEarlyAccessPass(record);
    waitlistStatus.textContent = "Early Access Pass " + passNumber + " confirmed for " + email + ".";
  });

  btnCopyPass.addEventListener("click", async function () {
    const summary = passNumberBadge.textContent + " — " + passMetaText.textContent;
    try {
      await navigator.clipboard.writeText(summary);
      btnCopyPass.textContent = "Copied Pass!";
      setTimeout(function () {
        btnCopyPass.textContent = "Copy Pass Summary";
      }, 2000);
    } catch (_) {}
  });

  btnCopyBuildCmd.addEventListener("click", async function () {
    try {
      await navigator.clipboard.writeText(buildCmdCode.textContent.trim());
      btnCopyBuildCmd.textContent = "Copied!";
      setTimeout(function () {
        btnCopyBuildCmd.textContent = "Copy";
      }, 2000);
    } catch (_) {}
  });

  // =========================================================================
  // 4. Sticky Scrollytelling (#scroll-story) & Scroll-Driven Card Engine
  // =========================================================================
  const storyTrack = document.getElementById("scroll-story-track");
  const storyRailFill = document.getElementById("story-rail-fill");
  const storyHudStage = document.getElementById("story-hud-stage");
  const storyActiveModule = document.getElementById("story-active-module");
  const storyProgressPct = document.getElementById("story-progress-pct");
  const storyStateBadge = document.getElementById("story-state-badge");
  const storyMetric1 = document.getElementById("story-metric-1");
  const storyMetric2 = document.getElementById("story-metric-2");
  const storyMetric3 = document.getElementById("story-metric-3");
  const storyChapters = Array.from(document.querySelectorAll(".story-chapter[data-chapter]"));
  const scrollCards = Array.from(document.querySelectorAll(".scroll-card"));

  const STORY_STATES = [
    {
      module: "VisionGazeDetector",
      badge: "OPTICAL LOCK",
      m1: "10.0 FPS ANE",
      m2: "2.0s Dwell",
      m3: "Instant Blur"
    },
    {
      module: "PowerAndLidMonitor",
      badge: "IOKIT TRIPWIRE",
      m1: "150ms Polling",
      m2: "3x/6s Anti-Flap",
      m3: "15s Grace Hold"
    },
    {
      module: "LocalAuth & BLE",
      badge: "OWNER DISARM",
      m1: "Touch ID / PIN",
      m2: "iPhone RSSI",
      m3: "< 0.5s Unlock"
    },
    {
      module: "SirenEscalation",
      badge: "LIBRARY SIREN",
      m1: "880 / 660 Hz",
      m2: "30% → 100% / 8s",
      m3: "Built-in Audio"
    }
  ];

  let activeStoryChapter = 0;

  function applyStoryChapter(chapterIdx, layerProgress) {
    const clampedIdx = Math.max(0, Math.min(3, chapterIdx));
    const state = STORY_STATES[clampedIdx];
    if (storyHudStage) {
      storyHudStage.dataset.activeChapter = String(clampedIdx);
      storyHudStage.style.setProperty("--layer-p", Math.max(0.2, Math.min(1, layerProgress)).toFixed(3));
    }
    if (clampedIdx !== activeStoryChapter) {
      activeStoryChapter = clampedIdx;
      storyChapters.forEach(function (btn, idx) {
        const isActive = idx === clampedIdx;
        btn.classList.toggle("is-active", isActive);
        btn.setAttribute("aria-pressed", isActive ? "true" : "false");
      });
    }
    if (storyActiveModule) storyActiveModule.textContent = state.module;
    if (storyStateBadge) storyStateBadge.textContent = state.badge;
    if (storyMetric1) storyMetric1.textContent = state.m1;
    if (storyMetric2) storyMetric2.textContent = state.m2;
    if (storyMetric3) storyMetric3.textContent = state.m3;
  }

  storyChapters.forEach(function (btn, idx) {
    btn.addEventListener("click", function () {
      const isStickyLayout = window.innerWidth > 900 && storyTrack && storyTrack.offsetHeight > window.innerHeight * 1.25;
      if (isStickyLayout) {
        const trackRect = storyTrack.getBoundingClientRect();
        const trackTop = window.scrollY + trackRect.top;
        const scrollable = Math.max(1, storyTrack.offsetHeight - window.innerHeight);
        const targetProgress = (idx + 0.12) / 4;
        window.scrollTo({
          top: trackTop + scrollable * targetProgress,
          behavior: "smooth"
        });
      } else {
        const pct = Math.round(((idx + 1) / 4) * 100);
        if (storyRailFill) storyRailFill.style.setProperty("--scroll-p", ((idx + 1) / 4).toFixed(3));
        if (storyProgressPct) storyProgressPct.textContent = pct + "%";
        applyStoryChapter(idx, 1);
      }
    });
  });

  const prefersReducedMotion =
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function updateScrollDrivenMotion() {
    const vh = window.innerHeight || 900;
    const maxScroll = Math.max(1, document.documentElement.scrollHeight - vh);
    const pageProgress = Math.max(0, Math.min(1, window.scrollY / maxScroll));
    document.documentElement.style.setProperty("--page-scroll", pageProgress.toFixed(4));

    if (storyTrack && window.innerWidth > 900 && !prefersReducedMotion) {
      const rect = storyTrack.getBoundingClientRect();
      const scrollable = Math.max(1, rect.height - vh);
      const rawP = -rect.top / scrollable;
      const p = Math.max(0, Math.min(1, rawP));
      const chapterFloat = p * 4;
      const chapterIdx = Math.min(3, Math.floor(chapterFloat));
      const layerProgress = chapterIdx === 3 && p >= 0.98 ? 1 : Math.max(0.2, Math.min(1, chapterFloat - chapterIdx + 0.25));

      if (storyRailFill) {
        storyRailFill.style.setProperty("--scroll-p", p.toFixed(4));
      }
      if (storyProgressPct) {
        storyProgressPct.textContent = Math.round(p * 100) + "%";
      }
      applyStoryChapter(chapterIdx, layerProgress);
    }

    if (!prefersReducedMotion) {
      scrollCards.forEach(function (card) {
        const rect = card.getBoundingClientRect();
        const cardProgress = Math.max(0, Math.min(1, (vh - rect.top) / (vh * 0.36)));
        card.style.setProperty("--card-p", cardProgress.toFixed(3));
      });
    } else {
      scrollCards.forEach(function (card) {
        card.style.setProperty("--card-p", "1");
      });
    }
  }

  let scrollRafScheduled = false;
  function requestScrollUpdate() {
    if (scrollRafScheduled) return;
    scrollRafScheduled = true;
    window.requestAnimationFrame(function () {
      scrollRafScheduled = false;
      updateScrollDrivenMotion();
    });
  }

  window.addEventListener("scroll", requestScrollUpdate, { passive: true });
  window.addEventListener("resize", requestScrollUpdate, { passive: true });
  updateScrollDrivenMotion();

  // =========================================================================
  // 5. IntersectionObserver Fallback for Scroll-Driven Entry Reveals
  // =========================================================================
  const supportsViewTimeline =
    typeof CSS !== "undefined" &&
    CSS.supports &&
    CSS.supports("animation-timeline: view()") &&
    CSS.supports("animation-range: entry");

  if (!supportsViewTimeline && "IntersectionObserver" in window) {
    const revealEls = document.querySelectorAll(".reveal-on-scroll");
    const observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12 }
    );
    revealEls.forEach(function (el) {
      observer.observe(el);
    });
  }
})();
