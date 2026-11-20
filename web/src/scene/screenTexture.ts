import * as THREE from "three";
import type { MacBookPose } from "./macbook";
import type { ScreenshotAtlas } from "./proceduralMaps";

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

function drawPupilEyeVector(ctx: CanvasRenderingContext2D, cx: number, cy: number, s: number, color: string) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineWidth = Math.max(2, s * 0.085);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  const halfSpan = s * 0.4;
  const cornerR = s * 0.12;
  const armLen = s * 0.14;
  for (const [sx, sy] of [
    [-1, -1],
    [1, -1],
    [-1, 1],
    [1, 1],
  ]) {
    const xc = cx + sx * halfSpan;
    const yc = cy + sy * halfSpan;
    ctx.beginPath();
    ctx.moveTo(xc - sx * (cornerR + armLen), yc);
    ctx.lineTo(xc - sx * cornerR, yc);
    ctx.quadraticCurveTo(xc, yc, xc, yc - sy * cornerR);
    ctx.lineTo(xc, yc - sy * (cornerR + armLen));
    ctx.stroke();
  }

  const eyeRx = s * 0.23;
  const eyeRy = s * 0.145;
  ctx.beginPath();
  ctx.moveTo(cx - eyeRx, cy);
  ctx.quadraticCurveTo(cx, cy - eyeRy * 1.45, cx + eyeRx, cy);
  ctx.quadraticCurveTo(cx, cy + eyeRy * 1.45, cx - eyeRx, cy);
  ctx.closePath();
  ctx.stroke();

  ctx.beginPath();
  ctx.arc(cx, cy, s * 0.068, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawPadlockIcon(ctx: CanvasRenderingContext2D, cx: number, cy: number, color: string) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineWidth = 2.6;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  roundRectPath(ctx, cx - 9, cy - 2, 18, 14, 3.5);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(cx, cy - 3, 5.5, Math.PI, 0, false);
  ctx.stroke();
  ctx.restore();
}

function drawWarningTriangle(ctx: CanvasRenderingContext2D, cx: number, cy: number, r: number, color: string) {
  ctx.save();
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(cx, cy - r);
  ctx.lineTo(cx + r * 0.96, cy + r * 0.78);
  ctx.lineTo(cx - r * 0.96, cy + r * 0.78);
  ctx.closePath();
  ctx.fill();
  ctx.fillStyle = "#111215";
  ctx.fillRect(cx - r * 0.1, cy - r * 0.35, r * 0.2, r * 0.62);
  ctx.beginPath();
  ctx.arc(cx, cy + r * 0.48, r * 0.12, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawBellBadge(ctx: CanvasRenderingContext2D, cx: number, cy: number, r: number, color: string) {
  ctx.save();
  ctx.fillStyle = color;
  ctx.strokeStyle = color;
  ctx.lineWidth = Math.max(2, r * 0.16);
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.arc(cx, cy - r * 0.08, r * 0.56, Math.PI, 0, false);
  ctx.lineTo(cx + r * 0.72, cy + r * 0.48);
  ctx.lineTo(cx - r * 0.72, cy + r * 0.48);
  ctx.closePath();
  ctx.fill();
  ctx.beginPath();
  ctx.arc(cx, cy + r * 0.68, r * 0.18, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawSpeakerWaves(ctx: CanvasRenderingContext2D, cx: number, cy: number, color: string) {
  ctx.save();
  ctx.fillStyle = color;
  ctx.strokeStyle = color;
  ctx.lineWidth = 2.4;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(cx - 11, cy - 4);
  ctx.lineTo(cx - 5, cy - 4);
  ctx.lineTo(cx + 1, cy - 9);
  ctx.lineTo(cx + 1, cy + 9);
  ctx.lineTo(cx - 5, cy + 4);
  ctx.lineTo(cx - 11, cy + 4);
  ctx.closePath();
  ctx.fill();
  for (const wr of [6, 11]) {
    ctx.beginPath();
    ctx.arc(cx + 2, cy, wr, -0.65, 0.65);
    ctx.stroke();
  }
  ctx.restore();
}

function drawAlarmAuthCard(ctx: CanvasRenderingContext2D) {
  const cw = 576;
  const ch = 660;
  const cx = (W - cw) / 2;
  const cy = (H - ch) / 2;

  ctx.save();
  ctx.shadowColor = "rgba(0, 0, 0, 0.55)";
  ctx.shadowBlur = 64;
  ctx.shadowOffsetY = 28;
  roundRectPath(ctx, cx, cy, cw, ch, 36);
  ctx.fillStyle = "rgba(28, 28, 30, 0.96)";
  ctx.fill();
  ctx.restore();

  ctx.save();
  roundRectPath(ctx, cx, cy, cw, ch, 36);
  ctx.strokeStyle = "rgba(255, 255, 255, 0.16)";
  ctx.lineWidth = 2;
  ctx.stroke();

  // 1. 52x52 (scaled 104x104) Rounded Square Badge with Crimson Bell
  const bx = W / 2 - 52;
  const by = cy + 48;
  roundRectPath(ctx, bx, by, 104, 104, 28);
  ctx.fillStyle = "rgba(255, 255, 255, 0.08)";
  ctx.fill();
  ctx.strokeStyle = "rgba(255, 255, 255, 0.14)";
  ctx.lineWidth = 2;
  ctx.stroke();
  drawBellBadge(ctx, W / 2, by + 52, 24, "#FF453A");

  // 2. Title + Crimson Source Capsule + Timestamp + Subtitle
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = "#FFFFFF";
  ctx.font = '600 30px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
  ctx.fillText("Security alarm active", W / 2, cy + 196);

  const pillW = 280;
  roundRectPath(ctx, W / 2 - pillW / 2, cy + 230, pillW, 44, 22);
  ctx.fillStyle = "rgba(255, 69, 58, 0.16)";
  ctx.fill();
  ctx.fillStyle = "#FF453A";
  ctx.font = '600 21px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
  ctx.fillText("Display Lid Closed", W / 2, cy + 252);

  ctx.fillStyle = "rgba(255, 255, 255, 0.68)";
  ctx.font = '500 20px "SF Mono", Menlo, monospace';
  ctx.fillText("Triggered at 9:41 AM (just now)", W / 2, cy + 306);

  ctx.fillStyle = "rgba(255, 255, 255, 0.62)";
  ctx.font = '400 23px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
  ctx.fillText("Enter your PIN to silence the alarm.", W / 2, cy + 352);

  // 3. PIN Input Field + Touch ID + Unlock Button + Forgot PIN
  const fx = cx + 44;
  const fw = cw - 88;
  roundRectPath(ctx, fx, cy + 394, fw, 68, 16);
  ctx.fillStyle = "rgba(0, 0, 0, 0.42)";
  ctx.fill();
  ctx.strokeStyle = "rgba(255, 69, 58, 0.55)";
  ctx.lineWidth = 2;
  ctx.stroke();

  ctx.textAlign = "left";
  ctx.fillStyle = "rgba(255, 255, 255, 0.36)";
  ctx.font = '400 25px "SF Mono", Menlo, monospace';
  ctx.fillText("Enter PIN", fx + 24, cy + 429);

  // Touch ID fingerprint rings + arrow inside input
  ctx.strokeStyle = "rgba(255, 255, 255, 0.78)";
  ctx.lineWidth = 2;
  for (const r of [6, 11, 16]) {
    ctx.beginPath();
    ctx.arc(fx + fw - 78, cy + 428, r, -Math.PI * 0.8, Math.PI * 0.8);
    ctx.stroke();
  }
  ctx.fillStyle = "rgba(255, 255, 255, 0.28)";
  ctx.beginPath();
  ctx.arc(fx + fw - 34, cy + 428, 15, 0, Math.PI * 2);
  ctx.fill();

  roundRectPath(ctx, fx, cy + 486, fw, 68, 16);
  ctx.fillStyle = "rgba(255, 255, 255, 0.9)";
  ctx.fill();
  ctx.textAlign = "center";
  ctx.fillStyle = "#111215";
  ctx.font = '600 25px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
  ctx.fillText("Unlock", W / 2, cy + 521);

  ctx.fillStyle = "rgba(255, 255, 255, 0.52)";
  ctx.font = '500 21px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
  ctx.fillText("Forgot PIN?", W / 2, cy + 598);
  ctx.restore();
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
}

function drawSettingsWindow(
  ctx: CanvasRenderingContext2D,
  img: HTMLImageElement | null,
  { x, y, w, h, scrollY = 0 }: { x: number; y: number; w: number; h: number; scrollY?: number },
) {
  ctx.save();
  ctx.shadowColor = "rgba(0, 0, 0, 0.58)";
  ctx.shadowBlur = 52;
  ctx.shadowOffsetY = 22;
  roundRectPath(ctx, x, y, w, h, 24);
  ctx.fillStyle = "#1c1c1e";
  ctx.fill();
  ctx.restore();

  if (img && (img.naturalWidth || img.width)) {
    const iw = img.naturalWidth || img.width;
    const ih = img.naturalHeight || img.height;
    const scale = w / iw;
    const headerSrcH = 78;
    const headerDstH = headerSrcH * scale;
    const footerSrcH = 136;
    const footerDstH = footerSrcH * scale;
    const bodyDstH = h - headerDstH;
    const bodySrcH = Math.min(ih - headerSrcH, bodyDstH / scale);
    const sy = Math.min(Math.max(headerSrcH, headerSrcH + scrollY), Math.max(headerSrcH, ih - bodySrcH));

    ctx.save();
    roundRectPath(ctx, x, y, w, h, 24);
    ctx.clip();

    ctx.drawImage(img, 0, 0, iw, headerSrcH, x, y, w, headerDstH);
    ctx.drawImage(img, 0, sy, iw, bodySrcH, x, y + headerDstH, w, bodyDstH);
    const fadeGrad = ctx.createLinearGradient(0, y + h - footerDstH - 36, 0, y + h);
    fadeGrad.addColorStop(0, "rgba(28, 28, 30, 0)");
    fadeGrad.addColorStop(0.35, "rgba(28, 28, 30, 0.94)");
    fadeGrad.addColorStop(1, "rgba(28, 28, 30, 0.98)");
    ctx.fillStyle = fadeGrad;
    ctx.fillRect(x, y + h - footerDstH - 36, w, footerDstH + 36);
    ctx.drawImage(img, 0, ih - footerSrcH, iw, footerSrcH, x, y + h - footerDstH, w, footerDstH);
    ctx.restore();
  }

  ctx.save();
  roundRectPath(ctx, x, y, w, h, 24);
  ctx.strokeStyle = "rgba(255, 255, 255, 0.16)";
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.restore();
}

function drawMenuBarPopover(ctx: CanvasRenderingContext2D, img: HTMLImageElement | null, x: number, y: number, w: number) {
  if (!img || !(img.naturalWidth || img.width)) return;
  const iw = img.naturalWidth || img.width;
  const ih = img.naturalHeight || img.height;
  const h = w * (ih / iw);
  ctx.save();
  ctx.shadowColor = "rgba(0, 0, 0, 0.5)";
  ctx.shadowBlur = 36;
  ctx.shadowOffsetY = 14;
  ctx.drawImage(img, x, y, w, h);
  ctx.restore();
}

export function createScreenTexture(wallpaper: HTMLImageElement | null, screenshots: ScreenshotAtlas) {
  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext("2d")!;

  const deskCanvas = document.createElement("canvas");
  deskCanvas.width = W;
  deskCanvas.height = H;
  const dctx = deskCanvas.getContext("2d")!;

  const supportsFilter = "filter" in CanvasRenderingContext2D.prototype;
  const blurCanvas = supportsFilter ? null : document.createElement("canvas");
  const blurCtx = blurCanvas ? blurCanvas.getContext("2d") : null;

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 8;

  let prevMode = -1;
  let prevBlur = -1;
  let prevCount = -1;
  let prevSiren = -1;

  function drawDesktopLayer(mode: number) {
    dctx.clearRect(0, 0, W, H);
    if (!wallpaper || !drawCoverImage(dctx, wallpaper, W, H)) {
      drawFallbackWallpaper(dctx);
    }
    dctx.fillStyle = "rgba(8, 10, 16, 0.28)";
    dctx.fillRect(0, 0, W, H);

    if (mode === 1) {
      drawSettingsWindow(dctx, screenshots.settingsGaze, { x: 584, y: 120, w: 880, h: 980, scrollY: 0 });
    } else if (mode === 4) {
      drawSettingsWindow(dctx, screenshots.settingsSensors, { x: 584, y: 120, w: 880, h: 980, scrollY: 1420 });
    } else if (mode === 5) {
      drawSettingsWindow(dctx, screenshots.settingsGeneral, { x: 340, y: 130, w: 860, h: 960, scrollY: 0 });
      drawMenuBarPopover(dctx, screenshots.menubarPopover, W - 430, 58, 360);
    } else {
      drawSettingsWindow(dctx, screenshots.settingsGeneral, { x: 380, y: 440, w: 820, h: 680, scrollY: 0 });
      drawMenuBarPopover(dctx, screenshots.menubarPopover, W - 410, 58, 340);
    }

    // Bottom macOS Glass Dock
    dctx.save();
    roundRectPath(dctx, 564, 1172, 920, 84, 24);
    dctx.fillStyle = "rgba(22, 24, 32, 0.72)";
    dctx.fill();
    dctx.strokeStyle = "rgba(255, 255, 255, 0.16)";
    dctx.lineWidth = 1.5;
    dctx.stroke();

    const dockColors = ["#2B7CFF", "#30D158", "#FF9F0A", "#FF453A", "#1C1E26", "#64D2FF", "#BF5AF2", "#8E8E93", "#34C759", "#0A84FF"];
    dockColors.forEach((dc, idx) => {
      const ix = 602 + idx * 86;
      const iy = 1188;
      roundRectPath(dctx, ix, iy, 52, 52, 13);
      dctx.fillStyle = dc;
      dctx.fill();
    });
    dctx.restore();
  }

  function draw(pose: MacBookPose) {
    const mode = Math.round(pose.screenMode);
    const activeShield = mode >= 1 && mode <= 3;
    const blurAlpha = activeShield ? Math.max(pose.shieldBlur, mode >= 2 ? 1 : 0) : pose.shieldBlur;

    drawDesktopLayer(mode);
    ctx.clearRect(0, 0, W, H);

    if (blurAlpha > 0.01) {
      ctx.save();
      const px = Math.round(blurAlpha * 34);
      if (supportsFilter) {
        if (px > 0) ctx.filter = `blur(${px}px)`;
        ctx.drawImage(deskCanvas, -28, -28, W + 56, H + 56);
      } else if (blurCanvas && blurCtx && px > 0) {
        const scale = Math.max(0.025, 1 / (1 + px * 0.45));
        const bw = Math.max(16, Math.round(W * scale));
        const bh = Math.max(10, Math.round(H * scale));
        blurCanvas.width = bw;
        blurCanvas.height = bh;
        blurCtx.imageSmoothingEnabled = true;
        blurCtx.imageSmoothingQuality = "high";
        blurCtx.drawImage(deskCanvas, 0, 0, bw, bh);
        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = "high";
        ctx.drawImage(blurCanvas, -28, -28, W + 56, H + 56);
      } else {
        ctx.drawImage(deskCanvas, -28, -28, W + 56, H + 56);
      }
      ctx.restore();

      // Native ScreenShieldView .ultraThickMaterial frosted tint (consistent across gaze blur, tamper, and alarm)
      ctx.fillStyle = `rgba(22, 24, 30, ${(0.52 * blurAlpha).toFixed(3)})`;
      ctx.fillRect(0, 0, W, H);

      // 2. Match ScreenShieldView.swift:
      //    - mode === 1 (isGazePrivacyOnly): pure frosted glass + Notch Gaze Wing ONLY (NO modal card!)
      //    - mode === 2 (isTamper): #FF6B0D perimeter outline + Tamper countdown PIN card
      //    - mode === 3 (isAlarm): #FF453A crimson perimeter outline + Security alarm active PIN card
      ctx.save();
      if (mode === 2) {
        ctx.save();
        ctx.strokeStyle = "rgba(255, 107, 13, 0.9)";
        ctx.lineWidth = 8;
        ctx.shadowColor = "rgba(255, 107, 13, 0.65)";
        ctx.shadowBlur = 24;
        ctx.strokeRect(4, 4, W - 8, H - 8);
        ctx.restore();

        if (screenshots.screenShield && (screenshots.screenShield.naturalWidth || screenshots.screenShield.width)) {
          const sw = screenshots.screenShield.naturalWidth || screenshots.screenShield.width;
          const sh = screenshots.screenShield.naturalHeight || screenshots.screenShield.height;
          ctx.globalAlpha = Math.min(1, blurAlpha * 1.1);
          const cx0 = 0.28;
          const cy0 = 0.13;
          const cw0 = 0.44;
          const ch0 = 0.74;
          ctx.drawImage(screenshots.screenShield, sw * cx0, sh * cy0, sw * cw0, sh * ch0, W * cx0, H * cy0, W * cw0, H * ch0);
        } else {
          const cw = 576;
          const ch = 620;
          const cx = (W - cw) / 2;
          const cy = (H - ch) / 2;
          ctx.globalAlpha = Math.min(1, blurAlpha * 1.1);
          roundRectPath(ctx, cx, cy, cw, ch, 36);
          ctx.fillStyle = "rgba(28, 28, 30, 0.95)";
          ctx.fill();
          ctx.strokeStyle = "rgba(255, 255, 255, 0.16)";
          ctx.lineWidth = 2;
          ctx.stroke();
          ctx.fillStyle = "#FFFFFF";
          ctx.font = '600 30px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
          ctx.textAlign = "center";
          ctx.fillText(`Tamper detected — ${Math.max(1, Math.round(pose.countdown))}s`, W / 2, cy + ch * 0.4);
          ctx.fillStyle = "#FF9F0A";
          ctx.font = '600 22px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
          ctx.fillText("AC Charger Unplugged · Enter PIN or Touch ID", W / 2, cy + ch * 0.54);
        }
      } else if (mode === 3) {
        ctx.save();
        ctx.strokeStyle = "rgba(255, 69, 58, 0.95)";
        ctx.lineWidth = 10;
        ctx.shadowColor = "rgba(255, 69, 58, 0.75)";
        ctx.shadowBlur = 28;
        ctx.strokeRect(5, 5, W - 10, H - 10);
        ctx.restore();
        ctx.globalAlpha = Math.min(1, blurAlpha * 1.1);
        drawAlarmAuthCard(ctx);
      }
      ctx.restore();
    } else {
      ctx.drawImage(deskCanvas, 0, 0);
    }

    // Retina Top Menu Bar
    ctx.save();
    ctx.fillStyle = "rgba(12, 12, 16, 0.84)";
    ctx.fillRect(0, 0, W, 54);
    ctx.fillStyle = "rgba(255, 255, 255, 0.12)";
    ctx.fillRect(0, 53, W, 1);

    ctx.fillStyle = "#F5F7FA";
    ctx.font = '600 22px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText("Pupil    File    Edit    Shield    Window    Help", 86, 28);

    ctx.beginPath();
    ctx.arc(54, 29, 9, 0, Math.PI * 2);
    ctx.fill();

    ctx.textAlign = "right";
    ctx.fillStyle = "rgba(235, 240, 248, 0.88)";
    ctx.font = '500 21px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Wi-Fi   100%   Tue 9:41 AM", W - 36, 28);
    drawPupilEyeVector(ctx, W - 332, 27, 26, "#F5F7FA");

    // Authentic MacBook Pro Hardware Notch + NotchOverlayView Flanking Wings
    const isWingActive = mode === 1 || mode === 2 || mode === 3;
    const notchW = isWingActive ? 430 : 244;
    const notchH = isWingActive ? 74 : 54;
    const notchX = W / 2 - notchW / 2;
    roundRectPath(ctx, notchX, -14, notchW, notchH + 14, 22);
    ctx.fillStyle = "#000000";
    ctx.fill();

    if (isWingActive) {
      const borderGrad = ctx.createLinearGradient(0, 0, 0, notchH);
      const borderHex = mode === 3 ? "255, 69, 58" : mode === 2 ? "255, 107, 13" : "255, 255, 255";
      const borderAlpha = mode === 1 ? 0.24 : 0.95;
      borderGrad.addColorStop(0, `rgba(${borderHex}, ${borderAlpha})`);
      borderGrad.addColorStop(1, `rgba(${borderHex}, ${(borderAlpha * 0.35).toFixed(2)})`);
      ctx.strokeStyle = borderGrad;
      ctx.lineWidth = 2;
      ctx.stroke();

      const leftWingX = notchX + 48;
      const rightWingX = notchX + notchW - 48;
      const wingY = notchH / 2 + 2;

      if (mode === 1) {
        drawPadlockIcon(ctx, leftWingX, wingY, "rgba(255, 255, 255, 0.92)");
        drawPupilEyeVector(ctx, rightWingX, wingY, 32, "rgba(255, 255, 255, 0.94)");
      } else if (mode === 2) {
        drawWarningTriangle(ctx, leftWingX, wingY, 13, "#FF9F0A");
        ctx.textAlign = "center";
        ctx.fillStyle = "#FF9F0A";
        ctx.font = '700 22px "SF Mono", Menlo, monospace';
        ctx.fillText(`${Math.max(1, Math.ceil(pose.countdown))}s`, rightWingX, wingY + 1);
      } else if (mode === 3) {
        drawBellBadge(ctx, leftWingX, wingY, 13, "#FF453A");
        drawSpeakerWaves(ctx, rightWingX, wingY, "#FF453A");
      }
    }
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

  draw({ lidAngle: 0, magsafeSlide: 0, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0, phoneMode: 0, phonePress: 0, phoneLift: 0 });

  return {
    texture,
    update,
    dispose: () => texture.dispose(),
  };
}
