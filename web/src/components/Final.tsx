import { useEffect, useState, type FormEvent, type Ref } from "react";
import { Button } from "./Button";
import styles from "./Final.module.css";

export const WAITLIST_CONFIG = {
  mode: "local" as "local" | "endpoint" | "mailto",
  endpointUrl: "",
  mailtoAddress: "",
  storageKey: "pupil.waitlist.submissions.v1",
  githubRepoUrl: "https://github.com/stevewong-a/pupil",
};

const PERSONAS = ["College Student", "Cafe / Remote Worker", "Developer"] as const;

interface PassRecord {
  email: string;
  persona: string;
  passNumber: string;
  timestamp: string;
}

function computePassCode(email: string): string {
  let hash = 418;
  for (let i = 0; i < email.length; i += 1) {
    hash = (hash * 31 + email.charCodeAt(i)) % 9000;
  }
  return `Early Access Pass #${String(1000 + hash).padStart(4, "0")}`;
}

interface FinalProps {
  ref?: Ref<HTMLElement>;
  onOpenScreenshots: () => void;
  onOpenBuild: () => void;
}

export function Final({ ref, onOpenScreenshots, onOpenBuild }: FinalProps) {
  const [email, setEmail] = useState("");
  const [persona, setPersona] = useState<string>(PERSONAS[0]);
  const [error, setError] = useState("");
  const [pass, setPass] = useState<PassRecord | null>(null);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(WAITLIST_CONFIG.storageKey);
      if (raw) {
        const parsed = JSON.parse(raw) as PassRecord[];
        if (Array.isArray(parsed) && parsed.length > 0) {
          setPass(parsed[parsed.length - 1]);
        }
      }
    } catch {
      // ignore storage errors
    }
  }, []);

  const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const trimmed = email.trim();
    if (!trimmed || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) {
      setError("Enter a valid university or work email address.");
      return;
    }
    setError("");
    const passNumber = computePassCode(trimmed);
    const record: PassRecord = {
      email: trimmed,
      persona,
      passNumber,
      timestamp: new Date().toISOString(),
    };
    try {
      const existing = JSON.parse(localStorage.getItem(WAITLIST_CONFIG.storageKey) || "[]") as PassRecord[];
      const list = Array.isArray(existing) ? existing : [];
      list.push(record);
      localStorage.setItem(WAITLIST_CONFIG.storageKey, JSON.stringify(list.slice(-20)));
    } catch {
      // ignore storage errors
    }

    if (WAITLIST_CONFIG.mode === "endpoint" && WAITLIST_CONFIG.endpointUrl) {
      try {
        await fetch(WAITLIST_CONFIG.endpointUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json", Accept: "application/json" },
          body: JSON.stringify(record),
        });
      } catch {
        // ignore network errors
      }
    }
    setPass(record);
  };

  return (
    <section ref={ref} id="waitlist" className={styles.final}>
      <h2 className={styles.title}>
        Leave your desk, <br />
        <em>keep your peace.</em>
      </h2>
      <p className={styles.closer}>Pupil for macOS 14+. Native Swift 6 on Apple Silicon and Intel.</p>

      <form className={styles.form} onSubmit={handleSubmit} noValidate>
        <div className={styles.personas} role="radiogroup" aria-label="Primary use case">
          {PERSONAS.map((item) => (
            <button
              key={item}
              type="button"
              role="radio"
              aria-checked={persona === item}
              className={`${styles.personaPill} ${persona === item ? styles.personaActive : ""}`}
              onClick={() => setPersona(item)}
            >
              {item}
            </button>
          ))}
        </div>

        <div className={styles.inputRow}>
          <label htmlFor="waitlist-email" className={styles.srOnly}>
            Email address
          </label>
          <input
            id="waitlist-email"
            type="email"
            name="email"
            required
            placeholder="you@university.edu"
            autoComplete="email"
            autoCorrect="off"
            autoCapitalize="none"
            spellCheck={false}
            aria-invalid={error ? "true" : undefined}
            value={email}
            onChange={(e) => {
              setEmail(e.target.value);
              if (error) setError("");
            }}
            className={styles.input}
          />
          <button type="submit" className={styles.submitBtn}>
            Join Waitlist
          </button>
        </div>

        <div aria-live="polite" className={styles.feedback}>
          {error ? (
            <span className={styles.error}>{error}</span>
          ) : pass ? (
            <span className={styles.passBadge}>
              <em>{pass.passNumber}</em> · Reserved for {pass.email} ({pass.persona})
            </span>
          ) : null}
        </div>
      </form>

      <div className={styles.buttons}>
        <Button
          href="#app-ui"
          ghost
          small
          onClick={(e) => {
            e.preventDefault();
            onOpenScreenshots();
          }}
        >
          Inspect macOS App UI
        </Button>
        <Button
          href="#build"
          ghost
          small
          onClick={(e) => {
            e.preventDefault();
            onOpenBuild();
          }}
        >
          Clone &amp; Build Locally
        </Button>
      </div>

      <small className={styles.footnote}>© 2026 Pupil · Local-Only macOS Security Sentinel</small>
    </section>
  );
}
