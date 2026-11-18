import type { MouseEvent, Ref } from "react";
import type { SectionName } from "../scene/uiHandles";
import { Button } from "./Button";
import { FeatureIcon, type IconKind } from "./FeatureIcon";
import styles from "./Nav.module.css";

const LINKS: { name: SectionName; label: string; icon?: IconKind }[] = [
  { name: "overview", label: "Overview" },
  { name: "gaze", label: "Gaze Blur", icon: "eye" },
  { name: "tamper", label: "Tamper Alert", icon: "bolt" },
  { name: "phone", label: "Phone Link", icon: "phone" },
  { name: "macos", label: "macOS & Touch ID", icon: "touchid" },
];

interface NavProps {
  ref?: Ref<HTMLElement>;
  active: SectionName | null;
  onGo: (name: SectionName) => void;
  onWaitlist: () => void;
  onOpenModal: () => void;
}

export function Nav({ ref, active, onGo, onWaitlist, onOpenModal }: NavProps) {
  const go = (name: SectionName) => (e: MouseEvent) => {
    e.preventDefault();
    onGo(name);
  };

  return (
    <nav ref={ref} className={styles.nav} aria-label="Primary">
      <a href="#overview" className={styles.brand} onClick={go("overview")}>
        <img src="./assets/pupil-icon.png" alt="" width={24} height={24} className={styles.icon} />
        <span className={styles.wordmark}>
          <em>pupil</em> sentry
        </span>
      </a>
      <div className={styles.links}>
        {LINKS.map(({ name, label, icon }) => (
          <a
            key={name}
            href={`#${name}`}
            className={`${styles.link} ${active === name ? styles.active : ""}`}
            aria-current={active === name ? "true" : undefined}
            onClick={go(name)}
          >
            {icon && <FeatureIcon kind={icon} size={13} />}
            <span>{label}</span>
          </a>
        ))}
        <a
          href="#app-ui"
          className={styles.link}
          onClick={(e) => {
            e.preventDefault();
            onOpenModal();
          }}
        >
          App UI
        </a>
      </div>
      <Button
        href="#waitlist"
        small
        onClick={(e) => {
          e.preventDefault();
          onWaitlist();
        }}
      >
        Join Waitlist
      </Button>
    </nav>
  );
}
