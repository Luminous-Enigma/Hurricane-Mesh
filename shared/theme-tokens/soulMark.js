/**
 * Soul Mark: a theme the person makes from a few colours of their own (Luminous, 19 Oct:
 * brought over from ArtCraft, where it was built from this app's Petal rule, "pick
 * freely, and what you have to read can always be read").
 *
 * They choose the mood: a background, an accent, how strongly cards step off the
 * background (tint), and a soft, warm or cool tone for the text. Every other colour is
 * worked out from those and MEASURED. Text colours are never picked directly. If
 * something falls short, the gentlest fix comes first: faded text is drawn a little
 * stronger; then the background moves in lightness only (its hue stays) by the smallest
 * step that works. The accent is fitted three ways (button fill, accent text, lines).
 * The source flags keep their hue, because the hue is the meaning.
 *
 * All of that is the readability guard, on unless the person turns it off. With it off,
 * the background and accent are used exactly as picked, and the result says what falls
 * below the readability line and what the guard would use instead.
 *
 * Only the seeds are saved, and a theme code carries only the seeds
 * (SM1-<bg>-<accent>-<tint>-<tone>[-open]), so a code made in ArtCraft makes the right
 * theme here, for this app's own surfaces, and the other way round.
 *
 * The ArtCraft original, with its README: Luminous-Enigma/artcraft-services,
 * frontend/apps/artcraft-webapp/src/theme/. The recipe is the same; the surfaces and the
 * text opacities are this app's. Pure: the provider, the picker and the tests all call
 * composeSoulMark, so what the tests measure is what ships.
 */

// ── Colour maths (no imports, so theme.jsx can import this) ───────────────────

const HEX = /^#[0-9a-fA-F]{6}$/;
export const isHex = (v) => typeof v === "string" && HEX.test(v);

const LINEAR = Array.from({ length: 256 }, (_, v) => {
  const c = v / 255;
  return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
});
const channels = (hex) => [1, 3, 5].map((i) => Number.parseInt(hex.slice(i, i + 2), 16));
const hexOf = (rgb) => "#" + rgb.map((v) => Math.round(Math.min(255, Math.max(0, v)))
  .toString(16).padStart(2, "0")).join("").toUpperCase();
const LUM = new Map();
function luminance(hex) {
  let l = LUM.get(hex);
  if (l === undefined) {
    const [r, g, b] = channels(hex);
    l = 0.2126 * LINEAR[r] + 0.7152 * LINEAR[g] + 0.0722 * LINEAR[b];
    if (LUM.size > 50000) LUM.clear();
    LUM.set(hex, l);
  }
  return l;
}
export function contrast(a, b) {
  const la = luminance(a), lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}
export function mix(a, b, t) {
  const ca = channels(a), cb = channels(b);
  return hexOf(ca.map((v, i) => v * (1 - t) + cb[i] * t));
}
export function toHsl(hex) {
  const [r, g, b] = channels(hex).map((v) => v / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h / 6, s, l];
}
export function fromHsl(h, s, l) {
  if (s === 0) return hexOf([l * 255, l * 255, l * 255]);
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const f = (t) => {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return hexOf([f(h + 1 / 3) * 255, f(h) * 255, f(h - 1 / 3) * 255]);
}
/** The nearest shade of hex (same hue, lightness moved as little as possible) that passes. */
function nearestLightness(hex, passes, score) {
  if (passes(hex)) return { hex, passed: true };
  const [h, s, l] = toHsl(hex);
  let best = hex, bestScore = score(hex);
  for (let step = 1; step <= 200; step++) {
    const d = step / 200;
    for (const nl of [l - d, l + d]) {
      if (nl < 0 || nl > 1) continue;
      const c = fromHsl(h, s, nl);
      if (passes(c)) return { hex: c, passed: true };
      const sc = score(c);
      if (sc > bestScore) { best = c; bestScore = sc; }
    }
  }
  return { hex: best, passed: false };
}

// ── The rules ───────────────────────────────────────────────────────────────

export const AA = 4.5;          // all text
export const NON_TEXT = 3;      // lines, rings, icons, a button's edge (aimed for)
export const BUTTON_EDGE_MIN = 1.5;
/** The opacities this app draws text at: full, and the dimmed captions (0.85, 0.7, 0.6). */
export const TEXT_OPACITIES = [1, 0.85, 0.7, 0.6];
export const MIN_TEXT_FADE = 0.4;
/** The lightness a source flag may use and still look like its colour. */
const FLAG_BAND = [0.15, 0.85];

export const SOUL_MARK_STARTER = { background: "#FDF2F7", accent: "#9B4DCA", tint: 0.5,
                                   character: "soft", guard: true };

const INKS = {
  soft: { light: { fg: "#F2F1EE", white: "#FFFFFF" }, dark: { fg: "#1A1712", white: "#0B0B0C" } },
  warm: { light: { fg: "#F7EDE2", white: "#FFFAF3" }, dark: { fg: "#2A1D14", white: "#140D08" } },
  cool: { light: { fg: "#EEF3F8", white: "#F7FBFF" }, dark: { fg: "#141B24", white: "#070B12" } },
};
/** The flags each ink starts from: the app's own (Neon Deep's on dark, Daylight's on light). */
const FLAGS = {
  light: { green: "#39FF88", orange: "#FFB020", red: "#FF4D6A" },
  dark: { green: "#1E7B4D", orange: "#A35A00", red: "#B42336" },
};
/** How far each surface steps off the background at tint 0.5 (ArtCraft's, from its default). */
const STEPS = { panel: 0.11, raised: 0.05, bubble: 0.1, input: 0.67, hair: 0.15 };

export function sanitizeSeeds(raw) {
  const r = raw ?? {};
  const tint = typeof r.tint === "number" && Number.isFinite(r.tint) ? r.tint : SOUL_MARK_STARTER.tint;
  return {
    background: isHex(r.background) ? r.background.toUpperCase() : SOUL_MARK_STARTER.background,
    accent: isHex(r.accent) ? r.accent.toUpperCase() : SOUL_MARK_STARTER.accent,
    tint: Math.min(1, Math.max(0, tint)),
    character: r.character === "warm" || r.character === "cool" ? r.character : "soft",
    guard: r.guard !== false,
  };
}

export function encodeSeeds(seeds) {
  const s = sanitizeSeeds(seeds);
  return ["SM1", s.background.slice(1), s.accent.slice(1), Math.round(s.tint * 100), s.character,
          ...(s.guard ? [] : ["open"])].join("-");
}

export function decodeSeeds(code) {
  const m = String(code ?? "").trim()
    .match(/^SM1-([0-9a-f]{6})-([0-9a-f]{6})-(\d{1,3})-(soft|warm|cool)(-open)?$/i);
  if (!m) return null;
  return sanitizeSeeds({ background: `#${m[1]}`, accent: `#${m[2]}`, tint: Number(m[3]) / 100,
                         character: m[4].toLowerCase(), guard: !m[5] });
}

// ── The ground: background, surfaces and inks ──────────────────────────────────

function buildGround(bg, pole, seeds, textFade) {
  const ink = INKS[seeds.character][pole];
  const deep = pole === "light" ? "#000000" : "#FFFFFF";
  const k = 0.5 + seeds.tint;
  const step = (a) => Math.min(0.95, a * k);
  // Sheets and text boxes sink away from the ink. On a background already at that end
  // (pure white, pure black) a step that way can't be seen, so they step toward the ink
  // instead, a little, as this app's stepTarget does: a text box must always have an edge.
  const sunk = Math.abs(luminance(mix(bg, deep, 0.18)) - luminance(bg)) >= 0.03;
  return {
    pole, bg, fg: ink.fg, white: ink.white,
    panel: sunk ? mix(bg, deep, step(STEPS.panel)) : mix(bg, ink.white, step(0.025)), // sheets, the tab bar
    raised: mix(bg, ink.white, step(STEPS.raised)),   // chosen rows, chips, quiet buttons
    aiBubble: mix(bg, ink.white, step(STEPS.bubble)), // the reading's bubble
    input: sunk ? mix(bg, deep, step(STEPS.input)) : mix(bg, ink.white, step(0.075)),   // text boxes
    hair: mix(bg, ink.white, STEPS.hair),
    flags: FLAGS[pole],
    textFade,
  };
}

const surfacesOf = (g) => [["page", g.bg], ["sheets", g.panel], ["cards", g.raised],
                           ["reading", g.aiBubble], ["text box", g.input]];
const drawnAt = (opacity, fade) => 1 - (1 - opacity) * fade;
/** Body text at every opacity, solid, on a surface. */
const inkOn = (g, surface, opacity) => mix(surface, g.fg, drawnAt(opacity, g.textFade));

/** The furthest each flag can reach inside its band, for this ink. */
function flagEdges(g) {
  const l = g.pole === "light" ? FLAG_BAND[1] - 0.01 : FLAG_BAND[0] + 0.01;
  return Object.values(g.flags).map((c) => { const [h, s] = toHsl(c); return fromHsl(h, s, l); });
}

/** Contrast of `ink` drawn at `opacity` over `surface`, on channels: the fitting calls
 *  this many thousands of times, so it skips building hex strings. */
function overlayContrast(sc, ic, opacity) {
  const keep = 1 - opacity;
  const lum = (r, g, b) => 0.2126 * LINEAR[r] + 0.7152 * LINEAR[g] + 0.0722 * LINEAR[b];
  const ls = lum(sc[0], sc[1], sc[2]);
  const ld = lum(Math.round(sc[0] * keep + ic[0] * opacity), Math.round(sc[1] * keep + ic[1] * opacity),
                 Math.round(sc[2] * keep + ic[2] * opacity));
  return ls > ld ? (ls + 0.05) / (ld + 0.05) : (ld + 0.05) / (ls + 0.05);
}

/** The worst text pair as a fraction of its floor: 1 or more means every text pair clears.
 *  It also asks that each source flag can reach AA inside its band, so a background that
 *  text only just reads on, and the flags could not, is not accepted. */
function textMargin(g) {
  let worst = Infinity;
  const edges = flagEdges(g);
  const ink = channels(g.fg);
  for (const [, s] of surfacesOf(g)) {
    const sc = channels(s);
    for (const o of TEXT_OPACITIES) {
      const m = overlayContrast(sc, ink, drawnAt(o, g.textFade)) / AA;
      if (m < worst) worst = m;
    }
    for (const e of edges) { const m = contrast(e, s) / AA; if (m < worst) worst = m; }
  }
  return worst;
}

function withBestFade(g) {
  if (textMargin(g) >= 1) return g;
  const at = (textFade) => ({ ...g, textFade });
  if (textMargin(at(MIN_TEXT_FADE)) < 1) return at(MIN_TEXT_FADE);
  let lo = MIN_TEXT_FADE, hi = 1;
  for (let i = 0; i < 12; i++) {
    const mid = (lo + hi) / 2;
    if (textMargin(at(mid)) >= 1) lo = mid; else hi = mid;
  }
  return at(Math.floor(lo * 1000) / 1000);
}

function fitGround(seeds) {
  const seedL = toHsl(seeds.background)[2];
  let best = null, other;
  for (const pole of ["light", "dark"]) {
    const strongest = (bg) => buildGround(bg, pole, seeds, MIN_TEXT_FADE);
    const fit = nearestLightness(seeds.background, (bg) => textMargin(strongest(bg)) >= 1,
                                 (bg) => textMargin(strongest(bg)));
    if (!fit.passed) continue;
    const ground = withBestFade(buildGround(fit.hex, pole, seeds, 1));
    const move = Math.abs(toHsl(fit.hex)[2] - seedL);
    const margin = ground.textFade + textMargin(ground) / 1000;
    if (!best || move < best.move - 1e-9 || (Math.abs(move - best.move) < 1e-9 && margin > best.margin)) {
      if (best) other = best.bg;
      best = { bg: fit.hex, lighter: toHsl(fit.hex)[2] > seedL, ground, move, margin };
    } else {
      other = fit.hex;
    }
  }
  if (best && other && other !== best.bg) best.alternative = other;
  return best ?? { bg: "#000000", lighter: false, ground: buildGround("#000000", "light", seeds, 1) };
}

// ── The accent ───────────────────────────────────────────────────────────────

function fitAccent(seed, g, notes) {
  const surfaces = surfacesOf(g).map(([, s]) => s);
  const worstOn = (c) => Math.min(...surfaces.map((s) => contrast(c, s)));
  const labelReads = (c) => contrast(g.white, c) >= AA;
  let fill = nearestLightness(seed, (c) => labelReads(c) && worstOn(c) >= NON_TEXT, () => 0);
  if (!fill.passed) {
    fill = nearestLightness(seed, (c) => labelReads(c) && worstOn(c) >= BUTTON_EDGE_MIN,
                            (c) => (labelReads(c) ? 1 + worstOn(c) : contrast(g.white, c) / AA));
  }
  if (!fill.passed || worstOn(fill.hex) < NON_TEXT) {
    const blends = !fill.passed || worstOn(fill.hex) < BUTTON_EDGE_MIN;
    notes.push({ kind: blends ? "warning" : "info", seed: "accent", chosen: seed, used: fill.hex,
      message: blends
        ? "On this background, buttons and your messages in this accent barely stand out from the page. Their text stays readable; another accent, or a darker or lighter background, gives them an edge."
        : "Buttons and your messages in this accent stand out from the page a little less than usual. Their text stays readable." });
  } else if (fill.hex !== seed) {
    notes.push({ kind: "adjusted", seed: "accent", chosen: seed, used: fill.hex,
      message: "Accent shade adjusted so the text on buttons and on your messages stays readable. Same hue." });
  }
  if (sameFamily(fill.hex, g.bg)) {
    notes.push({ kind: "warning", seed: "accent", chosen: seed, used: fill.hex,
      message: "Accent and background are the same colour family, so buttons stand out by brightness only." });
  }
  const text = nearestLightness(seed, (x) => worstOn(x) >= AA, worstOn).hex;
  return { fill: fill.hex, text };
}

function sameFamily(a, b) {
  const [ha, sa] = toHsl(a), [hb, sb] = toHsl(b);
  if (sa < 0.15 || sb < 0.15) return false;
  const d = Math.abs(ha - hb);
  return Math.min(d, 1 - d) < 0.04;
}

// ── The theme ────────────────────────────────────────────────────────────────

/** This app's theme keys from a fitted ground and accent. Flags go through the provider's
 *  derivedInks, which fits them (hue kept, within their band) to every surface. */
function themeOf(g, accent) {
  return {
    bg: g.bg, flat: g.bg, panel: g.panel, raised: g.raised, hair: g.hair,
    input: g.input, inputText: g.fg, ink: g.fg,
    muted: mix(g.bg, g.fg, drawnAt(0.6, g.textFade)),
    aiBubble: g.aiBubble, aiText: g.fg,
    accent: accent.text, accentFill: accent.fill, onAccent: g.white,
    userBubble: accent.fill, userText: g.white,
    ...g.flags,
    textFade: g.textFade,
  };
}

/**
 * The whole theme from the seeds: { seeds, theme, notes, shortfalls, guarded? }.
 * theme has this app's keys (flat, panel, raised, ink, accent, …).
 */
export function composeSoulMark(rawSeeds) {
  const seeds = sanitizeSeeds(rawSeeds);
  if (!seeds.guard) return composeOpen(seeds);
  const notes = [];
  const fitted = fitGround(seeds);
  const g = fitted.ground;
  if (g.textFade < 1) {
    notes.push({ kind: "adjusted", seed: "text", chosen: g.bg, used: g.bg,
      message: "Faded text (captions, hints) drawn a little stronger so it stays readable on this background." });
  }
  if (fitted.bg !== seeds.background) {
    notes.push({ kind: "adjusted", seed: "background", chosen: seeds.background, used: fitted.bg,
      message: `Background ${fitted.lighter ? "lightened" : "deepened"} so text on it stays readable. Same hue.`,
      alternative: fitted.alternative });
  }
  const accent = fitAccent(seeds.accent, g, notes);
  return { seeds, theme: themeOf(g, accent), notes, shortfalls: [] };
}

/** The guard off: background and accent exactly as picked; the better ink and the
 *  strongest fade it needs are still chosen, since neither changes a picked colour. */
function composeOpen(seeds) {
  const guarded = composeSoulMark({ ...seeds, guard: true });
  const g = ["light", "dark"]
    .map((pole) => withBestFade(buildGround(seeds.background, pole, seeds, 1)))
    .reduce((a, b) => (textMargin(b) > textMargin(a) ? b : a));
  const theme = themeOf(g, { fill: seeds.accent, text: seeds.accent });
  const notes = [];
  if (guarded.theme.flat !== seeds.background) {
    notes.push({ kind: "warning", seed: "background", chosen: seeds.background, used: guarded.theme.flat,
      message: "With the guard on, this background would be adjusted to the shade shown, so text on it reads." });
  }
  if (guarded.theme.accentFill !== seeds.accent) {
    notes.push({ kind: "warning", seed: "accent", chosen: seeds.accent, used: guarded.theme.accentFill,
      message: "With the guard on, buttons in this accent would use the shade shown, so their text reads." });
  }
  return { seeds, theme, notes, shortfalls: shortfalls(g, theme), guarded: guarded.theme };
}

/** Every pair a Soul Mark promises, with its floor, grouped as a person would name them. */
export function measure(theme) {
  const g = { bg: theme.flat, panel: theme.panel, raised: theme.raised, aiBubble: theme.aiBubble,
              input: theme.input, fg: theme.ink, textFade: theme.textFade ?? 1 };
  const out = [];
  for (const [name, s] of surfacesOf(g)) {
    for (const o of TEXT_OPACITIES) {
      out.push({ group: o >= 0.85 ? "Body text" : "Faded captions and hints",
                 what: `text ${Math.round(o * 100)}% on ${name}`, ratio: contrast(inkOn(g, s, o), s), floor: AA });
    }
    out.push({ group: "Accent-coloured text and icons", what: `accent on ${name}`,
               ratio: contrast(theme.accent, s), floor: AA });
    out.push({ group: "Buttons against the page", what: `button edge on ${name}`,
               ratio: contrast(theme.accentFill, s), floor: BUTTON_EDGE_MIN });
  }
  out.push({ group: "Button labels and your messages", what: "label on accent",
             ratio: contrast(theme.onAccent, theme.accentFill), floor: AA });
  return out;
}

function shortfalls(g, theme) {
  const all = measure(theme);
  for (const [, s] of surfacesOf(g)) {
    for (const [k, c] of Object.entries(g.flags)) {
      const fit = nearestLightness(c, (x) => toHsl(x)[2] >= FLAG_BAND[0] && toHsl(x)[2] <= FLAG_BAND[1]
        && contrast(x, s) >= AA, (x) => contrast(x, s));
      all.push({ group: "Source flags (green, orange, red)", what: `${k} on surface`,
                 ratio: contrast(fit.hex, s), floor: AA });
    }
  }
  const out = [];
  for (const group of [...new Set(all.map((m) => m.group))]) {
    const short = all.filter((m) => m.group === group && m.ratio < m.floor - 1e-9);
    if (!short.length) continue;
    const worst = short.reduce((x, y) => (y.ratio / y.floor < x.ratio / x.floor ? y : x));
    out.push({ label: group, ratio: worst.ratio, floor: worst.floor });
  }
  return out;
}

// ── Ready-made colours (ArtCraft's, with this app's own deep blue first) ─────

export const LIGHT_BACKGROUNDS = [
  ["Paper", "#FFFFFF"], ["Blush", "#FDF2F7"], ["Rose", "#F9CADE"], ["Coral", "#FFCCC4"],
  ["Peach", "#FFD8A8"], ["Butter", "#FFE066"], ["Honey", "#F3D588"], ["Mint", "#BFE3C6"],
  ["Sky", "#BFDBF1"],
];
export const DEEP_BACKGROUNDS = [
  ["Neon deep", "#070B14"], ["Night", "#0B0E14"], ["Midnight blue", "#101B44"],
  ["Deep blue", "#0D2661"], ["Royal blue", "#19206A"], ["Deep purple", "#391961"],
  ["Deep rose", "#521232"], ["Deep red", "#5D101B"], ["Reddish brown", "#441E13"],
  ["Brown", "#34241A"], ["Deep green", "#0C2F1C"],
];
export const ACCENTS = [
  ["Cyan", "#00E5FF"], ["Blue", "#2D81FF"], ["Purple", "#9B4DCA"], ["Pink", "#E86FA6"],
  ["Red", "#E23E57"], ["Amber", "#F59E0B"], ["Green", "#10B981"], ["Teal", "#1CB6BE"],
  ["Ink", "#111111"],
];
/** The hardest mid-tones: offered only with the guard off, marked as hard to read. */
export const BOLD_BACKGROUNDS = [
  ["Red", "#E23E57"], ["Crimson", "#DC143C"], ["Burnt orange", "#CC5500"],
  ["Royal blue", "#4169E1"], ["Violet", "#7A4FBF"], ["Grey", "#777777"],
  ["Emerald", "#10B981"], ["Orange", "#F59E0B"], ["Hot pink", "#E86FA6"], ["Teal", "#1CB6BE"],
];
export const TONES = [["soft", "Soft"], ["warm", "Warm"], ["cool", "Cool"]];
