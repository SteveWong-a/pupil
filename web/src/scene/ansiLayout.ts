// 16-inch MacBook Pro ANSI Magic Keyboard geometry in centimetres (1u = 1.9 cm).
// Rows run back (function row) to front (bottom modifier row).

export const U = 1.9;
export const CAP_GAP = 0.38; // spacing between adjacent keycap footprints
export const WELL_PAD = 0.07; // clearance between keycap skirt and well cutout
export const MARGIN = 0.6; // keyboard well border margin

export type ArrowDir = "left" | "up" | "down" | "right";

export interface KeyLegendDef {
  c?: string;
  t?: string;
  b?: string;
  bl?: string;
  br?: string;
  bc?: string;
  tl?: string;
  tr?: string;
  small?: boolean;
  fkey?: number;
  icon?: "touch" | "globe";
  led?: boolean;
  arrow?: ArrowDir;
  h?: number;
  align?: "top" | "bottom";
  stack?: boolean;
}

export interface KeySpec {
  id: string;
  index: number;
  row: number;
  x: number;
  z: number;
  w: number;
  d: number;
  wellW: number;
  wellD: number;
  legend: KeyLegendDef;
  letter: string | null;
}

const HALF_ROW = 0.55;

type KeyEntry = [id: string, width: number, legend: KeyLegendDef];
const single = (c: string): KeyLegendDef => ({ c });
const pair = (t: string, b: string): KeyLegendDef => ({ t, b });

const ROWS: { h: number; keys: KeyEntry[] }[] = [
  {
    h: HALF_ROW,
    keys: [
      ["esc", 1.5, { bl: "esc", small: true }],
      ...Array.from({ length: 12 }, (_, i): KeyEntry => [`F${i + 1}`, 1, { fkey: i + 1 }]),
      ["power", 1, { icon: "touch" }],
    ],
  },
  {
    h: 1,
    keys: [
      ["`", 1, pair("~", "`")],
      ["1", 1, pair("!", "1")],
      ["2", 1, pair("@", "2")],
      ["3", 1, pair("#", "3")],
      ["4", 1, pair("$", "4")],
      ["5", 1, pair("%", "5")],
      ["6", 1, pair("^", "6")],
      ["7", 1, pair("&", "7")],
      ["8", 1, pair("*", "8")],
      ["9", 1, pair("(", "9")],
      ["0", 1, pair(")", "0")],
      ["-", 1, pair("_", "–")],
      ["=", 1, pair("+", "=")],
      ["delete", 1.5, { br: "delete", small: true }],
    ],
  },
  {
    h: 1,
    keys: [
      ["tab", 1.5, { bl: "tab", tl: "⇥", small: true }],
      ..."QWERTYUIOP".split("").map((k): KeyEntry => [k, 1, single(k)]),
      ["[", 1, pair("{", "[")],
      ["]", 1, pair("}", "]")],
      ["\\", 1, pair("|", "\\")],
    ],
  },
  {
    h: 1,
    keys: [
      ["caps", 1.75, { bl: "caps lock", led: true, small: true }],
      ..."ASDFGHJKL".split("").map((k): KeyEntry => [k, 1, single(k)]),
      [";", 1, pair(":", ";")],
      ["'", 1, pair('"', "'")],
      ["return", 1.75, { br: "return", small: true }],
    ],
  },
  {
    h: 1,
    keys: [
      ["shift", 2.25, { bl: "shift", tl: "⇧", small: true }],
      ..."ZXCVBNM".split("").map((k): KeyEntry => [k, 1, single(k)]),
      [",", 1, pair("<", ",")],
      [".", 1, pair(">", ".")],
      ["/", 1, pair("?", "/")],
      ["rshift", 2.25, { br: "shift", tr: "⇧", small: true }],
    ],
  },
  {
    h: 1,
    keys: [
      ["fn", 1, { icon: "globe", tr: "fn", small: true }],
      ["control", 1, { tr: "⌃", bc: "control", small: true }],
      ["option", 1, { tr: "⌥", bc: "option", small: true }],
      ["command", 1.25, { tr: "⌘", bc: "command", small: true }],
      ["space", 3.25, {}],
      ["rcmd", 1, { tl: "⌘", bc: "command", small: true }],
      ["ropt", 1, { tl: "⌥", bc: "option", small: true }],
      ["rctrl", 1, { tl: "⌃", bc: "control", small: true }],
      ["rfn", 1, { icon: "globe", tl: "fn", small: true }],
      ["left", 1, { arrow: "left", h: 0.5, align: "bottom" }],
      ["up", 1, { arrow: "up", h: 0.5, align: "top" }],
      ["down", 1, { arrow: "down", h: 0.5, align: "bottom", stack: true }],
      ["right", 1, { arrow: "right", h: 0.5, align: "bottom" }],
    ],
  },
];

export const ROWS_DEPTH = ROWS.reduce((sum, row) => sum + row.h, 0) * U;
export const ROWS_WIDTH = 14.5 * U;

export const BODY_W = ROWS_WIDTH + MARGIN * 2;
export const BODY_D = ROWS_DEPTH + MARGIN * 2;

export const KEYS: KeySpec[] = (() => {
  const keys: KeySpec[] = [];
  let z = -ROWS_DEPTH / 2;
  ROWS.forEach((row, rowIndex) => {
    let x = -ROWS_WIDTH / 2;
    const rowDepth = row.h * U;
    for (const [id, units, opts] of row.keys) {
      const kw = units * U;
      const kh = (opts.h ?? row.h) * U;
      let cz = z + rowDepth / 2;
      if (opts.align === "bottom") cz = z + rowDepth - kh / 2;
      if (opts.align === "top") cz = z + kh / 2;
      // Down arrow shares the up arrow column.
      if (opts.stack) x -= kw;
      const capW = kw - CAP_GAP;
      const capD = kh - CAP_GAP;
      keys.push({
        id,
        index: keys.length,
        row: rowIndex,
        x: x + kw / 2,
        z: cz,
        w: capW,
        d: capD,
        wellW: capW + WELL_PAD * 2,
        wellD: capD + WELL_PAD * 2,
        legend: opts,
        letter: id.length === 1 && /[A-Z]/.test(id) ? id.toLowerCase() : null,
      });
      x += kw;
    }
    z += rowDepth;
  });
  return keys;
})();

const indexOf = (id: string) => KEYS.findIndex((k) => k.id === id);
export const HERO_KEY = indexOf("power");
export const TOUCH_ID_KEY = HERO_KEY;
