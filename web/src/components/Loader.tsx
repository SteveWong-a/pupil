import { useEffect, useRef, useState, type Ref } from "react";
import styles from "./Loader.module.css";

interface LoaderProps {
  ref?: Ref<HTMLDivElement>;
  sceneReady: boolean;
  onLocked: () => void;
}

interface DiscSpec {
  id: "black" | "grey" | "white";
  r: number;
  gapStart: number;
  gapEnd: number;
  targetX: number;
  targetY: number;
  initialAngle: number;
  lockDelayMs: number;
  lockDurationMs: number;
}

const DISCS: readonly DiscSpec[] = [
  {
    id: "black",
    r: 95.9,
    gapStart: 0,
    gapEnd: 36,
    targetX: 0,
    targetY: 0,
    initialAngle: 0,
    lockDelayMs: 420,
    lockDurationMs: 760,
  },
  {
    id: "grey",
    r: 61.0,
    gapStart: -18,
    gapEnd: 18,
    targetX: 16.2,
    targetY: -17.5,
    initialAngle: 120,
    lockDelayMs: 200,
    lockDurationMs: 720,
  },
  {
    id: "white",
    r: 39.2,
    gapStart: -46,
    gapEnd: -10,
    targetX: 28.7,
    targetY: -29.1,
    initialAngle: 240,
    lockDelayMs: 0,
    lockDurationMs: 700,
  },
] as const;

/** Builds a notched disc path centered at (0, 0) with a wedge cutout from gapStart to gapEnd (degrees). */
function notchedDiscPath(r: number, gapStartDeg: number, gapEndDeg: number): string {
  const s = (gapStartDeg * Math.PI) / 180;
  const e = (gapEndDeg * Math.PI) / 180;
  const x1 = +(r * Math.cos(e)).toFixed(3);
  const y1 = +(r * Math.sin(e)).toFixed(3);
  const x2 = +(r * Math.cos(s)).toFixed(3);
  const y2 = +(r * Math.sin(s)).toFixed(3);
  return `M 0 0 L ${x1} ${y1} A ${r} ${r} 0 1 1 ${x2} ${y2} Z`;
}

const PATHS = {
  black: notchedDiscPath(DISCS[0].r, DISCS[0].gapStart, DISCS[0].gapEnd),
  grey: notchedDiscPath(DISCS[1].r, DISCS[1].gapStart, DISCS[1].gapEnd),
  white: notchedDiscPath(DISCS[2].r, DISCS[2].gapStart, DISCS[2].gapEnd),
};

const SPIN_DEG_PER_SEC = 66; // ~11 RPM steady mechanical spin
const MIN_COAST_DEG = 72;
const SETTLED_BEAT_MS = 240;

const easeOutQuart = (u: number) => 1 - (1 - u) ** 4;
const easeOutCubic = (u: number) => 1 - (1 - u) ** 3;

interface DiscState {
  angle: number;
  tx: number;
  ty: number;
  locking: boolean;
  locked: boolean;
  lockStartMs: number;
  startAngle: number;
  endAngle: number;
}

export function Loader({ ref, sceneReady, onLocked }: LoaderProps) {
  const [isLocked, setIsLocked] = useState(false);

  const blackGroupRef = useRef<SVGGElement>(null);
  const greyGroupRef = useRef<SVGGElement>(null);
  const whiteGroupRef = useRef<SVGGElement>(null);

  const blackFillGradRef = useRef<SVGLinearGradientElement>(null);
  const greyFillGradRef = useRef<SVGLinearGradientElement>(null);
  const whiteFillGradRef = useRef<SVGLinearGradientElement>(null);

  const blackRimGradRef = useRef<SVGLinearGradientElement>(null);
  const greyRimGradRef = useRef<SVGLinearGradientElement>(null);
  const whiteRimGradRef = useRef<SVGLinearGradientElement>(null);

  const sceneReadyRef = useRef(sceneReady);
  const onLockedRef = useRef(onLocked);

  useEffect(() => {
    sceneReadyRef.current = sceneReady;
  }, [sceneReady]);

  useEffect(() => {
    onLockedRef.current = onLocked;
  }, [onLocked]);

  useEffect(() => {
    const groups = {
      black: blackGroupRef.current,
      grey: greyGroupRef.current,
      white: whiteGroupRef.current,
    };
    const fillGrads = {
      black: blackFillGradRef.current,
      grey: greyFillGradRef.current,
      white: whiteFillGradRef.current,
    };
    const rimGrads = {
      black: blackRimGradRef.current,
      grey: greyRimGradRef.current,
      white: whiteRimGradRef.current,
    };

    const applyTransform = (id: DiscSpec["id"], tx: number, ty: number, angle: number) => {
      const g = groups[id];
      if (g) g.setAttribute("transform", `translate(${(100 + tx).toFixed(3)} ${(100 + ty).toFixed(3)}) rotate(${angle.toFixed(3)})`);
      const counter = `rotate(${(-angle).toFixed(3)})`;
      fillGrads[id]?.setAttribute("gradientTransform", counter);
      rimGrads[id]?.setAttribute("gradientTransform", counter);
    };

    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) {
      for (const spec of DISCS) {
        applyTransform(spec.id, spec.targetX, spec.targetY, 0);
      }
      if (sceneReadyRef.current) {
        onLockedRef.current();
      }
      return;
    }

    const states: Record<DiscSpec["id"], DiscState> = {
      black: { angle: DISCS[0].initialAngle, tx: 0, ty: 0, locking: false, locked: false, lockStartMs: 0, startAngle: 0, endAngle: 0 },
      grey: { angle: DISCS[1].initialAngle, tx: 0, ty: 0, locking: false, locked: false, lockStartMs: 0, startAngle: 0, endAngle: 0 },
      white: { angle: DISCS[2].initialAngle, tx: 0, ty: 0, locking: false, locked: false, lockStartMs: 0, startAngle: 0, endAngle: 0 },
    };

    let readyAtMs: number | null = null;
    let allLockedAtMs: number | null = null;
    let notified = false;
    let lastNow = performance.now();
    let rafId = 0;

    const tick = (now: number) => {
      const dt = Math.min(0.05, Math.max(0, (now - lastNow) / 1000));
      lastNow = now;

      if (sceneReadyRef.current && readyAtMs === null) {
        readyAtMs = now;
      }

      let everyLocked = true;

      for (const spec of DISCS) {
        const st = states[spec.id];

        if (!st.locking && !st.locked) {
          st.angle += SPIN_DEG_PER_SEC * dt;
          if (readyAtMs !== null && now - readyAtMs >= spec.lockDelayMs) {
            st.locking = true;
            st.lockStartMs = now;
            st.startAngle = st.angle;
            // Nearest forward target angle (0 deg mod 360) with minimum coast arc
            const mod = ((st.angle % 360) + 360) % 360;
            const forwardDelta = (360 - mod) % 360;
            const coast = forwardDelta < MIN_COAST_DEG ? forwardDelta + 360 : forwardDelta;
            st.endAngle = st.angle + coast;
          }
        }

        if (st.locking && !st.locked) {
          const u = Math.min(1, (now - st.lockStartMs) / spec.lockDurationMs);
          const eRot = easeOutQuart(u);
          const ePos = easeOutCubic(u);
          st.angle = st.startAngle + (st.endAngle - st.startAngle) * eRot;
          st.tx = spec.targetX * ePos;
          st.ty = spec.targetY * ePos;
          if (u >= 1) {
            st.locking = false;
            st.locked = true;
            st.angle = 0;
            st.tx = spec.targetX;
            st.ty = spec.targetY;
          }
        }

        if (!st.locked) everyLocked = false;
        applyTransform(spec.id, st.tx, st.ty, st.angle);
      }

      if (everyLocked) {
        if (allLockedAtMs === null) {
          allLockedAtMs = now;
          setIsLocked(true);
        }
        if (!notified && now - allLockedAtMs >= SETTLED_BEAT_MS) {
          notified = true;
          onLockedRef.current();
          return;
        }
      }

      rafId = requestAnimationFrame(tick);
    };

    // Initial paint
    for (const spec of DISCS) {
      applyTransform(spec.id, 0, 0, spec.initialAngle);
    }
    rafId = requestAnimationFrame(tick);

    return () => cancelAnimationFrame(rafId);
  }, []);

  // Ensure reduced-motion path resolves immediately once sceneReady flips true
  useEffect(() => {
    if (!sceneReady) return;
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      onLockedRef.current();
    }
  }, [sceneReady]);

  const locked = isLocked || (sceneReady && typeof window !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches);

  return (
    <div
      ref={ref}
      className={styles.veil}
      data-locked={locked ? "true" : undefined}
      role="status"
      aria-live="polite"
      aria-busy={!locked}
    >
      <div className={styles.stage}>
        <svg className={styles.logo} viewBox="0 0 200 200" fill="none" aria-hidden="true">
          <defs>
            {/* Layered physical drop shadows between stacked anodized discs */}
            <filter id="disc-shadow-grey" x="-30%" y="-30%" width="160%" height="160%">
              <feDropShadow dx="-2.5" dy="3.5" stdDeviation="4.2" floodColor="#000000" floodOpacity="0.62" />
            </filter>
            <filter id="disc-shadow-white" x="-40%" y="-40%" width="180%" height="180%">
              <feDropShadow dx="-1.8" dy="2.8" stdDeviation="3.4" floodColor="#000000" floodOpacity="0.46" />
            </filter>

            {/* Space Black anodized aluminum catching Titanium-Blue upper-right studio light */}
            <linearGradient
              ref={blackFillGradRef}
              id="metal-black"
              gradientUnits="userSpaceOnUse"
              x1="78"
              y1="-86"
              x2="-78"
              y2="86"
            >
              <stop offset="0%" stopColor="#3c4960" />
              <stop offset="18%" stopColor="#273040" />
              <stop offset="44%" stopColor="#161920" />
              <stop offset="76%" stopColor="#0d0f13" />
              <stop offset="100%" stopColor="#1c212b" />
            </linearGradient>

            <linearGradient
              ref={blackRimGradRef}
              id="rim-black"
              gradientUnits="userSpaceOnUse"
              x1="82"
              y1="-88"
              x2="-82"
              y2="88"
            >
              <stop offset="0%" stopColor="#9cc2ff" stopOpacity="0.58" />
              <stop offset="32%" stopColor="#b8d0f2" stopOpacity="0.2" />
              <stop offset="68%" stopColor="#ffffff" stopOpacity="0.06" />
              <stop offset="100%" stopColor="#6c84aa" stopOpacity="0.22" />
            </linearGradient>

            {/* Space Grey anodized aluminum catching Titanium-Blue upper-right studio light */}
            <linearGradient
              ref={greyFillGradRef}
              id="metal-grey"
              gradientUnits="userSpaceOnUse"
              x1="50"
              y1="-54"
              x2="-50"
              y2="54"
            >
              <stop offset="0%" stopColor="#c5d6f0" />
              <stop offset="22%" stopColor="#a7b3c4" />
              <stop offset="52%" stopColor="#868f9c" />
              <stop offset="82%" stopColor="#636a75" />
              <stop offset="100%" stopColor="#7a8494" />
            </linearGradient>

            <linearGradient
              ref={greyRimGradRef}
              id="rim-grey"
              gradientUnits="userSpaceOnUse"
              x1="54"
              y1="-56"
              x2="-54"
              y2="56"
            >
              <stop offset="0%" stopColor="#e3efff" stopOpacity="0.82" />
              <stop offset="38%" stopColor="#9cc2ff" stopOpacity="0.32" />
              <stop offset="75%" stopColor="#ffffff" stopOpacity="0.1" />
              <stop offset="100%" stopColor="#000000" stopOpacity="0.28" />
            </linearGradient>

            {/* Satin Silver-White pearl aluminum catching Titanium-Blue upper-right studio light */}
            <linearGradient
              ref={whiteFillGradRef}
              id="metal-white"
              gradientUnits="userSpaceOnUse"
              x1="34"
              y1="-36"
              x2="-34"
              y2="36"
            >
              <stop offset="0%" stopColor="#ffffff" />
              <stop offset="26%" stopColor="#eef4ff" />
              <stop offset="58%" stopColor="#d7e1f0" />
              <stop offset="86%" stopColor="#bac4d4" />
              <stop offset="100%" stopColor="#d1dcf0" />
            </linearGradient>

            <linearGradient
              ref={whiteRimGradRef}
              id="rim-white"
              gradientUnits="userSpaceOnUse"
              x1="36"
              y1="-38"
              x2="-36"
              y2="38"
            >
              <stop offset="0%" stopColor="#ffffff" stopOpacity="0.95" />
              <stop offset="40%" stopColor="#b8d4ff" stopOpacity="0.52" />
              <stop offset="80%" stopColor="#ffffff" stopOpacity="0.18" />
              <stop offset="100%" stopColor="#7b8ba3" stopOpacity="0.32" />
            </linearGradient>
          </defs>

          {/* Outer Metallic Black Disc */}
          <g ref={blackGroupRef} transform="translate(100 100)">
            <path d={PATHS.black} fill="url(#metal-black)" stroke="url(#rim-black)" strokeWidth="1.2" strokeLinejoin="round" />
          </g>

          {/* Middle Metallic Grey Disc */}
          <g ref={greyGroupRef} transform="translate(100 100)" filter="url(#disc-shadow-grey)">
            <path d={PATHS.grey} fill="url(#metal-grey)" stroke="url(#rim-grey)" strokeWidth="1.15" strokeLinejoin="round" />
          </g>

          {/* Inner Metallic White Disc */}
          <g ref={whiteGroupRef} transform="translate(100 100)" filter="url(#disc-shadow-white)">
            <path d={PATHS.white} fill="url(#metal-white)" stroke="url(#rim-white)" strokeWidth="1.1" strokeLinejoin="round" />
          </g>
        </svg>

        <progress className={styles.srOnly} aria-label="Loading Pupil 3D showcase" />
      </div>
    </div>
  );
}
