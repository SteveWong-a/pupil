import styles from "./FeatureIcon.module.css";

export type IconKind = "eye" | "bolt" | "phone" | "touchid" | "shield";

export function FeatureIcon({ kind, size = 14 }: { kind: IconKind; size?: number }) {
  return (
    <svg
      className={`${styles.icon} ${styles[kind]}`}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {kind === "eye" && (
        <>
          <path d="M2 12s3.8-6.5 10-6.5S22 12 22 12s-3.8 6.5-10 6.5S2 12 2 12z" />
          <circle className={styles.pupil} cx="12" cy="12" r="2.8" fill="currentColor" stroke="none" />
        </>
      )}
      {kind === "bolt" && <path className={styles.strokeDraw} d="M13 2L4.5 13.5H12L11 22L19.5 10.5H12L13 2Z" />}
      {kind === "phone" && (
        <>
          <rect x="7" y="2.5" width="10" height="19" rx="2.5" />
          <line className={styles.signal} x1="10.5" y1="6" x2="13.5" y2="6" />
          <circle cx="12" cy="18" r="0.8" fill="currentColor" stroke="none" />
        </>
      )}
      {kind === "touchid" && (
        <>
          <path d="M7.5 11.5a4.5 4.5 0 0 1 9 0v1.5" />
          <path className={styles.strokeDraw} d="M10 11.5a2 2 0 0 1 4 0v4.5a3 3 0 0 1-1.5 2.6" />
          <path d="M5 12a7 7 0 0 1 14 0" />
        </>
      )}
      {kind === "shield" && (
        <>
          <path d="M12 2.5L4.5 5.8v5.5c0 4.8 3.2 9.1 7.5 10.2 4.3-1.1 7.5-5.4 7.5-10.2V5.8L12 2.5z" />
          <path className={styles.strokeDraw} d="M9.2 12.2l1.9 1.9 3.8-4.1" />
        </>
      )}
    </svg>
  );
}
