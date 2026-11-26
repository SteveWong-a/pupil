import type { Ref } from "react";
import { Button } from "./Button";
import buttonStyles from "./Button.module.css";
import styles from "./Hero.module.css";

interface HeroProps {
  ref?: Ref<HTMLElement>;
  cueRef?: Ref<HTMLSpanElement>;
  onWaitlist?: () => void;
  onOpenModal: () => void;
}

export function Hero({ ref, cueRef, onOpenModal }: HeroProps) {
  return (
    <header ref={ref} className={styles.hero}>
      <h1 className={styles.title}>
        Pupil watches your Mac <br />
        <em>when you can&apos;t.</em>
      </h1>
      <p className={styles.lede}>
        Step away for a minute in the library or a cafe. Pupil blurs your screen if someone peeks, and sounds an alarm if
        someone grabs your laptop.
      </p>
      <p className={styles.privacy}>
        Private by design. Gaze detection runs fully on-device and never saves a photo or video. When an alarm fires,
        one verification photo goes to your paired iPhone.
      </p>
      <div className={styles.cta}>
        <div className={styles.actions}>
          <a
            href="https://github.com/SteveWong-a/pupil/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
            className={buttonStyles.button}
          >
            Download for macOS
          </a>
          <Button
            href="#app-ui"
            ghost
            onClick={(e) => {
              e.preventDefault();
              onOpenModal();
            }}
          >
            Demo
          </Button>
        </div>
        <span ref={cueRef} className={styles.cue}>
          Scroll to see Pupil in action <span className={styles.arrow}>↓</span>
        </span>
      </div>
    </header>
  );
}
