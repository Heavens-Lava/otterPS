// css-values.js - Small, dependency-free helpers for reading and writing CSS
// values in the designer: lengths, box shorthands and media conditions.

const LENGTH_PATTERN = /^(-?\d*\.?\d+)(px|%|em|rem|vw|vh|vmin|vmax|fr|ch|pt|deg|s|ms)?$/i;

// "16px" -> { num: 16, unit: 'px' }; "1.5" -> { num: 1.5, unit: '' }; "auto" -> null
export function parseLength(text) {
  if (text === null || text === undefined) return null;
  const match = String(text).trim().match(LENGTH_PATTERN);
  if (!match) return null;
  return { num: Number(match[1]), unit: (match[2] || '').toLowerCase() };
}

export function formatNumber(num) {
  // Avoid float noise such as 0.30000000000000004 while scrubbing.
  return String(Math.round(num * 1000) / 1000);
}

export function formatLength(num, unit) {
  if (num === 0 && unit !== '%' && unit !== 'fr') return '0';
  return `${formatNumber(num)}${unit || ''}`;
}

// Change a numeric CSS value by `delta` steps, keeping its unit.
// Values without a number (auto, none) start from `fallback`.
export function stepLength(text, delta, defaultUnit = 'px', fallback = 0) {
  const parsed = parseLength(text);
  const unit = parsed ? (parsed.unit || (defaultUnit === '' ? '' : defaultUnit)) : defaultUnit;
  const base = parsed ? parsed.num : fallback;
  return formatLength(base + delta, unit);
}

// A bare number typed into a length field means pixels.
export function normalizeLengthInput(text, defaultUnit = 'px') {
  const value = String(text ?? '').trim();
  if (value === '') return '';
  if (/^-?\d*\.?\d+$/.test(value) && defaultUnit) {
    return Number(value) === 0 ? '0' : `${value}${defaultUnit}`;
  }
  return value;
}

// Split a CSS value on top-level whitespace (not inside parentheses).
export function splitTopLevel(value) {
  const parts = [];
  let depth = 0;
  let current = '';
  for (const ch of String(value || '').trim()) {
    if (ch === '(') depth++;
    if (ch === ')') depth = Math.max(0, depth - 1);
    if (/\s/.test(ch) && depth === 0) {
      if (current) parts.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  if (current) parts.push(current);
  return parts;
}

// "8px 16px" -> ['8px', '16px', '8px', '16px'] (top, right, bottom, left)
export function expandBox(value) {
  const parts = splitTopLevel(value);
  if (parts.length === 0) return ['', '', '', ''];
  const [t, r = t, b = t, l = r] = parts;
  return [t, r, b, l];
}

// ['8px', '16px', '8px', '16px'] -> "8px 16px"; empty sides count as 0.
export function collapseBox(sides) {
  const [t, r, b, l] = sides.map(s => (s === '' || s === null || s === undefined) ? '0' : s);
  if (t === r && r === b && b === l) return t;
  if (t === b && r === l) return `${t} ${r}`;
  if (r === l) return `${t} ${r} ${b}`;
  return `${t} ${r} ${b} ${l}`;
}

export const SIDES = ['top', 'right', 'bottom', 'left'];

// Read the four sides of padding/margin from a declaration map, where the
// shorthand and longhands may both appear.
export function readBoxSides(decls, prop) {
  const sides = expandBox(decls[prop] || '');
  SIDES.forEach((side, i) => {
    const longhand = decls[`${prop}-${side}`];
    if (longhand !== undefined) sides[i] = longhand;
  });
  return sides;
}

// Four corner radii, same idea as readBoxSides.
export const CORNERS = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];
export function readCorners(decls) {
  const corners = expandBox(decls['border-radius'] || '');
  CORNERS.forEach((corner, i) => {
    const longhand = decls[`border-${corner}-radius`];
    if (longhand !== undefined) corners[i] = longhand;
  });
  return corners;
}

// -----------------------------------------------------------------------------
// Media conditions
// -----------------------------------------------------------------------------

// The environment a design is previewed in: a desktop screen in light mode
// with a mouse, unless a breakpoint says otherwise. Studio's own window and
// the OS theme never leak into the canvas.
export const DEFAULT_MEDIA_ENV = Object.freeze({
  width: 1280,
  height: 800,
  colorScheme: 'light',       // prefers-color-scheme
  reducedMotion: 'no-preference', // prefers-reduced-motion
  contrast: 'no-preference',  // prefers-contrast
  hover: 'hover',             // hover / any-hover
  pointer: 'fine',            // pointer / any-pointer
  displayMode: 'browser'      // display-mode
});

// A full environment from a partial one, or from a bare width.
export function mediaEnv(partial) {
  if (typeof partial === 'number') return { ...DEFAULT_MEDIA_ENV, width: partial };
  return { ...DEFAULT_MEDIA_ENV, ...(partial || {}) };
}

// Does `query` match the environment `env` (see DEFAULT_MEDIA_ENV; a number
// means a width)? Returns true / false, or null when the query uses a feature
// this does not model, which the caller should then leave to the browser.
export function evaluateMedia(query, env) {
  const e = mediaEnv(env);
  const alternatives = String(query || '').split(',');
  let sawUnknown = false;
  for (const alternative of alternatives) {
    const result = evaluateMediaPart(alternative, e);
    if (result === true) return true;
    if (result === null) sawUnknown = true;
  }
  return sawUnknown ? null : false;
}

// Kept for callers that only know a width.
export function evaluateMediaForWidth(query, width) {
  return evaluateMedia(query, { width });
}

const KEYWORD_FEATURES = {
  'prefers-color-scheme': 'colorScheme',
  'prefers-reduced-motion': 'reducedMotion',
  'prefers-contrast': 'contrast',
  hover: 'hover',
  'any-hover': 'hover',
  pointer: 'pointer',
  'any-pointer': 'pointer',
  'display-mode': 'displayMode'
};

function evaluateCondition(condition, env) {
  const inner = condition.slice(1, -1).trim();
  const length = inner.match(/^(min|max)-(width|height)\s*:\s*(-?\d*\.?\d+)(px|em|rem)?$/);
  if (length) {
    const px = Number(length[3]) * (length[4] === 'em' || length[4] === 'rem' ? 16 : 1);
    const actual = env[length[2]];
    return length[1] === 'max' ? actual <= px : actual >= px;
  }
  const orientation = inner.match(/^orientation\s*:\s*(portrait|landscape)$/);
  if (orientation) return (env.height >= env.width ? 'portrait' : 'landscape') === orientation[1];
  const keyword = inner.match(/^([a-z-]+)\s*:\s*([a-z-]+)$/);
  if (keyword && KEYWORD_FEATURES[keyword[1]]) return env[KEYWORD_FEATURES[keyword[1]]] === keyword[2];
  return null;
}

// The environment `env` adjusted so the non-width features `media` names are
// true in it: (prefers-color-scheme: dark) -> colorScheme 'dark',
// (orientation: portrait) -> taller than wide. Widths come from the
// breakpoint's own preview width, not from here.
export function envSatisfying(media, env) {
  const out = mediaEnv(env);
  for (const condition of String(media || '').toLowerCase().match(/\([^)]*\)/g) || []) {
    const inner = condition.slice(1, -1).trim();
    const orientation = inner.match(/^orientation\s*:\s*(portrait|landscape)$/);
    if (orientation) {
      // A 16:10 screen in the requested orientation, keeping the width.
      out.height = Math.round(out.width * (orientation[1] === 'portrait' ? 1.6 : 0.625));
      continue;
    }
    const keyword = inner.match(/^([a-z-]+)\s*:\s*([a-z-]+)$/);
    if (keyword && KEYWORD_FEATURES[keyword[1]]) out[KEYWORD_FEATURES[keyword[1]]] = keyword[2];
  }
  return out;
}

function evaluateMediaPart(part, env) {
  let text = part.trim().toLowerCase();
  if (!text) return null;
  let negate = false;
  if (text.startsWith('not ')) { negate = true; text = text.slice(4); }
  text = text.replace(/^only\s+/, '');
  const typeMatch = text.match(/^(all|screen|print)\b\s*(and\s+)?/);
  if (typeMatch) {
    if (typeMatch[1] === 'print') return negate;
    text = text.slice(typeMatch[0].length);
  }
  const conditions = text.match(/\([^)]*\)/g) || [];
  if (conditions.length === 0) return negate ? false : true;
  let result = true;
  for (const condition of conditions) {
    const verdict = evaluateCondition(condition, env);
    if (verdict === null) return null;
    if (!verdict) result = false;
  }
  return negate ? !result : result;
}

// -----------------------------------------------------------------------------
// Colors
// -----------------------------------------------------------------------------

const NAMED_COLORS = {
  white: '#ffffff', black: '#000000', red: '#ff0000', blue: '#0000ff', green: '#008000',
  gray: '#808080', grey: '#808080', navy: '#000080', orange: '#ffa500', purple: '#800080',
  yellow: '#ffff00', transparent: '#000000'
};

// Best-effort conversion of any CSS color to #rrggbb for <input type=color>.
export function toHexColor(color, fallback = '#000000') {
  const text = String(color || '').trim().toLowerCase();
  if (!text) return fallback;
  if (/^#[0-9a-f]{6}$/.test(text)) return text;
  if (/^#[0-9a-f]{8}$/.test(text)) return text.slice(0, 7);
  if (/^#[0-9a-f]{3,4}$/.test(text)) return '#' + text.slice(1, 4).split('').map(c => c + c).join('');
  const rgb = text.match(/^rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)/);
  if (rgb) return '#' + rgb.slice(1, 4).map(n => Math.min(255, Number(n)).toString(16).padStart(2, '0')).join('');
  return NAMED_COLORS[text] || fallback;
}
