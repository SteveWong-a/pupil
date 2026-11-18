import * as THREE from "three";
import type { MacBookPose } from "./keyboard";

const W = 2048;
const H = 1280;

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

function drawCoverImage(ctx: CanvasRenderingContext2D, img: HTMLImageElement, w: number, h: number) {
  const iw = img.naturalWidth || img.width;
  const ih = img.naturalHeight || img.height;
  if (!iw || !ih) return false;
  const scale = Math.max(w / iw, h / ih);
  const dw = iw * scale;
  const dh = ih * scale;
  ctx.drawImage(img, (w - dw) / 2, (h - dh) / 2, dw, dh);
  return true;
}

function drawFallbackWallpaper(ctx: CanvasRenderingContext2D) {
  const bg = ctx.createLinearGradient(0, 0, W, H);
  bg.addColorStop(0, "#0d1626");
  bg.addColorStop(0.45, "#192538");
  bg.addColorStop(0.8, "#2b2429");
  bg.addColorStop(1, "#121319");
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, W, H);

  const glow = ctx.createRadialGradient(W * 0.62, H * 0.34, 40, W * 0.62, H * 0.34, 780);
  glow.addColorStop(0, "rgba(255, 145, 70, 0.28)");
  glow.addColorStop(0.5, "rgba(88, 128, 210, 0.14)");
  glow.addColorStop(1, "rgba(12, 16, 26, 0)");
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, W, H);
}

function drawVectorLockIcon(ctx: CanvasRenderingContext2D, cx: number, cy: number, color: string) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  roundRectPath(ctx, cx - 22, cy - 4, 44, 34, 8);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(cx, cy - 6, 13, Math.PI, 0, false);
  ctx.stroke();
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(cx, cy + 12, 4, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawVectorBoltIcon(ctx: CanvasRenderingContext2D, cx: number, cy: number, color: string) {
  ctx.save();
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(cx + 4, cy - 22);
  ctx.lineTo(cx - 14, cy + 2);
  ctx.lineTo(cx - 1, cy + 2);
  ctx.lineTo(cx - 6, cy + 22);
  ctx.lineTo(cx + 14, cy - 2);
  ctx.lineTo(cx + 1, cy - 2);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

function drawVectorSirenIcon(ctx: CanvasRenderingContext2D, cx: number, cy: number, color: string) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(cx - 16, cy + 16);
  ctx.lineTo(cx + 16, cy + 16);
  ctx.moveTo(cx - 12, cy + 16);
  ctx.lineTo(cx - 9, cy - 2);
  ctx.arc(cx, cy - 2, 9, Math.PI, 0, false);
  ctx.lineTo(cx + 12, cy + 16);
  ctx.stroke();
  for (const r of [20, 29]) {
    ctx.beginPath();
    ctx.arc(cx, cy - 2, r, -Math.PI * 0.78, -Math.PI * 0.22, false);
    ctx.stroke();
  }
  ctx.restore();
}

export function createScreenTexture(wallpaper: HTMLImageElement | null) {
  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext("2d")!;

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 8;

  let prevMode = -1;
  let prevBlur = -1;
  let prevCount = -1;
  let prevSiren = -1;

  function draw(pose: MacBookPose) {
    ctx.clearRect(0, 0, W, H);

    // 1. macOS Sequoia Wallpaper
    if (!wallpaper || !drawCoverImage(ctx, wallpaper, W, H)) {
      drawFallbackWallpaper(ctx);
    }

    // Subtle contrast dim so HUD and desktop window remain legible under studio softboxes
    ctx.fillStyle = "rgba(8, 10, 16, 0.34)";
    ctx.fillRect(0, 0, W, H);

    // 2. Sleek compact dark-mode Pupil Desktop Window (lower-center so upper wallpaper stays clean)
    const wx = 440;
    const wy = 590;
    const ww = 1168;
    const wh = 490;
    ctx.save();
    roundRectPath(ctx, wx, wy, ww, wh, 22);
    ctx.fillStyle = "rgba(14, 16, 22, 0.82)";
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = "rgba(255, 255, 255, 0.14)";
    ctx.stroke();

    // Titlebar
    ctx.fillStyle = "rgba(255, 255, 255, 0.04)";
    ctx.fillRect(wx + 2, wy + 2, ww - 4, 52);
    const lights: [number, string][] = [
      [wx + 32, "#FF5F56"],
      [wx + 60, "#FFBD2E"],
      [wx + 88, "#27C93F"],
    ];
    for (const [lx, lc] of lights) {
      ctx.fillStyle = lc;
      ctx.beginPath();
      ctx.arc(lx, wy + 28, 8, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.fillStyle = "rgba(236, 240, 248, 0.72)";
    ctx.font = '600 19px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText("PUPIL HARDWARE SENTINEL  ·  M4 ANE", wx + ww / 2, wy + 29);

    ctx.textAlign = "left";
    // 3 Telemetry Cards
    const cards = [
      {
        tag: "APPLE VISION ANE",
        title: "10.0 FPS Gaze Monitor",
        sub: "95ms shield · 0B disk write",
        accent: "#30D158",
      },
      {
        tag: "IOKIT TRIPWIRES",
        title: "MagSafe 3 · Lid · HID",
        sub: "150ms interrupt · no sleep",
        accent: "#FF9F0A",
      },
      {
        tag: "OWNER DISARM",
        title: "Touch ID · Companion",
        sub: "15s grace · RFC 8291 push",
        accent: "#64D2FF",
      },
    ];
    const cw = 338;
    const ch = 196;
    const gap = 28;
    cards.forEach((c, idx) => {
      const cx = wx + 48 + idx * (cw + gap);
      const cy = wy + 84;
      roundRectPath(ctx, cx, cy, cw, ch, 14);
      ctx.fillStyle = "rgba(255, 255, 255, 0.04)";
      ctx.fill();
      ctx.strokeStyle = "rgba(255, 255, 255, 0.09)";
      ctx.lineWidth = 1.5;
      ctx.stroke();

      ctx.fillStyle = c.accent;
      ctx.font = '600 15px "SF Mono", Menlo, monospace';
      ctx.fillText(c.tag, cx + 24, cy + 38);
      ctx.fillStyle = "#F4F6FA";
      ctx.font = '600 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
      ctx.fillText(c.title, cx + 24, cy + 92);
      ctx.fillStyle = "rgba(205, 212, 224, 0.70)";
      ctx.font = '400 18px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
      ctx.fillText(c.sub, cx + 24, cy + 144);
    });

    // Bottom live metrics strip inside window
    roundRectPath(ctx, wx + 48, wy + 312, ww - 96, 128, 14);
    ctx.fillStyle = "rgba(255, 255, 255, 0.03)";
    ctx.fill();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.08)";
    ctx.stroke();

    const metrics = [
      ["THERMAL GOVERNOR", "10 -> 5 -> 2 FPS"],
      ["SIREN RAMP", "30% -> 100% (8s)"],
      ["TRUSTED WI-FI", "SHA-256 BSSID"],
      ["AUDIT VAULT", "AES-256-GCM"],
    ];
    metrics.forEach(([k, v], i) => {
      const mx = wx + 80 + i * 260;
      ctx.fillStyle = "rgba(180, 190, 208, 0.62)";
      ctx.font = '600 14px "SF Mono", Menlo, monospace';
      ctx.fillText(k, mx, wy + 356);
      ctx.fillStyle = "#F5F7FA";
      ctx.font = '600 22px "SF Mono", Menlo, monospace';
      ctx.fillText(v, mx, wy + 398);
    });
    ctx.restore();

    // 3. Frosted Privacy Shield Overlay (Modes 1, 2, 3 or transitioning)
    const mode = Math.round(pose.screenMode);
    const activeShield = mode >= 1 && mode < 4;
    const blurAlpha = activeShield ? Math.max(pose.shieldBlur, mode >= 2 ? 1 : 0) : pose.shieldBlur;

    if (blurAlpha > 0.01) {
      ctx.save();
      ctx.fillStyle = `rgba(8, 10, 16, ${(0.88 * blurAlpha).toFixed(3)})`;
      ctx.fillRect(0, 0, W, H);

      // Subtle frosted interference grid
      ctx.strokeStyle = `rgba(255, 255, 255, ${(0.03 * blurAlpha).toFixed(3)})`;
      ctx.lineWidth = 1;
      for (let gx = 0; gx <= W; gx += 64) {
        ctx.beginPath();
        ctx.moveTo(gx, 0);
        ctx.lineTo(gx, H);
        ctx.stroke();
      }
      for (let gy = 0; gy <= H; gy += 64) {
        ctx.beginPath();
        ctx.moveTo(0, gy);
        ctx.lineTo(W, gy);
        ctx.stroke();
      }

      // Centered Lock / Alert Card
      const cw2 = 960;
      const ch2 = 500;
      const cx2 = (W - cw2) / 2;
      const cy2 = (H - ch2) / 2 + 12;
      ctx.globalAlpha = Math.min(1, blurAlpha * 1.15);

      roundRectPath(ctx, cx2, cy2, cw2, ch2, 28);
      ctx.fillStyle = "rgba(18, 20, 28, 0.94)";
      ctx.fill();
      const borderHex = mode === 3 ? "#FF453A" : "#FF9F0A";
      ctx.strokeStyle = mode === 3 ? `rgba(255, 69, 58, ${0.55 + 0.4 * pose.sirenPulse})` : "rgba(255, 159, 10, 0.55)";
      ctx.lineWidth = 2.5;
      ctx.stroke();

      // Badge pill
      const badgeW = mode === 3 ? 620 : 540;
      const badgeX = W / 2 - badgeW / 2;
      const badgeY = cy2 + 54;
      roundRectPath(ctx, badgeX, badgeY, badgeW, 48, 10);
      ctx.fillStyle = mode === 3 ? "rgba(255, 69, 58, 0.16)" : "rgba(255, 159, 10, 0.16)";
      ctx.fill();
      ctx.strokeStyle = borderHex;
      ctx.lineWidth = 1.5;
      ctx.stroke();

      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillStyle = borderHex;
      ctx.font = '700 20px "SF Mono", Menlo, monospace';

      if (mode === 1) {
        ctx.fillText("GAZE DETECTED  ·  PRIVACY SHIELD ACTIVE", W / 2, badgeY + 25);
        drawVectorLockIcon(ctx, W / 2, cy2 + 178, "#FF9F0A");
        ctx.fillStyle = "#F8FAFC";
        ctx.font = '700 54px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.fillText("Screen Blurred in 95ms", W / 2, cy2 + 292);
        ctx.fillStyle = "rgba(216, 224, 236, 0.78)";
        ctx.font = '400 26px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.fillText("Unrecognized face in camera field · Touch ID required to unblur", W / 2, cy2 + 372);
      } else if (mode === 2) {
        ctx.fillText("MAGSAFE 3 DISCONNECTED  ·  GRACE WINDOW", W / 2, badgeY + 25);
        const secs = Math.max(0, Math.ceil(pose.countdown));
        const ringX = W / 2;
        const ringY = cy2 + 216;
        ctx.strokeStyle = "rgba(255, 159, 10, 0.22)";
        ctx.lineWidth = 10;
        ctx.beginPath();
        ctx.arc(ringX, ringY, 72, 0, Math.PI * 2);
        ctx.stroke();
        ctx.strokeStyle = "#FF9F0A";
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.arc(ringX, ringY, 72, -Math.PI / 2, -Math.PI / 2 + (Math.max(0.05, pose.countdown / 15)) * Math.PI * 2);
        ctx.stroke();
        drawVectorBoltIcon(ctx, ringX - 160, ringY, "#FF9F0A");

        ctx.fillStyle = "#F8FAFC";
        ctx.font = '700 48px "SF Mono", Menlo, monospace';
        ctx.fillText(`${secs}s`, ringX, ringY + 3);
        ctx.font = '700 38px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.fillText(`Power Unplugged · ${secs}s to Disarm`, W / 2, cy2 + 344);
        ctx.fillStyle = "rgba(216, 224, 236, 0.78)";
        ctx.font = '400 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.fillText("Disarm via Touch ID or iPhone Companion before acoustic siren", W / 2, cy2 + 404);
      } else if (mode === 3) {
        ctx.fillText("SLEEP BLOCKED (IOPMAssertion)  ·  SIREN ACTIVE", W / 2, badgeY + 25);
        drawVectorSirenIcon(ctx, W / 2, cy2 + 162, "#FF453A");

        // Acoustic waveform bars
        const bars = 24;
        const barW = 14;
        const barGap = 10;
        const totalW = bars * (barW + barGap) - barGap;
        const startX = W / 2 - totalW / 2;
        for (let b = 0; b < bars; b++) {
          const norm = Math.abs(b - (bars - 1) / 2) / ((bars - 1) / 2);
          const amp = (0.35 + 0.65 * Math.sin((b * 0.7 + pose.sirenPulse * 4.2))) * (1 - norm * 0.45);
          const bh = 22 + Math.abs(amp) * 62 * (0.65 + 0.35 * pose.sirenPulse);
          ctx.fillStyle = b % 2 === 0 ? "#FF453A" : "#FF9F0A";
          roundRectPath(ctx, startX + b * (barW + barGap), cy2 + 266 - bh / 2, barW, bh, 5);
          ctx.fill();
        }
        ctx.fillStyle = "#F8FAFC";
        ctx.font = '700 34px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.fillText("30% -> 60% -> 100% Progressive Library-Safe Siren", W / 2, cy2 + 356);
        ctx.fillStyle = "rgba(216, 224, 236, 0.78)";
        ctx.font = '400 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.fillText("RFC 8291 Encrypted Push Dispatched to Owner iPhone", W / 2, cy2 + 408);
      }
      ctx.restore();
    }

    // 4. Retina Top Menu Bar
    ctx.save();
    ctx.fillStyle = "rgba(12, 12, 16, 0.80)";
    ctx.fillRect(0, 0, W, 54);
    ctx.fillStyle = "rgba(255, 255, 255, 0.1)";
    ctx.fillRect(0, 53, W, 1);

    ctx.fillStyle = "#F5F7FA";
    ctx.font = '600 22px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText("Pupil    File    Edit    Shield    Window    Help", 86, 28);

    // Small Apple-style geometric mark left of Pupil
    ctx.beginPath();
    ctx.arc(54, 29, 9, 0, Math.PI * 2);
    ctx.fill();

    ctx.textAlign = "right";
    ctx.fillStyle = "rgba(235, 240, 248, 0.86)";
    ctx.font = '500 21px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Wi-Fi   100% Charged   Tue 9:41 AM", W - 36, 28);

    // 5. Center Pupil Notch Pill
    const pillW = 480;
    const pillH = 68;
    const pillX = W / 2 - pillW / 2;
    roundRectPath(ctx, pillX, -12, pillW, pillH + 12, 22);
    ctx.fillStyle = "#050507";
    ctx.fill();

    let pillColor = "#30D158";
    let pillLabel = "ARMED  ·  10 FPS ANE";
    if (mode === 1) {
      pillColor = "#FF9F0A";
      pillLabel = "GAZE SHIELDED";
    } else if (mode === 2) {
      pillColor = "#FF9F0A";
      pillLabel = `UNPLUGGED  ·  ${Math.max(0, Math.ceil(pose.countdown))}s GRACE`;
    } else if (mode === 3) {
      pillColor = "#FF453A";
      pillLabel = "SIREN ACTIVE  ·  NO SLEEP";
    } else if (mode === 4) {
      pillColor = "#30D158";
      pillLabel = "DISARMED  ·  TOUCH ID";
    }

    ctx.strokeStyle = pillColor;
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.fillStyle = pillColor;
    ctx.beginPath();
    ctx.arc(pillX + 44, 34, 7, 0, Math.PI * 2);
    ctx.fill();

    ctx.textAlign = "center";
    ctx.fillStyle = "#F8FAFC";
    ctx.font = '600 21px "SF Mono", Menlo, monospace';
    ctx.fillText(pillLabel, W / 2 + 12, 35);
    ctx.restore();

    // 6. Bottom macOS Glass Dock
    ctx.save();
    roundRectPath(ctx, 564, 1172, 920, 84, 24);
    ctx.fillStyle = "rgba(22, 24, 32, 0.72)";
    ctx.fill();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.16)";
    ctx.lineWidth = 1.5;
    ctx.stroke();

    const dockColors = ["#2B7CFF", "#30D158", "#FF9F0A", "#FF453A", "#1C1E26", "#64D2FF", "#BF5AF2", "#8E8E93", "#34C759", "#0A84FF"];
    dockColors.forEach((dc, idx) => {
      const ix = 602 + idx * 86;
      const iy = 1188;
      roundRectPath(ctx, ix, iy, 52, 52, 13);
      ctx.fillStyle = dc;
      ctx.fill();
      if (idx === 4) {
        ctx.strokeStyle = "#30D158";
        ctx.lineWidth = 2.5;
        ctx.stroke();
        ctx.fillStyle = "#30D158";
        ctx.beginPath();
        ctx.arc(ix + 26, iy + 26, 9, 0, Math.PI * 2);
        ctx.fill();
      }
    });
    ctx.restore();

    texture.needsUpdate = true;
  }

  function update(pose: MacBookPose) {
    if (
      pose.screenMode === prevMode &&
      Math.abs(pose.shieldBlur - prevBlur) <= 0.003 &&
      Math.abs(pose.countdown - prevCount) <= 0.05 &&
      Math.abs(pose.sirenPulse - prevSiren) <= 0.003
    ) {
      return;
    }
    prevMode = pose.screenMode;
    prevBlur = pose.shieldBlur;
    prevCount = pose.countdown;
    prevSiren = pose.sirenPulse;
    draw(pose);
  }

  // Initial render
  draw({ lidAngle: 0, magsafeSlide: 0, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0 });

  return {
    texture,
    update,
    dispose: () => texture.dispose(),
  };
}
