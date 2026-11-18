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
      drawMenuBarPopover(dctx, screenshots.menubarPopover, W - 540, 62, 460);
    } else {
      drawSettingsWindow(dctx, screenshots.settingsGeneral, { x: 380, y: 440, w: 820, h: 680, scrollY: 0 });
      drawMenuBarPopover(dctx, screenshots.menubarPopover, W - 520, 64, 420);
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
      const px = Math.round(blurAlpha * 26);
      if (supportsFilter) {
        if (px > 0) ctx.filter = `blur(${px}px)`;
        ctx.drawImage(deskCanvas, -24, -24, W + 48, H + 48);
      } else if (blurCanvas && blurCtx && px > 0) {
        const scale = Math.max(0.03, 1 / (1 + px * 0.45));
        const bw = Math.max(16, Math.round(W * scale));
        const bh = Math.max(10, Math.round(H * scale));
        blurCanvas.width = bw;
        blurCanvas.height = bh;
        blurCtx.imageSmoothingEnabled = true;
        blurCtx.imageSmoothingQuality = "high";
        blurCtx.drawImage(deskCanvas, 0, 0, bw, bh);
        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = "high";
        ctx.drawImage(blurCanvas, -24, -24, W + 48, H + 48);
      } else {
        ctx.drawImage(deskCanvas, -24, -24, W + 48, H + 48);
      }
      ctx.restore();

      ctx.fillStyle = `rgba(10, 12, 18, ${(0.42 * blurAlpha).toFixed(3)})`;
      ctx.fillRect(0, 0, W, H);

      ctx.save();
      if (screenshots.screenShield && (screenshots.screenShield.naturalWidth || screenshots.screenShield.width)) {
        const sw = screenshots.screenShield.naturalWidth || screenshots.screenShield.width;
        const sh = screenshots.screenShield.naturalHeight || screenshots.screenShield.height;
        ctx.globalAlpha = Math.min(0.62, blurAlpha * 0.62);
        ctx.drawImage(screenshots.screenShield, 0, 0, W, H);

        ctx.globalAlpha = Math.min(1, blurAlpha * 1.1);
        const cx0 = 0.28;
        const cy0 = 0.13;
        const cw0 = 0.44;
        const ch0 = 0.74;
        ctx.drawImage(
          screenshots.screenShield,
          sw * cx0,
          sh * cy0,
          sw * cw0,
          sh * ch0,
          W * cx0,
          H * cy0,
          W * cw0,
          H * ch0,
        );
      } else if (mode === 2) {
        const cw = W * 0.44;
        const ch = H * 0.52;
        const cx = (W - cw) / 2;
        const cy = (H - ch) / 2;
        ctx.globalAlpha = Math.min(1, blurAlpha * 1.1);
        roundRectPath(ctx, cx, cy, cw, ch, 26);
        ctx.fillStyle = "#1E1E20";
        ctx.fill();
        ctx.strokeStyle = "rgba(255, 159, 10, 0.45)";
        ctx.lineWidth = 2;
        ctx.stroke();

        ctx.fillStyle = "#FFFFFF";
        ctx.font = '700 42px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(`Tamper detected — ${Math.max(1, Math.round(pose.countdown))}s`, W / 2, cy + ch * 0.36);

        ctx.fillStyle = "#FF9F0A";
        ctx.font = '600 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.fillText("AC Charger Unplugged · Enter PIN or Touch ID", W / 2, cy + ch * 0.54);
      }

      ctx.globalAlpha = Math.min(1, blurAlpha * 1.1);
      if (mode === 1) {
        roundRectPath(ctx, W * 0.31, H * 0.335, W * 0.38, H * 0.16, 16);
        ctx.fillStyle = "#1E1E20";
        ctx.fill();

        ctx.fillStyle = "#FFFFFF";
        ctx.font = '700 42px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText("Privacy shield active", W / 2, H * 0.368);

        const badgeW = 396;
        roundRectPath(ctx, W / 2 - badgeW / 2, H * 0.402, badgeW, 44, 22);
        ctx.fillStyle = "rgba(255, 159, 10, 0.18)";
        ctx.fill();
        ctx.fillStyle = "#FF9F0A";
        ctx.font = '600 22px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
        ctx.fillText("👁  Shoulder-Surfer Gaze Detected", W / 2, H * 0.425);

        ctx.fillStyle = "rgba(235, 238, 245, 0.78)";
        ctx.font = '500 21px "SF Mono", Menlo, monospace';
        ctx.fillText("Blurred in 95ms · 10.0 FPS Apple Vision ANE", W / 2, H * 0.468);
      } else if (mode === 3) {
        const pillW = 720;
        const pillX = W / 2 - pillW / 2;
        roundRectPath(ctx, pillX, 92, pillW, 56, 28);
        ctx.fillStyle = "rgba(40, 14, 16, 0.94)";
        ctx.fill();
        ctx.strokeStyle = "#FF453A";
        ctx.lineWidth = 2.5;
        ctx.stroke();
        ctx.fillStyle = "#FF453A";
        ctx.font = '700 22px "SF Mono", Menlo, monospace';
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText("SLEEP BLOCKED (IOPMAssertion) · SIREN 30% -> 100%", W / 2, 121);
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
    ctx.fillText("Pupil   Wi-Fi   100%   Tue 9:41 AM", W - 36, 28);

    // Expanding Center Pupil Notch Pill
    const expanded = mode >= 1 && mode <= 4;
    const pillW = expanded ? 580 : 460;
    const pillH = expanded ? 76 : 66;
    const pillX = W / 2 - pillW / 2;
    roundRectPath(ctx, pillX, -12, pillW, pillH + 12, 24);
    ctx.fillStyle = "#050507";
    ctx.fill();

    let pillColor = "#30D158";
    let pillLabel = "PUPIL ARMED · 10 FPS ANE";
    if (mode === 1) {
      pillColor = "#FF9F0A";
      pillLabel = "GAZE DETECTED · BLURRING SCREEN";
    } else if (mode === 2) {
      pillColor = "#FF9F0A";
      pillLabel = `CHARGER UNPLUGGED · ${Math.max(0, Math.ceil(pose.countdown))}S GRACE`;
    } else if (mode === 3) {
      pillColor = "#FF453A";
      pillLabel = "LID TAMPER · SIREN ACTIVE";
    } else if (mode === 4) {
      pillColor = "#30D158";
      pillLabel = "DISARMED VIA IPHONE COMPANION";
    } else if (mode === 5) {
      pillColor = "#64D2FF";
      pillLabel = "TOUCH ID VERIFIED · UNLOCKED";
    }

    ctx.strokeStyle = pillColor;
    ctx.lineWidth = 2.2;
    ctx.stroke();

    ctx.fillStyle = pillColor;
    ctx.beginPath();
    ctx.arc(pillX + 42, 34, 7, 0, Math.PI * 2);
    ctx.fill();

    ctx.textAlign = "center";
    ctx.fillStyle = "#F8FAFC";
    ctx.font = '600 20px "SF Mono", Menlo, monospace';
    ctx.fillText(pillLabel, W / 2 + 12, 35);
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

  draw({ lidAngle: 0, magsafeSlide: 0, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0, phoneMode: 0, phonePress: 0 });

  return {
    texture,
    update,
    dispose: () => texture.dispose(),
  };
}
