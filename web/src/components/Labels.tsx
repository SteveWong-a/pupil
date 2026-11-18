import type { Ref } from "react";
import type { KeyPart, LayerName } from "../lib/keyboard";
import styles from "./Labels.module.css";

const LAYER_LABELS: { layer: LayerName; title: string; note: string }[] = [
  { layer: "lid", title: "Retina Display & Notch", note: "10 FPS Vision ANE · 95ms privacy blur" },
  { layer: "caps", title: "80-Key PBT & Touch ID", note: "Sapphire biometric ring · input lock" },
  { layer: "switch", title: "Mechanical Switch Matrix", note: "150ms MagSafe, lid & HID tripwires" },
  { layer: "plate", title: "CNC Unibody & Trackpad", note: "Force Touch glass · laser speaker grilles" },
  { layer: "foam", title: "Acoustic & Thermal Shield", note: "10 → 5 → 2 FPS adaptive governor" },
  { layer: "pcb", title: "Apple Silicon Logic Board", note: "M4 SoC · SHA-256 Wi-Fi · zero cloud" },
  { layer: "base", title: "100Wh Base & MagSafe 3", note: "30–100% siren · AES-GCM vault · RFC 8291" },
];

const PART_LABELS: { part: KeyPart; title: string; note: string }[] = [
  { part: "cap", title: "Sapphire Touch ID Cap", note: "Sub-second biometric disarm · lockout" },
  { part: "switch", title: "iPhone Companion", note: "RFC 8291 push · remote disarm & snapshot" },
  { part: "spring", title: "Proximity & Idle", note: "Walk-away auto-arm · closed-lid sleep safe" },
  { part: "pad", title: "Quiet Library Mode", note: "45% cap · 8-second progressive ramp" },
];

export function Labels({ ref }: { ref?: Ref<HTMLDivElement> }) {
  return (
    <div ref={ref} className={styles.labels}>
      {LAYER_LABELS.map(({ layer, title, note }) => (
        <div key={layer} className={`${styles.label} ${styles.left}`} data-layer={layer}>
          <div className={styles.box}>
            <b>{title}</b>
            <span>{note}</span>
          </div>
        </div>
      ))}
      {PART_LABELS.map(({ part, title, note }) => (
        <div key={part} className={`${styles.label} ${styles.right}`} data-part={part}>
          <div className={styles.box}>
            <b>{title}</b>
            <span>{note}</span>
          </div>
        </div>
      ))}
    </div>
  );
}
