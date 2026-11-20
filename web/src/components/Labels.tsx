import type { Ref } from "react";
import { FEATURE_LIST } from "../scene/featureShots";
import type { FeatureId } from "../scene/macbook";
import styles from "./Labels.module.css";

interface LabelsProps {
  ref?: Ref<HTMLDivElement>;
  focused: FeatureId | null;
  onFocus: (id: FeatureId) => void;
  onHover: (id: FeatureId | null) => void;
}

export function Labels({ ref, focused, onFocus, onHover }: LabelsProps) {
  return (
    <div ref={ref} className={styles.labels}>
      {FEATURE_LIST.map(({ id, chapter, side, title, note }) => {
        const isFocused = focused === id;
        return (
          <div
            key={id}
            className={`${styles.label} ${styles[side]}`}
            data-feature={id}
            data-chapter={chapter}
            data-side={side}
            data-focused={isFocused ? "true" : "false"}
            data-interactive="false"
          >
            <span className={styles.dot} aria-hidden="true" />
            <button
              type="button"
              className={styles.box}
              aria-pressed={isFocused}
              aria-label={isFocused ? `Exit focus on ${title}` : `Zoom into ${title}`}
              onClick={() => onFocus(id)}
              onPointerEnter={() => onHover(id)}
              onPointerLeave={() => onHover(null)}
            >
              <span className={styles.card}>
                <b>
                  {title}
                  <span className={styles.badge} aria-hidden="true">
                    {isFocused ? "×" : "↗"}
                  </span>
                </b>
                <span className={styles.note}>{note}</span>
              </span>
            </button>
          </div>
        );
      })}
    </div>
  );
}
