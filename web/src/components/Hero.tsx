import type { Ref } from "react";
import { Button } from "./Button";
import styles from "./Hero.module.css";

interface HeroProps {
  ref?: Ref<HTMLElement>;
  cueRef?: Ref<HTMLSpanElement>;
  onWaitlist: () => void;
  onOpenModal: () => void;
}

export function Hero({ ref, cueRef, onWaitlist, onOpenModal }: HeroProps) {
  return (
    <header ref={ref} className={styles.hero}>
      <h1 className={styles.title}>
        Step away without <br />
        <em>packing up.</em>
      </h1>
      <p className={styles.lede}>
        A notch-native security sentinel for Mac, with four core tripwires: gaze blur, power unplug, lid slam and display
        lock, built for libraries and cafes.
      </p>
      <div className={styles.cta}>
        <div className={styles.actions}>
          <Button
            href="#waitlist"
            onClick={(e) => {
              e.preventDefault();
              onWaitlist();
            }}
          >
            Join Beta Waitlist · Free
          </Button>
          <Button
            href="#app-ui"
            ghost
            onClick={(e) => {
              e.preventDefault();
              onOpenModal();
            }}
          >
            Inspect App UI
          </Button>
        </div>
        <span ref={cueRef} className={styles.cue}>
          Scroll to look inside <span className={styles.arrow}>↓</span>
        </span>
      </div>
    </header>
  );
}
