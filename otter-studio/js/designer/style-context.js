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

// CSS properties a component inherits from its parent when nothing sets them.
const INHERITED_PROPS = new Set([
  'color', 'font', 'font-family', 'font-size', 'font-style', 'font-weight', 'font-variant',
  'line-height', 'letter-spacing', 'word-spacing', 'text-align', 'text-indent',
  'text-transform', 'text-shadow', 'white-space', 'direction', 'cursor', 'visibility',
  'list-style', 'list-style-type', 'list-style-position', 'quotes', 'hyphens'
]);

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
    // (comp, cssProp, state) => what the compiler itself applies; see explain().
    this.compilerProbe = null;
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

  // --- Provenance -----------------------------------------------------------

  // Where the value of `cssProp` on `comp` comes from in the current context,
  // ranked the way the compiled app's cascade ranks it:
  //
  //   1. !important styles.css rules (#card beats the compiler's class rules)
  //   2. !important compiler rules
  //   3. inline styles: the Otter source value, else a compiler-forced default
  //   4. plain styles.css rules
  //   5. plain compiler rules
  //   6. inherited from a parent component (inheritable properties only)
  //   7. browser default
  //
  // Within the styles.css groups, a state rule outranks a plain one, and a
  // narrower breakpoint outranks a wider one (it comes later in the file).
  //
  // Returns {
  //   prop, value,            the winning value (null = browser default)
  //   status,                 'set' | 'inherited' | 'overridden' | 'compiler' | 'default'
  //   source,                 where the winning value lives:
  //                           'otter' | 'styles.css' | 'compiler' | 'parent' | 'browser'
  //   from,                   human label: 'Desktop', 'Tablet · Hover', 'parent card1'
  //   location,               { file: 'source', component } or
  //                           { file: 'styles.css', selector, media } or
  //                           { file: 'compiler', selector } or null
  //   forced,                 the compiler always sets this for the kind, so
  //                           Studio writes styles.css values as !important
  //   overriddenBy,           status 'overridden' only: the candidate that wins
  //   chain                   every candidate, winner first
  // }
  //
  // `compilerProbe(comp, cssProp, state)`, installed by the canvas, reports
  // what the compiler itself applies: { inline, rules: [{ selector, value,
  // important }] }. Without it (tests, no render yet) compiler candidates are
  // simply absent.
  explain(comp, cssProp, { depth = 0 } = {}) {
    const prop = String(cssProp).toLowerCase();
    const empty = { prop, value: null, status: 'default', source: 'browser', from: null, location: null, forced: false, overriddenBy: null, chain: [] };
    if (!comp) return empty;

    const state = this.context.state;
    const bpIndex = Math.max(0, BREAKPOINTS.findIndex(b => b.id === this.context.breakpoint));
    const stateLabel = (st) => STATES.find(s => s.id === st)?.label || st;
    const candidates = [];

    // styles.css rules that apply here. `order` grows with specificity and
    // source position, so the highest order wins within the same group.
    const states = state ? ['', state] : [''];
    states.forEach((st, stIndex) => {
      for (let i = 0; i <= bpIndex; i++) {
        const bp = BREAKPOINTS[i];
        const selector = this.selector(comp, st);
        const raw = this.css.getRuleDeclarations(selector, bp.media)[prop];
        if (raw === undefined) continue;
        candidates.push({
          source: 'styles.css',
          value: stripImportant(raw),
          important: IMPORTANT.test(raw),
          order: stIndex * 100 + i,
          here: i === bpIndex && st === state,
          from: `${bp.label}${st ? ' · ' + stateLabel(st) : ''}`,
          location: { file: 'styles.css', selector, media: bp.media }
        });
      }
    });

    const sourceValue = this.sourceValue(comp, prop);
    const probe = this.compilerProbe ? this.compilerProbe(comp, prop, state) : null;
    const forced = this.isForcedInline(comp, prop);
    if (sourceValue !== null) {
      candidates.push({
        source: 'otter', value: sourceValue, important: false, inline: true,
        here: this.isBaseContext(), from: 'Desktop',
        location: { file: 'source', component: comp.name, key: sourceKeyFor(comp, prop) }
      });
    } else if (probe?.inline) {
      candidates.push({
        source: 'compiler', value: stripImportant(probe.inline), important: false, inline: true,
        here: false, from: `every ${comp.kind}`, location: { file: 'compiler', selector: 'inline style' }
      });
    }
    (probe?.rules || []).forEach((rule, index) => {
      candidates.push({
        source: 'compiler', value: stripImportant(rule.value), important: !!rule.important, order: index,
        here: false, from: `every ${comp.kind}`, location: { file: 'compiler', selector: rule.selector }
      });
    });

    const rank = (c) => {
      if (c.source === 'styles.css') return c.important ? 600 + c.order : 300 + c.order;
      if (c.inline) return 400;
      if (c.source === 'compiler') return c.important ? 500 + c.order : 200 + c.order;
      return 0;
    };
    candidates.sort((a, b) => rank(b) - rank(a));

    // Nothing on the component itself (or only `inherit`, which the compiler
    // uses for headings): an inheritable property comes from the nearest
    // ancestor that has it.
    const defers = candidates.length === 0 ? INHERITED_PROPS.has(prop) : candidates[0].value === 'inherit';
    if (defers && comp.parentId && depth < 64) {
      const parent = this.uiModel.getComponent(comp.parentId);
      const fromParent = parent ? this.explain(parent, prop, { depth: depth + 1 }) : null;
      if (fromParent && fromParent.value !== null) {
        const via = fromParent.source === 'parent' ? fromParent.from : `parent ${parent.name}`;
        return {
          prop, value: fromParent.value, status: 'inherited', source: 'parent', from: via,
          location: fromParent.location, forced: false, overriddenBy: null,
          chain: [{ source: 'parent', value: fromParent.value, from: via, location: fromParent.location, here: false, wins: true }]
        };
      }
    }

    if (candidates.length === 0) return { ...empty, forced };

    const winner = candidates[0];
    const mine = candidates.find(c => c.here);
    const chain = candidates.map(c => ({
      source: c.source, value: c.value, important: c.important, from: c.from,
      location: c.location, here: c.here, wins: c === winner
    }));

    let status;
    if (mine && mine !== winner) status = 'overridden';
    else if (winner.here) status = 'set';
    else if (winner.source === 'compiler') status = 'compiler';
    else status = 'inherited';

    return {
      prop,
      value: winner.value,
      status,
      source: winner.source,
      from: winner.from,
      location: winner.location,
      forced,
      overriddenBy: status === 'overridden' ? chain[0] : null,
      mine: mine ? chain[candidates.indexOf(mine)] : null,
      chain
    };
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
export const _internal = { SOURCE_PROPS, FORCED_INLINE, INHERITED_PROPS, expandBox };
