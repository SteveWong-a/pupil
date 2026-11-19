import type { Ref } from "react";
import styles from "./Loader.module.css";

interface LoaderProps {
  ref?: Ref<HTMLDivElement>;
  progress: number;
  label: string;
}

export function Loader({ ref, progress, label }: LoaderProps) {
  const clamped = Math.max(0.06, Math.min(1, progress));
  const ready = clamped >= 1;

  return (
    <div
      ref={ref}
      className={styles.veil}
      data-ready={ready ? "true" : undefined}
      role="status"
      aria-live="polite"
      aria-busy={!ready}
    >
      <div className={styles.stage}>
        <div className={styles.iris} aria-hidden="true">
          <span className={styles.reticle} />
          <span className={styles.sweep} />
          <svg className={styles.aperture} viewBox="0 0 58 58" fill="none">
            <circle
              cx="29"
              cy="29"
              r="27"
              stroke="currentColor"
              strokeWidth="1"
              strokeDasharray="3 5"
            />
          </svg>
          <span className={styles.core}>
            <img src="./assets/pupil-icon.png" alt="" width={22} height={22} className={styles.icon} />
          </span>
        </div>

        <span className={styles.wordmark}>
          <em>pupil</em> sentry
        </span>

        <div className={styles.meta}>
          <div className={styles.track} aria-hidden="true">
            <span className={styles.fill} style={{ transform: `scaleX(${clamped})` }} />
          </div>
          <progress
            className={styles.srOnly}
            value={Math.round(clamped * 100)}
            max={100}
            aria-label="Loading Pupil 3D showcase"
          />
          <span className={styles.label}>{label}</span>
        </div>
      </div>
    </div>
  );
}
