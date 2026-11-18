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

export function createPhoneTexture() {
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

    ctx.clearRect(0, 0, PW, PH);

    // 1. iOS 18 Dark Titanium Wallpaper
    const bg = ctx.createLinearGradient(0, 0, PW, PH);
    bg.addColorStop(0, "#0b111e");
    bg.addColorStop(0.45, "#131c2e");
    bg.addColorStop(1, "#07090f");
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, PW, PH);

    const glow = ctx.createRadialGradient(PW * 0.5, PH * 0.28, 40, PW * 0.5, PH * 0.28, 680);
    glow.addColorStop(0, mode === 1 ? "rgba(255, 149, 0, 0.28)" : mode === 2 ? "rgba(48, 209, 88, 0.26)" : "rgba(56, 128, 255, 0.20)");
    glow.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, PW, PH);

    // 2. iOS Status Bar + Dynamic Island Live Activity
    ctx.fillStyle = "#F5F7FA";
    ctx.font = '600 34px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText("9:41", 88, 86);
    ctx.textAlign = "right";
    ctx.font = '600 28px "SF Mono", Menlo, monospace';
    ctx.fillText("5G  100%", PW - 84, 86);

    roundRect(ctx, PW / 2 - 250, 44, 500, 84, 42);
    ctx.fillStyle = "#030305";
    ctx.fill();
    ctx.strokeStyle = mode === 1 ? "#FF9F0A" : "#30D158";
    ctx.lineWidth = 2.5;
    ctx.stroke();

    ctx.fillStyle = mode === 1 ? "#FF9F0A" : "#30D158";
    ctx.beginPath();
    ctx.arc(PW / 2 - 196, 86, 10, 0, Math.PI * 2);
    ctx.fill();

    ctx.textAlign = "center";
    ctx.fillStyle = "#F8FAFC";
    ctx.font = '600 23px "SF Mono", Menlo, monospace';
    ctx.fillText(mode === 1 ? "TAMPER ALERT · 15S GRACE" : mode === 2 ? "DISARMED REMOTELY" : "BLE LINKED · -52 dBm", PW / 2 + 16, 87);

    // 3. iOS Lock Screen Clock
    ctx.fillStyle = "rgba(235, 242, 255, 0.72)";
    ctx.font = '500 36px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Tuesday, November 17", PW / 2, 224);

    ctx.fillStyle = "#FFFFFF";
    ctx.font = '700 176px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("9:41", PW / 2, 372);

    // 4. Main RFC 8291 Web Push Notification & Intruder Snapshot Card
    const cx = 64;
    const cy = 500;
    const cw = PW - 128;
    const ch = 920;
    roundRect(ctx, cx, cy, cw, ch, 48);
    ctx.fillStyle = "rgba(20, 24, 34, 0.92)";
    ctx.fill();
    ctx.strokeStyle = mode === 1 ? "rgba(255, 159, 10, 0.65)" : mode === 2 ? "rgba(48, 209, 88, 0.65)" : "rgba(255, 255, 255, 0.16)";
    ctx.lineWidth = 3;
    ctx.stroke();

    roundRect(ctx, cx + 44, cy + 44, cw - 88, 72, 20);
    ctx.fillStyle = mode === 1 ? "rgba(255, 159, 10, 0.18)" : "rgba(48, 209, 88, 0.18)";
    ctx.fill();
    ctx.fillStyle = mode === 1 ? "#FF9F0A" : "#30D158";
    ctx.font = '700 25px "SF Mono", Menlo, monospace';
    ctx.textAlign = "left";
    ctx.fillText(
      mode === 1 ? "RFC 8291 WEB PUSH · CRITICAL" : mode === 2 ? "REMOTE DISARM CONFIRMED" : "PUPIL COMPANION · ARMED",
      cx + 72,
      cy + 81,
    );

    ctx.fillStyle = "#FFFFFF";
    ctx.font = '700 44px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText(
      mode === 1 ? "AC Charger Unplugged" : mode === 2 ? "MacBook Pro Unlocked" : '16" MacBook Pro Protected',
      cx + 48,
      cy + 178,
    );

    ctx.fillStyle = "rgba(210, 220, 236, 0.82)";
    ctx.font = '400 29px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText(
      mode === 1
        ? "15s grace window active · Sleep blocked (IOPMAssertion)"
        : mode === 2
          ? "Screen shield cleared · Siren cancelled via APNs"
          : "Walk-away auto-arm & return auto-disarm active",
      cx + 48,
      cy + 236,
    );

    const sx = cx + 48;
    const sy = cy + 286;
    const sw = cw - 96;
    const sh = 380;
    roundRect(ctx, sx, sy, sw, sh, 28);
    const snapGrad = ctx.createLinearGradient(sx, sy, sx + sw, sy + sh);
    snapGrad.addColorStop(0, "#141d2b");
    snapGrad.addColorStop(1, "#0d121c");
    ctx.fillStyle = snapGrad;
    ctx.fill();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.12)";
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.fillStyle = "rgba(255, 255, 255, 0.14)";
    ctx.beginPath();
    ctx.arc(sx + sw / 2, sy + 148, 56, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(sx + sw / 2, sy + 320, 118, Math.PI, 0, false);
    ctx.fill();

    ctx.strokeStyle = mode === 1 ? "#FF9F0A" : "#30D158";
    ctx.lineWidth = 3;
    ctx.strokeRect(sx + sw / 2 - 92, sy + 72, 184, 184);

    ctx.fillStyle = mode === 1 ? "#FF9F0A" : "#30D158";
    ctx.font = '600 22px "SF Mono", Menlo, monospace';
    ctx.fillText("ENCRYPTED SNAPSHOT · AES-256-GCM", sx + 28, sy + 44);
    ctx.fillStyle = "rgba(235, 242, 255, 0.78)";
    ctx.fillText("1080p FaceTime HD · 0B Cloud Storage", sx + 28, sy + sh - 28);

    // 5. One-Tap "Disarm MacBook" Button
    const bx = cx + 48;
    const by = cy + 712 + press * 8;
    const bw = cw - 96;
    const bh = 148;
    roundRect(ctx, bx, by, bw, bh, 34);
    ctx.fillStyle = mode === 2 || press > 0.4 ? "#30D158" : "#248A3D";
    ctx.fill();
    ctx.strokeStyle = "#70FF94";
    ctx.lineWidth = press > 0.2 ? 4 : 2;
    ctx.stroke();

    ctx.textAlign = "center";
    ctx.fillStyle = "#061209";
    ctx.font = '700 38px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText(mode === 2 ? "✓ MacBook Disarmed" : "Disarm MacBook", PW / 2, by + bh / 2 + 2);

    // 6. Bluetooth Proximity & Walk-Away Auto-Arm Card at Bottom
    const px = 64;
    const py = 1470;
    const pw = PW - 128;
    const ph = 390;
    roundRect(ctx, px, py, pw, ph, 42);
    ctx.fillStyle = "rgba(18, 22, 32, 0.88)";
    ctx.fill();
    ctx.strokeStyle = "rgba(100, 210, 255, 0.35)";
    ctx.lineWidth = 2.5;
    ctx.stroke();

    ctx.textAlign = "left";
    ctx.fillStyle = "#64D2FF";
    ctx.font = '700 24px "SF Mono", Menlo, monospace';
    ctx.fillText("BLUETOOTH LE PROXIMITY RADAR", px + 48, py + 66);

    ctx.fillStyle = "#FFFFFF";
    ctx.font = '600 36px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Steve's iPhone 16 Pro · Trusted", px + 48, py + 132);

    ctx.fillStyle = "rgba(205, 216, 232, 0.78)";
    ctx.font = '400 27px -apple-system, BlinkMacSystemFont, "Instrument Sans", sans-serif';
    ctx.fillText("Auto-arms when RSSI drops below -78 dBm", px + 48, py + 192);
    ctx.fillText("Auto-disarms on return within 1.5m desk radius", px + 48, py + 236);

    roundRect(ctx, px + 48, py + 278, 360, 68, 20);
    ctx.fillStyle = "rgba(48, 209, 88, 0.16)";
    ctx.fill();
    ctx.fillStyle = "#30D158";
    ctx.font = '600 24px "SF Mono", Menlo, monospace';
    ctx.fillText("● RSSI -52 dBm (NEAR)", px + 76, py + 313);

    roundRect(ctx, px + 436, py + 278, 412, 68, 20);
    ctx.fillStyle = "rgba(100, 210, 255, 0.14)";
    ctx.fill();
    ctx.fillStyle = "#64D2FF";
    ctx.fillText("P-256 ECDH + AES-128-GCM", px + 462, py + 313);

    roundRect(ctx, PW / 2 - 180, PH - 48, 360, 14, 7);
    ctx.fillStyle = "rgba(255, 255, 255, 0.65)";
    ctx.fill();

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

  draw({ lidAngle: 0, magsafeSlide: 0, screenMode: 0, shieldBlur: 0, countdown: 15, sirenPulse: 0, phoneMode: 0, phonePress: 0 });

  return {
    texture,
    update,
    dispose: () => texture.dispose(),
  };
}
