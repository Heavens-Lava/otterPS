// style-context.js - Where a designer style edit goes, and what it replaces.
//
// A style edit has a context: which breakpoint (Desktop / Tablet / Mobile)
// and which state (normal, hover, pressed, focused) is being designed. The
// controller turns (component, property, context) into a concrete location:
//
//   * the Otter source itself, for properties Otter can express
//     (`padding 28`, `size 24`, `background "#fff"`). The web compiler applies
//     those as inline styles, so they beat styles.css and must be edited where
//     they live;
//   * a rule in styles.css:  #card { }, #card:hover { }, or a rule inside
//     @media (max-width: 900px) { #card { } }.
//
// Two facts about the web compiler (src/Otter.Web.psm1) shape this:
//
//  1. An inline source value can never be overridden by a breakpoint or a
//     state rule. So the first time a breakpoint/state value is set for such a
//     property, the base value moves from the Otter source into the #card rule
//     in styles.css. The look is unchanged and the override now works.
//  2. Some layout values are always inlined for a kind, even when the source
//     does not mention them (a row always gets gap, justify-content,
//     align-items...). A stylesheet rule for those must be !important to take
//     effect in the compiled app, so the controller writes it that way.

import { expandBox } from './css-values.js';

export const BREAKPOINTS = [
  { id: 'base', label: 'Desktop', media: '', width: null, hint: 'All screen sizes' },
  { id: 'tablet', label: 'Tablet', media: '(max-width: 900px)', width: 768, hint: '900px and below' },
  { id: 'mobile', label: 'Mobile', media: '(max-width: 600px)', width: 375, hint: '600px and below' }
];

export const STATES = [
  { id: '', label: 'Normal' },
  { id: ':hover', label: 'Hover' },
  { id: ':active', label: 'Pressed' },
  { id: ':focus', label: 'Focused' }
];

// CSS property -> the Otter source properties the compiler inlines for it
// (first match wins, like the compiler), and whether a bare number means px.
const SOURCE_PROPS = {
  width: { keys: ['width'], px: true, full: true },
  height: { keys: ['height'], px: true, full: true },
  'max-width': { keys: ['maxwidth'], px: true },
  'min-width': { keys: ['minwidth'], px: true },
  'min-height': { keys: ['minheight'], px: true },
  background: { keys: ['background'] },
  color: { keys: ['foreground'] },
  'border-radius': { keys: ['round', 'radius'], px: true },
  border: { keys: ['border'] },
  'box-shadow': { keys: ['shadow'] },
  padding: { keys: ['padding'], px: true },
  margin: { keys: ['margin'], px: true },
  'font-size': { keys: ['fontsize', 'size'], px: true },
  'font-weight': { keys: ['fontweight', 'weight'] },
  'font-style': { keys: ['fontstyle'] },
  'font-family': { keys: ['fontfamily', 'family'] },
  'line-height': { keys: ['lineheight'] },
  'letter-spacing': { keys: ['letterspacing'] },
  'white-space': { keys: ['whitespace'] },
  overflow: { keys: ['overflow'] },
  'text-align': { keys: ['align'], notKinds: ['row', 'column'] },
  flex: { keys: ['flex'] },
  cursor: { keys: ['cursor'] },
  position: { keys: ['position'] },
  top: { keys: ['top'], px: true },
  right: { keys: ['right'], px: true },
  bottom: { keys: ['bottom'], px: true },
  left: { keys: ['left'], px: true },
  'z-index': { keys: ['zindex'] },
  gap: { keys: ['gap', 'spacing'], px: true }
};

// Kept for callers that only need the simple mapping.
export const SOURCE_BACKED_CSS = Object.fromEntries(
  Object.entries(SOURCE_PROPS).map(([css, def]) => [css, def.keys[def.keys.length - 1]])
);

// Layout the compiler inlines for a kind whatever the source says.
const FORCED_INLINE = {
  window: ['gap'],
  card: ['gap'],
  row: ['display', 'flex-direction', 'gap', 'align-items', 'justify-content', 'flex-wrap'],
  column: ['display', 'flex-direction', 'gap', 'align-items', 'justify-content'],
  scroll: ['display', 'flex-direction', 'overflow-x', 'overflow-y']
};

// Containers whose child spacing is Otter's `spacing` property.
const SPACING_KINDS = new Set(['window', 'card', 'row', 'column']);

function sourceKeyFor(comp, cssProp) {
  const def = SOURCE_PROPS[cssProp];
  if (!def || !comp.properties) return null;
  if (def.notKinds && def.notKinds.includes(comp.kind)) return null;
  for (const key of def.keys) {
    const value = comp.properties[key];
    if (value === undefined || value === null || value === '') continue;
    // Any truthy `round` is generated as a bare `round`, which the compiler
    // draws as a pill (9999px) - whatever number the model holds.
    if (key === 'round' && (value === false || value === 'false' || value === 0)) continue;
    return key;
  }
  return null;
}

// The CSS the compiler emits for a source value.
export function sourceValueToCss(cssProp, value, key = null) {
  if (key === 'round') return '9999px';
  if (cssProp === 'border-radius' && value === 'round') return '9999px';
  if (value === 'full' && (cssProp === 'width' || cssProp === 'height')) return '100%';
  if (typeof value === 'number' && SOURCE_PROPS[cssProp]?.px) return `${value}px`;
  return String(value);
}

// The Otter source value for a CSS value, or undefined when the source
// cannot express it simply (then it belongs in styles.css).
export function cssValueToSource(cssProp, text) {
  if (text === '' || text === null || text === undefined) return undefined;
  const value = String(text).trim();
  const def = SOURCE_PROPS[cssProp];
  if (!def) return undefined;
  if (def.full && value === '100%') return 'full';
  if (def.px) {
    const px = value.match(/^(-?\d+(?:\.\d+)?)(?:px)?$/);
    return px ? Number(px[1]) : undefined;
  }
  // Plain words and colors only; anything with functions goes to styles.css.
  if (/[()]/.test(value) && !/^(#|rgba?\(|hsla?\()/.test(value)) return undefined;
  return value;
}

const IMPORTANT = /\s*!important\s*$/i;
const stripImportant = (value) => String(value).replace(IMPORTANT, '');

const COALESCE_MS = 1200;

export class StyleController {
  constructor(uiModel, css) {
    this.uiModel = uiModel;
    this.css = css;
    this.context = { breakpoint: 'base', state: '' };
    this.lastEditKey = null;
    this.lastEditAt = 0;
    // (comp, cssProp) => true when the compiler's stylesheet sets cssProp on
    // this component with !important. Installed by the canvas.
    this.importantProbe = null;
    // A new selection always starts a new undo step.
    uiModel.subscribe((type) => {
      if (type === 'select' || type === 'undo' || type === 'redo') this.lastEditKey = null;
    });
  }

  // --- Context -------------------------------------------------------------

  setContext(partial) {
    const next = { ...this.context, ...partial };
    if (next.breakpoint === this.context.breakpoint && next.state === this.context.state) return;
    this.context = next;
    this.lastEditKey = null;
    window.dispatchEvent(new CustomEvent('otter:style-context', { detail: { ...this.context } }));
  }

  get breakpoint() {
    return BREAKPOINTS.find(b => b.id === this.context.breakpoint) || BREAKPOINTS[0];
  }

  get state() {
    return STATES.find(s => s.id === this.context.state) || STATES[0];
  }

  isBaseContext() {
    return this.context.breakpoint === 'base' && this.context.state === '';
  }

  media() {
    return this.breakpoint.media;
  }

  selector(comp, state = this.context.state) {
    return `#${comp.name}${state}`;
  }

  // Human-readable description of where edits go, e.g. "#card:hover · Tablet".
  describe(comp) {
    const bp = this.breakpoint;
    return `${this.selector(comp)}${bp.media ? ` · ${bp.label} (${bp.media})` : ''}`;
  }

  isForcedInline(comp, cssProp) {
    return (FORCED_INLINE[comp.kind] || []).includes(cssProp);
  }

  // --- Reading --------------------------------------------------------------

  sourceValue(comp, cssProp) {
    const key = sourceKeyFor(comp, cssProp);
    return key ? sourceValueToCss(cssProp, comp.properties[key], key) : null;
  }

  // Every CSS value the Otter source puts inline on this component.
  sourceInline(comp) {
    const out = {};
    for (const cssProp of Object.keys(SOURCE_PROPS)) {
      const value = this.sourceValue(comp, cssProp);
      if (value !== null) out[cssProp] = value;
    }
    return out;
  }

  // All declarations that apply in the current context, plus where each came
  // from. `own` holds what is set in this exact context; `inherited` holds
  // values that cascade in from a wider context. Values are shown without
  // any !important the controller added.
  resolve(comp) {
    const own = {};
    const inherited = {};
    const inheritedFrom = {};
    const origin = {};
    if (!comp) return { own, inherited, inheritedFrom, origin };

    const media = this.media();
    const state = this.context.state;
    const clean = (decls) => Object.fromEntries(Object.entries(decls).map(([k, v]) => [k, stripImportant(v)]));

    Object.assign(own, clean(this.css.getRuleDeclarations(this.selector(comp), media)));
    for (const prop of Object.keys(own)) origin[prop] = 'css';

    if (this.isBaseContext()) {
      for (const [cssProp, value] of Object.entries(this.sourceInline(comp))) {
        own[cssProp] = value;
        origin[cssProp] = 'otter';
      }
      return { own, inherited, inheritedFrom, origin };
    }

    // Cascade chain from most to least specific, excluding the current
    // context. A state rule (#a:hover) outranks every plain #a rule whatever
    // its breakpoint, because it is more specific; within each group the
    // narrower breakpoint wins because it comes later in the stylesheet.
    const chain = [];
    const bpIndex = BREAKPOINTS.findIndex(b => b.id === this.context.breakpoint);
    for (const st of state ? [state, ''] : ['']) {
      for (let i = bpIndex; i >= 0; i--) {
        if (i === bpIndex && st === state) continue;
        chain.push({ bp: BREAKPOINTS[i], state: st });
      }
    }
    for (const { bp, state: st } of chain) {
      const decls = clean(this.css.getRuleDeclarations(this.selector(comp, st), bp.media));
      if (bp.id === 'base' && st === '') Object.assign(decls, this.sourceInline(comp));
      for (const [prop, value] of Object.entries(decls)) {
        if (own[prop] === undefined && inherited[prop] === undefined) {
          inherited[prop] = value;
          inheritedFrom[prop] = `${bp.label}${st ? ' ' + (STATES.find(s => s.id === st)?.label || st) : ''}`;
        }
      }
    }
    return { own, inherited, inheritedFrom, origin };
  }

  // --- Writing --------------------------------------------------------------

  // Start an edit. Edits with the same key close together in time (a drag, a
  // slider, repeated arrow keys) become one undo step.
  beginEdit(key) {
    const now = Date.now();
    if (!key || key !== this.lastEditKey || now - this.lastEditAt > COALESCE_MS) {
      this.uiModel.saveSnapshot();
    }
    this.lastEditKey = key || null;
    this.lastEditAt = now;
  }

  // Write `values` ({ cssProp: value, ... }, value '' / null removes) to every
  // component in `comps`, in the current context, as one undoable step.
  write(comps, values, { key = null } = {}) {
    const list = (Array.isArray(comps) ? comps : [comps]).filter(Boolean);
    if (list.length === 0) return;
    this.beginEdit(key || Object.keys(values).join(','));

    let sourceChanged = false;
    for (const comp of list) {
      for (const [prop, value] of Object.entries(values)) {
        if (this.writeOne(comp, prop.toLowerCase(), value)) sourceChanged = true;
      }
    }

    if (sourceChanged) {
      this.uiModel.notify('property', { id: list[0].id, source: 'style' });
    }
    window.dispatchEvent(new CustomEvent('css-updated', {
      detail: { source: 'style', props: Object.keys(values), ids: list.map(c => c.id) }
    }));
  }

  // A stylesheet value, made !important when the compiler would otherwise
  // override it: an inline default for the kind, or an !important rule in
  // the compiler's own stylesheet (reported by the canvas, which has that
  // stylesheet loaded - see `importantProbe`).
  cssValue(comp, cssProp, value) {
    const text = stripImportant(value);
    const forced = this.isForcedInline(comp, cssProp) || (this.importantProbe ? this.importantProbe(comp, cssProp) : false);
    return forced ? `${text} !important` : text;
  }

  // Returns true when the Otter source changed.
  writeOne(comp, cssProp, value) {
    const remove = value === null || value === undefined || value === '';
    const sourceKey = sourceKeyFor(comp, cssProp);
    const base = this.isBaseContext();

    if (base) {
      if (sourceKey) {
        if (remove) {
          delete comp.properties[sourceKey];
          if (sourceKey === 'round') delete comp.properties.round;
          this.css.removeProperty(this.selector(comp), cssProp);
          return true;
        }
        const sourceValue = cssValueToSource(cssProp, value);
        if (sourceValue !== undefined) {
          if (sourceKey === 'round') {
            delete comp.properties.round;
            comp.properties.radius = sourceValue;
          } else {
            comp.properties[sourceKey] = sourceValue;
          }
          return true;
        }
        // Too rich for Otter source (calc(), several sides, a gradient):
        // move it to styles.css.
        delete comp.properties[sourceKey];
        this.css.setProperty(this.selector(comp), cssProp, this.cssValue(comp, cssProp, value));
        return true;
      }
      // Child spacing is an Otter concept: containers keep it in the source.
      if (cssProp === 'gap' && SPACING_KINDS.has(comp.kind) && !remove) {
        const spacing = cssValueToSource('gap', value);
        if (spacing !== undefined) {
          comp.properties.spacing = spacing;
          this.css.removeProperty(this.selector(comp), 'gap');
          return true;
        }
      }
      this.css.setProperty(this.selector(comp), cssProp, remove ? null : this.cssValue(comp, cssProp, value));
      return false;
    }

    // Breakpoint or state edit. Move an inline source value to styles.css
    // first, so this override can actually win in the compiled app.
    let changed = false;
    if (sourceKey && !remove) {
      // The inline source value was the one winning, so it replaces any
      // stylesheet value for the same property: the look does not change.
      const baseValue = this.sourceValue(comp, cssProp);
      delete comp.properties[sourceKey];
      this.css.setProperty(`#${comp.name}`, cssProp, this.cssValue(comp, cssProp, baseValue));
      changed = true;
    }
    this.css.setProperty(this.selector(comp), cssProp, remove ? null : this.cssValue(comp, cssProp, value), this.media());
    return changed;
  }

  // Remove everything set for these components in the current context.
  clear(comps) {
    const list = (Array.isArray(comps) ? comps : [comps]).filter(Boolean);
    const values = {};
    for (const comp of list) {
      for (const prop of Object.keys(this.resolve(comp).own)) values[prop] = null;
    }
    if (Object.keys(values).length) this.write(list, values, { key: 'clear' });
  }
}

// Exposed for tests.
export const _internal = { SOURCE_PROPS, FORCED_INLINE, expandBox };
