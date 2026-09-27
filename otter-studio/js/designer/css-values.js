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

// Does `query` match a viewport `width` px wide? Returns true / false, or null
// when the condition depends on something other than width (orientation,
// hover, prefers-color-scheme ...) and cannot be decided here.
export function evaluateMediaForWidth(query, width) {
  const alternatives = String(query || '').split(',');
  let sawUnknown = false;
  for (const alternative of alternatives) {
    const result = evaluateMediaPart(alternative, width);
    if (result === true) return true;
    if (result === null) sawUnknown = true;
  }
  return sawUnknown ? null : false;
}

function evaluateMediaPart(part, width) {
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
    const m = condition.match(/^\(\s*(min|max)-width\s*:\s*(-?\d*\.?\d+)(px|em|rem)?\s*\)$/);
    if (!m) return null;
    const px = Number(m[2]) * (m[3] === 'em' || m[3] === 'rem' ? 16 : 1);
    if (m[1] === 'max' && !(width <= px)) result = false;
    if (m[1] === 'min' && !(width >= px)) result = false;
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
