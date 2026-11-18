import type { ReactNode, Ref } from "react";
import styles from "./Panel.module.css";

interface PanelProps {
  ref?: Ref<HTMLElement>;
  place: "inside" | "vibe" | "key";
  eyebrow: string;
  title: ReactNode;
  body?: string;
}

export function Panel({ ref, place, eyebrow, title, body }: PanelProps) {
  return (
    <section ref={ref} className={`${styles.panel} ${styles[place]}`}>
      <p className={styles.eyebrow}>{eyebrow}</p>
      <h2 className={styles.title}>{title}</h2>
      {body && <p className={styles.body}>{body}</p>}
    </section>
  );
}
