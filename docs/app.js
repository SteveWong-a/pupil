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
  const badgeFlap = document.getElementById("sim-badge-flap");
  const badgeSleep = document.getElementById("sim-badge-sleep");

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
  const audioLabel = document.getElementById("sim-audio-label");

  const ENV_PRESETS = {
    library: { name: "Quiet Library", cap: 45 },
    cafe: { name: "Cafe", cap: 80 },
    park: { name: "Busy Park", cap: 100 }
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
    // Keep browser preview volume gentle and safe while reflecting 30%->100% ramp
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
      telSiren.textContent = "0% (" + preset.name + " " + preset.cap + "% cap)";
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
      badgeFlap.textContent = "Flap Guard: Ready";
      badgeSleep.textContent = "Sleep Hold: Standby";
      setNotch("amber", "Arming…", "2s exit", true);
      telState.textContent = "ARMING (2s)";
      telVision.textContent = "Calibrating ambient ROI";
      telTrigger.textContent = "Shortcut ⌃⌥⌘L";
      telSiren.textContent = "0% (" + preset.name + " " + preset.cap + "% cap)";
      setIphoneState("safe", "Arming MacBook Pro…", "Exit delay started. Sensors calibrating.", "now");
      setJournal("ArmingStarted", "Exit countdown started via ⌃⌥⌘L; calibrating room noise floor.");

      sim.armingTimer = setTimeout(function () {
        if (sim.scenario !== "arm") return;
        macbookEl.dataset.simState = "armed";
        setNotch("green", "Armed", "10.0 FPS", true);
        telState.textContent = "ARMED";
        telVision.textContent = "10.0 FPS · 0B disk";
        telTrigger.textContent = "Monitoring 4 sensors";
        setIphoneState("safe", "Armed Sentinel Active", "MacBook Pro is guarded. Lock-screen alerts ready over APNs.", "now");
        setJournal("SystemArmed", "Monitoring active. MagSafe AC, External Display, Clamshell Lid, and Vision Gaze armed.");
      }, 900);
      return;
    }

    if (scenario === "gaze") {
      macbookEl.dataset.simState = "gaze-warning";
      macbookEl.dataset.blurred = "true";
      shieldOverlay.classList.add("is-visible");
      shieldIcon.textContent = "👁️";
      shieldTitle.textContent = "Privacy Shield Active";
      shieldDetail.textContent = "Shoulder surfer gaze locked in peripheral ROI (Score 0.78 ≥ 0.52 Strict). Auto-clears when they look away.";
      modalUnlockBtn.textContent = "Dismiss Preview Blur";
      menubarPower.textContent = "MagSafe AC";
      setNotch("amber", "Gaze Detected", "Score 0.78", true);
      telState.textContent = "GAZE SHIELD";
      telVision.textContent = "10.0 FPS · Ultra 90% ROI";
      telTrigger.textContent = "Dwell 2.0s · Blink ≤350ms";
      telSiren.textContent = "Silent blur (0% audio)";
      setIphoneState("warning", "Shoulder Surfer Blocked", "On-device Apple Vision blurred workspace locally. Zero frames written to disk.", "just now");
      setJournal("GazeWarning", "Sustained peripheral gaze detected (2.0s dwell); frosted privacy blur activated.");
      return;
    }

    if (scenario === "magsafe" || scenario === "monitor") {
      const isMagSafe = scenario === "magsafe";
      sim.graceRemaining = 15;
      macbookEl.dataset.simState = isMagSafe ? "tamper-magsafe" : "tamper-display";
      macbookEl.dataset.blurred = "true";
      shieldOverlay.classList.add("is-visible");
      shieldIcon.textContent = isMagSafe ? "🔌" : "🖥️";
      shieldTitle.textContent = "Tamper detected — 15s";
      shieldDetail.textContent = isMagSafe
        ? "AC Charger Unplugged. ChargerFlapDetector active (≥3 cycles in 6s blocks re-plug bypass)."
        : "External Library Monitor Disconnected (DisplayTopologyEvaluator 1 → 0 IDs).";
      modalUnlockBtn.textContent = "Unlock via Touch ID / YubiKey";
      menubarPower.textContent = isMagSafe ? "Battery (Unplugged!)" : "MagSafe AC";
      badgeFlap.textContent = isMagSafe ? "Flap Guard: 3x/6s Armed" : "Display IDs: 1 → 0";
      setNotch("amber", isMagSafe ? "Power Unplugged" : "Monitor Unplugged", "15s", true);

      telState.textContent = "TAMPER (15s)";
      telVision.textContent = "10.0 FPS · Burst Mode";
      telTrigger.textContent = isMagSafe ? "IOPSCopyPowerSourcesInfo" : "DisplayTopologyEvaluator";
      telSiren.textContent = "Grace countdown (0%)";

      setIphoneState(
        "warning",
        isMagSafe ? "Power Unplugged on MacBook Pro" : "External Monitor Disconnected",
        "15s grace countdown started. Tap Remote Disarm if this was you.",
        "just now"
      );
      setJournal(
        isMagSafe ? "TamperPowerUnplugged" : "TamperDisplayUnplugged",
        (isMagSafe ? "AC Charger Unplugged" : "External Display Unplugged") + " — 15s grace countdown active."
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

    if (scenario === "yubikey") {
      macbookEl.dataset.simState = "disarmed-yubikey";
      macbookEl.dataset.blurred = "false";
      shieldOverlay.classList.remove("is-visible");
      menubarPower.textContent = "MagSafe AC";
      badgeFlap.textContent = "Flap Guard: Ready";
      badgeSleep.textContent = "Sleep Hold: Idle";
      setNotch("green", "YubiKey Verified", "Disarmed", true);
      telState.textContent = "DISARMED";
      telVision.textContent = "Idle (Camera off)";
      telTrigger.textContent = "USBKey 0x1050:0x0407";
      telSiren.textContent = "0% (Silenced)";
      setIphoneState("safe", "Disarmed by Owner", "Hardware key YubiKey 5C Nano (serial-pinned) verified on MacBook Pro.", "just now");
      setJournal("DisarmedUSBKey", "Disarmed instantly via YubiKey 5C Nano (VID 0x1050 : PID 0x0407, serial pinned).");
      return;
    }

    if (scenario === "siren") {
      macbookEl.dataset.simState = "alarm-siren";
      macbookEl.dataset.blurred = "true";
      shieldOverlay.classList.add("is-visible");
      shieldIcon.textContent = "🚨";
      shieldTitle.textContent = "ALARM ACTIVE — 880 / 660 Hz";
      shieldDetail.textContent = "Built-in speakers forced & unmuted. Progressive escalation ramps 30% → 100% over 8 seconds.";
      modalUnlockBtn.textContent = "Disarm Siren (PIN / Touch ID)";
      sirenMeterEl.hidden = false;
      envPillsWrap.hidden = false;
      badgeSleep.textContent = "IOPMAssertion: Sleep Blocked";
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
        telState.textContent = "ALARM LATCHED";
        telVision.textContent = "10.0 FPS · Alert Capture";
        telTrigger.textContent = "IOPMAssertion Sleep Hold";
        telSiren.textContent = effectivePct + "% (" + ENV_PRESETS[sim.env].name + ")";
        updateSirenAudioGain(effectivePct);
      };

      tickSiren();
      sim.sirenInterval = setInterval(tickSiren, 180);

      setIphoneState(
        "critical",
        "🚨 SIREN ACTIVE — MacBook Tamper Alarm",
        "Progressive 880/660 Hz siren latched. Ping Camera Snapshot or tap Remote Disarm.",
        "now"
      );
      setJournal("AlarmEscalated", "Progressive siren active (30% → 100% over 8s). Built-in speakers forced; sleep blocked.");
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
    runScenario("yubikey");
  });

  btnIphoneDisarm.addEventListener("click", function () {
    clearSimTimers();
    stopSirenAudio();
    sim.scenario = "yubikey";
    setActiveScenarioButton("yubikey");
    macbookEl.dataset.simState = "disarmed-yubikey";
    macbookEl.dataset.blurred = "false";
    shieldOverlay.classList.remove("is-visible");
    sirenMeterEl.hidden = true;
    envPillsWrap.hidden = true;
    menubarPower.textContent = "MagSafe AC";
    badgeSleep.textContent = "Sleep Hold: Idle";
    setNotch("green", "Remote Disarm", "Verified", true);
    telState.textContent = "DISARMED";
    telTrigger.textContent = "pupildisarm:// HMAC-SHA256";
    telSiren.textContent = "0% (Silenced)";
    setIphoneState("safe", "Disarmed Remotely", "Authenticated HMAC-SHA256 disarm command verified by your MacBook.", "just now");
    setJournal("DisarmedRemotely", "Authenticated pupildisarm:// command received from paired iPhone.");
  });

  btnIphoneSnapshot.addEventListener("click", function () {
    snapshotEmpty.hidden = true;
    snapshotPreview.hidden = false;
    setJournal("RemoteSnapshotSent", "Encrypted verification frame pushed to iPhone companion (pupilsnapshot://).");
  });

  audioToggleBtn.addEventListener("click", function () {
    sim.audioEnabled = !sim.audioEnabled;
    audioToggleBtn.setAttribute("aria-pressed", sim.audioEnabled ? "true" : "false");
    audioLabel.textContent = sim.audioEnabled ? "Audio Preview: On (880/660 Hz)" : "Audio Preview: Off";
    audioToggleBtn.firstElementChild.textContent = sim.audioEnabled ? "🔊" : "🔇";

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
          title: "Idle Inactivity Auto-Arm (5–30 min)",
          desc: "Polls CGEventSource HID idle duration with streak suppression and closed-lid sleep immunity—so Pupil never false-arms overnight or during Power Nap."
        },
        {
          x: 78,
          y: 48,
          title: "OS Hardware Lockdown",
          desc: "Blocks Force Quit, Command-Tab switching, Dock interaction, and Logout while the tamper Screen Shield is active."
        },
        {
          x: 68,
          y: 72,
          title: "Stepped Exit & Grace Timers (5s–30s)",
          desc: "Gives you predictable stepped time to unplug your own charger or cancel an accidental library cable bump before the siren latches."
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
          title: "Adaptive Vision Frame Rate (10 → 5 → 2 FPS)",
          desc: "Automatically throttles Apple Vision inference when battery drops below 30% or macOS thermal pressure rises, bursting back to 10 FPS on activity."
        },
        {
          x: 70,
          y: 28,
          title: "Notch Deterrent Style Tiles",
          desc: "Choose between Glance-inspired Minimal Pill notch wings or Silent Log audit mode. All camera frames remain strictly in RAM."
        },
        {
          x: 65,
          y: 42,
          title: "4-Stage Peripheral Cone (Relaxed → Ultra)",
          desc: "Strict and Ultra expand the camera Region of Interest up to 90% × 90% and lower the gaze vector threshold to catch side shoulder-surfers."
        }
      ]
    },
    sensors: {
      src: "./assets/screenshots/settings-sensors.png",
      alt: "Pupil Sensors Settings window showing Hardware Triggers, One-Time QR Phone Companion, Bluetooth Proximity, YubiKey enrollment, and Trusted Wi-Fi",
      width: 1000,
      height: 4086,
      wide: false,
      file: "SensorsSettingsPage.swift",
      hotspots: [
        {
          x: 56,
          y: 6,
          title: "Hardware Tripwires & External Display Unplug",
          desc: "Guards Power Unplug (with ChargerFlapDetector), Lid Close (with IOPMAssertion sleep-hold), Screen Lock, and External Display Hot-Unplug."
        },
        {
          x: 45,
          y: 39,
          title: "One-Time QR iPhone Pairing (RFC 8291)",
          desc: "Direct Mac-to-APNs encrypted Web Push pairing using native CryptoKit ECDH P-256 + HKDF-SHA256—zero accounts or relay databases."
        },
        {
          x: 65,
          y: 75,
          title: "YubiKey Fast Disarm & Trusted Wi-Fi Boundary",
          desc: "Pin hardware USB keys (VID:PID + serial) in an AES-GCM vault and SHA-256 hash dorm/home Wi-Fi SSIDs + router gateway MACs."
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
          title: "Force Built-In Speakers & Unmute",
          desc: "Overrides headphone/AirPods routing via CoreAudio and unmutes hardware output so plugging in a dummy jack cannot silence the alarm."
        },
        {
          x: 64,
          y: 18,
          title: "Location Environment Presets (45% / 80% / 100%)",
          desc: "One-tap acoustic ceilings for Quiet Library (45%), Cafe (80%), and Busy Park (100%) alongside smooth 30% → 100% 8s escalation."
        },
        {
          x: 68,
          y: 50,
          title: "Encrypted Tamper Journal & Markdown Export",
          desc: "Records up to 200 security events in an AES-GCM sealed ring buffer (tamper-journal.enc.json) with one-click Markdown export."
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
          title: "Live Sentinel & Power Source Header",
          desc: "Displays instant armed state, active grace countdowns, and AC/Battery power status directly inside NSStatusBar."
        },
        {
          x: 65,
          y: 47,
          title: "1-Click Privacy & Lock Toggles",
          desc: "Toggle Gaze deterrence, Blur screen on gaze, Auto-arm on lock, and Lock on input without opening the Settings window."
        },
        {
          x: 50,
          y: 75,
          title: "Dockless .accessory Architecture",
          desc: "Runs cleanly with zero Dock icon clutter; opens Settings (⌘,) on demand and blocks unauthorized Quit while armed."
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
          title: "Exact Tamper Source & Timestamp Telemetry",
          desc: "Clearly surfaces what triggered the shield (e.g., AC Charger Unplugged or External Display Unplugged) and when it happened."
        },
        {
          x: 59,
          y: 61,
          title: "Touch ID + Brute-Force Lockout (PinAttemptLimiter)",
          desc: "Supports instant Touch ID or constant-time salted SHA-256 PIN with exponential backoff (15s at 5 fails, 60s at 8, 300s + Siren at 10)."
        },
        {
          x: 50,
          y: 90,
          title: "macOS Account Password Recovery",
          desc: "Locked yourself out? Verify your macOS user password via LocalAuthentication to recover cleanly and reset lockout state."
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

  // Restore saved pass if user already signed up
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
  // 4. IntersectionObserver Fallback for Scroll-Driven Entry Reveals
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
