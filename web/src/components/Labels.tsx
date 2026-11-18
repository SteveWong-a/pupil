import type { Ref } from "react";
import type { KeyPart, LayerName } from "../lib/keyboard";
import styles from "./Labels.module.css";

const LAYER_LABELS: { layer: LayerName; title: string; note: string }[] = [
  { layer: "caps", title: "Input Lock", note: "Instant shield on key or touch" },
  { layer: "switch", title: "Hardware Tripwires", note: "150ms MagSafe, lid & display" },
  { layer: "plate", title: "Apple Vision ANE", note: "10 FPS gaze blur · 0 bytes saved" },
  { layer: "foam", title: "Adaptive Governor", note: "10 → 5 → 2 FPS thermal governor" },
  { layer: "pcb", title: "Trusted Boundaries", note: "SHA-256 Wi-Fi & idle auto-arm" },
  { layer: "battery", title: "Library-Safe Siren", note: "30–100% ramp · built-in speakers" },
  { layer: "base", title: "Encrypted Vault", note: "AES-GCM log · RFC 8291 push" },
];

const PART_LABELS: { part: KeyPart; title: string; note: string }[] = [
  { part: "cap", title: "Touch ID & PIN", note: "Exponential brute-force lockout" },
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
