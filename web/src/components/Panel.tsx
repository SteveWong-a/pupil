import type { ReactNode, Ref } from "react";
import { CHAPTER_FEATURES, type ChapterKey } from "../scene/featureShots";
import type { FeatureId } from "../scene/macbook";
import { FeatureIcon, type IconKind } from "./FeatureIcon";
import styles from "./Panel.module.css";

interface PanelProps {
  ref?: Ref<HTMLElement>;
  place: "left" | "right";
  chapter: ChapterKey;
  icon?: IconKind;
  eyebrow: string;
  title: ReactNode;
  body?: string;
  focused?: FeatureId | null;
  onFocusFeature?: (id: FeatureId) => void;
}

export function Panel({ ref, place, chapter, icon, eyebrow, title, body, focused, onFocusFeature }: PanelProps) {
  const features = CHAPTER_FEATURES[chapter];
  const isDimmed = Boolean(focused);

  return (
    <section ref={ref} className={`${styles.panel} ${styles[place]}`} data-focus-dim={isDimmed ? "true" : "false"}>
      <p className={styles.eyebrow} data-icon-hover="true">
        {icon && <FeatureIcon kind={icon} size={14} />}
        <span>{eyebrow}</span>
      </p>
      <h2 className={styles.title}>{title}</h2>
      {body && <p className={styles.body}>{body}</p>}
      {onFocusFeature && (
        <div className={styles.chips} role="group" aria-label="Inspect 3D features">
          {features.map((f) => (
            <button
              key={f.id}
              type="button"
              className={`${styles.chip} ${focused === f.id ? styles.chipActive : ""}`}
              onClick={() => onFocusFeature(f.id)}
              aria-pressed={focused === f.id}
            >
              <span>{f.title}</span>
              <span className={styles.chipIcon} aria-hidden="true">
                ↗
              </span>
            </button>
          ))}
        </div>
      )}
    </section>
  );
}
