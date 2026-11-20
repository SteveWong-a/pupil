import * as THREE from "three";
import type { MacBookPose } from "./macbook";

const PW = 1024;
const PH = 2048;

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
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

// Renders the real Pupil Mobile Sentinel Companion PWA (companion.html) on OLED #000000
export function createPhoneTexture(pupilIcon: HTMLImageElement | null = null) {
  const canvas = document.createElement("canvas");
  canvas.width = PW;
  canvas.height = PH;
  const ctx = canvas.getContext("2d")!;

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 8;

  let prevMode = -1;
  let prevPress = -1;

  function draw(pose: MacBookPose) {
    const mode = Math.round(pose.phoneMode);
    const press = pose.phonePress;
    const isTamper = mode === 1;
    const isDisarmed = mode === 2;

    ctx.clearRect(0, 0, PW, PH);

    // 1. Pure OLED #000000 Companion PWA Background
    ctx.fillStyle = "#000000";
    ctx.fillRect(0, 0, PW, PH);

    // 2. iOS Status Bar + Dynamic Island
    ctx.fillStyle = "#F5F7FA";
    ctx.font = '600 32px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText("9:41", 86, 84);
    ctx.textAlign = "right";
    ctx.font = '600 26px "SF Mono", Menlo, monospace';
    ctx.fillText("5G  100%", PW - 82, 84);

    roundRect(ctx, PW / 2 - 190, 46, 380, 74, 37);
    ctx.fillStyle = "#09090b";
    ctx.fill();
    ctx.strokeStyle = isTamper ? "rgba(255, 159, 10, 0.75)" : "rgba(48, 209, 88, 0.55)";
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.fillStyle = isTamper ? "#FF9F0A" : "#30D158";
    ctx.beginPath();
    ctx.arc(PW / 2 - 140, 83, 8, 0, Math.PI * 2);
    ctx.fill();
    ctx.textAlign = "center";
    ctx.fillStyle = "#F5F7FA";
    ctx.font = '600 20px "SF Mono", Menlo, monospace';
    ctx.fillText(isTamper ? "TAMPER · 15S" : isDisarmed ? "DISARMED" : "ARMED · BLE", PW / 2 + 12, 84);

    // 3. Companion App Header (pupil-icon.png + Pupil / Mobile Sentinel Companion + Status Pill)
    const padX = 56;
    const hdrY = 176;
    const iconSize = 82;
    ctx.save();
    roundRect(ctx, padX, hdrY, iconSize, iconSize, 18);
    ctx.fillStyle = "#141414";
    ctx.fill();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.12)";
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.clip();
    if (pupilIcon && (pupilIcon.naturalWidth || pupilIcon.width)) {
      ctx.drawImage(pupilIcon, padX, hdrY, iconSize, iconSize);
    } else {
      ctx.fillStyle = "#FFFFFF";
      ctx.beginPath();
      ctx.arc(padX + iconSize / 2, hdrY + iconSize / 2, 22, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    ctx.textAlign = "left";
    ctx.fillStyle = "#EEEEEE";
    ctx.font = '600 36px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Pupil", padX + 104, hdrY + 28);
    ctx.fillStyle = "#999999";
    ctx.font = '400 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Mobile Sentinel Companion", padX + 104, hdrY + 62);

    // Header Status Pill (matches .header-status-pill in companion.html)
    const pillW = isTamper ? 276 : 230;
    const pillX = PW - padX - pillW;
    const pillY = hdrY + 11;
    roundRect(ctx, pillX, pillY, pillW, 60, 30);
    const pillAccent = isTamper ? "#FF9F0A" : "#30D158";
    ctx.fillStyle = isTamper ? "rgba(255, 159, 10, 0.14)" : "rgba(48, 209, 88, 0.12)";
    ctx.fill();
    ctx.strokeStyle = isTamper ? "rgba(255, 159, 10, 0.4)" : "rgba(48, 209, 88, 0.32)";
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.fillStyle = pillAccent;
    ctx.beginPath();
    ctx.arc(pillX + 30, pillY + 30, 8, 0, Math.PI * 2);
    ctx.fill();
    ctx.font = '500 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText(isTamper ? "Tamper Alert" : isDisarmed ? "Disarmed" : "Paired · Armed", pillX + 52, pillY + 31);

    // 4. Section 1: LOCK-SCREEN PUSH ALERTS
    const cardW = PW - padX * 2;
    ctx.fillStyle = "#999999";
    ctx.font = '500 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("LOCK-SCREEN PUSH ALERTS", padX + 16, 326);

    const c1Y = 356;
    const c1H = 344;
    roundRect(ctx, padX, c1Y, cardW, c1H, 24);
    ctx.fillStyle = "#141414";
    ctx.fill();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.10)";
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.fillStyle = "#EEEEEE";
    ctx.font = '600 30px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Direct Apple APNs Delivery", padX + 32, c1Y + 52);

    ctx.fillStyle = "#BFBFBF";
    ctx.font = '400 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("End-to-end encrypted alerts wake your locked phone", padX + 32, c1Y + 96);
    ctx.fillText("whenever your Mac detects tamper or lid triggers.", padX + 32, c1Y + 128);

    // Utility Pills (Copy Code + Test Alert)
    roundRect(ctx, padX + 32, c1Y + 168, 220, 62, 31);
    ctx.fillStyle = "rgba(255, 255, 255, 0.08)";
    ctx.fill();
    ctx.fillStyle = "#EEEEEE";
    ctx.font = '500 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.textAlign = "center";
    ctx.fillText("Copy Code", padX + 142, c1Y + 200);

    roundRect(ctx, padX + 272, c1Y + 168, 220, 62, 31);
    ctx.fillStyle = "rgba(255, 255, 255, 0.08)";
    ctx.fill();
    ctx.fillStyle = "#EEEEEE";
    ctx.fillText("Test Alert", padX + 382, c1Y + 200);

    // Status Banner inside Card 1
    ctx.textAlign = "left";
    roundRect(ctx, padX + 32, c1Y + 252, cardW - 64, 64, 16);
    ctx.fillStyle = isTamper ? "rgba(255, 159, 10, 0.12)" : "rgba(48, 209, 88, 0.10)";
    ctx.fill();
    ctx.fillStyle = isTamper ? "#FF9F0A" : "#30D158";
    ctx.font = '500 23px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText(
      isTamper
        ? "Tamper: AC Charger Unplugged · 15s grace active"
        : isDisarmed
          ? "Disarmed remotely · MacBook shield cleared"
          : "Paired to MacBook Pro · APNs ready",
      padX + 54,
      c1Y + 285,
    );

    // 5. Section 2: VERIFICATION & REMOTE CONTROL
    ctx.fillStyle = "#999999";
    ctx.font = '500 24px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("VERIFICATION & REMOTE CONTROL", padX + 16, 766);

    const c2Y = 796;
    const c2H = 980;
    roundRect(ctx, padX, c2Y, cardW, c2H, 24);
    ctx.fillStyle = "#141414";
    ctx.fill();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.10)";
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.fillStyle = "#EEEEEE";
    ctx.font = '600 30px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Verification Snapshot", padX + 32, c2Y + 54);
    ctx.fillStyle = "#BFBFBF";
    ctx.font = '400 23px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Inspect the captured frame before disarming.", padX + 32, c2Y + 94);

    // Refresh Photo pill
    roundRect(ctx, PW - padX - 230, c2Y + 34, 198, 56, 28);
    ctx.fillStyle = "rgba(255, 255, 255, 0.08)";
    ctx.fill();
    ctx.textAlign = "center";
    ctx.fillStyle = "#EEEEEE";
    ctx.font = '500 22px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Refresh Photo", PW - padX - 131, c2Y + 63);

    // 16:9 Verification Snapshot Frame
    const sx = padX + 32;
    const sy = c2Y + 136;
    const sw = cardW - 64;
    const sh = 460;
    roundRect(ctx, sx, sy, sw, sh, 20);
    const snapGrad = ctx.createLinearGradient(sx, sy, sx + sw, sy + sh);
    snapGrad.addColorStop(0, "#141923");
    snapGrad.addColorStop(1, "#0b0d12");
    ctx.fillStyle = snapGrad;
    ctx.fill();
    ctx.strokeStyle = isTamper ? "rgba(255, 159, 10, 0.45)" : "rgba(255, 255, 255, 0.12)";
    ctx.lineWidth = 2;
    ctx.stroke();

    // Camera viewfinder silhouette & FaceTime ROI box
    ctx.fillStyle = "rgba(255, 255, 255, 0.14)";
    ctx.beginPath();
    ctx.arc(sx + sw / 2, sy + 178, 66, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(sx + sw / 2, sy + 382, 138, Math.PI, 0, false);
    ctx.fill();

    ctx.strokeStyle = isTamper ? "#FF9F0A" : "#30D158";
    ctx.lineWidth = 3;
    ctx.strokeRect(sx + sw / 2 - 110, sy + 88, 220, 220);

    ctx.textAlign = "left";
    ctx.fillStyle = "#999999";
    ctx.font = '500 22px "SF Mono", Menlo, monospace';
    ctx.fillText(isTamper ? "Alert frame · Just now" : "1080p FaceTime HD · On-device", sx + 22, sy + sh - 28);
    ctx.textAlign = "right";
    ctx.fillText("AES-256-GCM", sx + sw - 22, sy + sh - 28);

    // Divider
    ctx.fillStyle = "rgba(255, 255, 255, 0.08)";
    ctx.fillRect(padX + 32, c2Y + 634, cardW - 64, 2);

    // Remote Disarm Row (matches companion.html lines 646-654)
    ctx.textAlign = "left";
    ctx.fillStyle = "#EEEEEE";
    ctx.font = '600 30px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Remote Disarm", padX + 32, c2Y + 690);
    ctx.fillStyle = "#BFBFBF";
    ctx.font = '400 23px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Send an authenticated disarm command if false alarm.", padX + 32, c2Y + 730);

    const btnY = c2Y + 780 + press * 8;
    roundRect(ctx, padX + 32, btnY, cardW - 64, 114, 22);
    ctx.fillStyle = isDisarmed ? "#30D158" : isTamper ? "#FF453A" : "#0A84FF";
    ctx.fill();
    ctx.textAlign = "center";
    ctx.fillStyle = isDisarmed ? "#07140B" : "#FFFFFF";
    ctx.font = '600 31px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText(isDisarmed ? "✓  MacBook Disarmed" : "Disarm Mac (False Alarm)", PW / 2, btnY + 58);

    // 6. Footer
    ctx.fillStyle = "#999999";
    ctx.font = '400 23px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Encrypted alert to your iPhone", PW / 2, 1890);

    texture.needsUpdate = true;
  }

  function update(pose: MacBookPose) {
    if (pose.phoneMode === prevMode && Math.abs(pose.phonePress - prevPress) <= 0.01) {
      return;
    }
    prevMode = pose.phoneMode;
    prevPress = pose.phonePress;
    draw(pose);
  }

  draw({ lidAngle: 0, magsafeSlide: 0, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0, phoneMode: 0, phonePress: 0, phoneLift: 0 });

  return {
    texture,
    update,
    dispose: () => texture.dispose(),
  };
}
