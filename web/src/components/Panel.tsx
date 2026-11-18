import type { ReactNode, Ref } from "react";
import { FeatureIcon, type IconKind } from "./FeatureIcon";
import styles from "./Panel.module.css";

interface PanelProps {
  ref?: Ref<HTMLElement>;
  place: "left" | "right";
  icon?: IconKind;
  eyebrow: string;
  title: ReactNode;
  body?: string;
}

export function Panel({ ref, place, icon, eyebrow, title, body }: PanelProps) {
  return (
    <section ref={ref} className={`${styles.panel} ${styles[place]}`}>
      <p className={styles.eyebrow} data-icon-hover="true">
        {icon && <FeatureIcon kind={icon} size={14} />}
        <span>{eyebrow}</span>
      </p>
      <h2 className={styles.title}>{title}</h2>
      {body && <p className={styles.body}>{body}</p>}
    </section>
  );
}
