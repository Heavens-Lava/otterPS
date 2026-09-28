# Otter Studio designer — gap analysis against Webstudio, GrapesJS and Penpot

Status: analysis only, no code changed. Written 2026-09-27 against
`feature/studio-electron-followup` at `04f71ca`.

The question: before the next designer polish pass, what do three mature
open-source visual builders do that Otter Studio does not, and what should be
built next, in what order?

## Ground rules for using these projects

| Project | License | How it may be used |
|---|---|---|
| Webstudio (`webstudio-is/webstudio`, `apps/builder`) | AGPL-3.0 | UX and documentation only. Read no source, copy nothing. This analysis used its public docs (`docs.webstudio.is`, `llms-full.txt`) and directory names only. |
| GrapesJS (`GrapesJS/grapesjs`, `packages/core/src`) | BSD-3-Clause | Architecture and patterns. Code could legally be adapted with attribution, but Otter's model (Otter source is the truth, not HTML) makes direct reuse a poor fit. |
| Penpot (`penpot/penpot`, `frontend/src`) | MPL-2.0 | UX and documentation only (help center). File-level copyleft; copy nothing. |
| Puck | MIT | React component-tree editor. Not studied further: Otter's canvas is not React and its tree is Otter source. |

Nothing in this document requires code from any of them.

## What Otter Studio's designer is today

The modules involved, with their size, because size is part of the finding:

| Module | Lines | Role (GrapesJS equivalent) |
|---|---|---|
| `js/model/ui-model.js` | 523 | Component tree, selection, snapshot undo (DomComponents + UndoManager) |
| `js/compiler/css-ast.js` | 482 | Lossless styles.css AST, media blocks widest-first (CssComposer + Parser) |
| `js/designer/style-context.js` | 377 | Where an edit goes: Otter source vs styles.css, breakpoint, state, `!important` (SelectorManager + part of StyleManager) |
| `js/designer/css-values.js` | 165 | Value parsing/expansion |
| `js/components/properties.js` | 1322 | The whole inspector UI (StyleManager + TraitManager UI) |
| `js/components/canvas.js` | 1947 | Rendering, overlay, handles, guides, gestures, keyboard, context menu (Canvas + parts of Commands + Keymaps) |
| `js/components/real-style.js` | 214 | Real-compiler styling and media flattening for the device width (Canvas frame + DeviceManager simulation) |
| `js/components/hierarchy.js` | 267 | Layer tree: select, Ctrl multi-select, drag reorder/re-nest, rename (LayerManager / Navigator) |
| `js/components/toolbox.js` | 96 | Categorized component palette (BlockManager) |
| `js/shell/commands.js` | 131 | Command registry used by F1 / Ctrl+Shift+P (Commands) — the designer's canvas shortcuts do **not** go through it |

What Otter has that none of the three have: the designer edits a real
programming language. A style value can live in the Otter source
(`padding 28`), in `styles.css`, in a breakpoint or state rule, or be forced by
the compiler — and `StyleController` already knows which. That is the
foundation for the most valuable item below.

## Findings

### 1. Style provenance

Webstudio's label colors (from its docs): **blue** set on the current source
and breakpoint; **orange** coming from somewhere else (another token, a state
not selected, a parent, a larger breakpoint); **gray** a browser or Webstudio
default; **red** set here but overridden by something later. Hovering a label
names the exact source; every section header carries a dot when anything in it
is set.

Otter today (`properties.js` `dot()`, `style-context.js` `resolve()`):

| Otter case | Shown today? |
|---|---|
| Set in the Otter source, this context | Yes — green dot, "Set in the Otter source", click resets |
| Set in styles.css, this context | Yes — blue dot, click resets |
| Cascaded from a wider breakpoint or from the normal state | Yes — orange dot, tooltip "Inherited from Desktop Hover" |
| Section has values set | Yes — count badge on the section header |
| Inherited from a parent component (`color`, `font-*`, `line-height`) | **No** — shows as unset; the computed value appears only as a placeholder |
| Compiler-forced value (a row always gets inline `gap`, `align-items`…) | **Hidden** — the controller silently writes `!important`; the user is never told why |
| Compiler theme default (e.g. a primary button's background from the compiler stylesheet) | **No** — indistinguishable from browser default |
| A styles.css value that is being beaten (by inline source, a later rule, a compiler `!important`) | **No** — there is no "red" state |
| Browser default | Partly — plain dot plus computed placeholder |
| Where exactly: `main.ot` line 12, or `styles.css` `@media (max-width: 900px) { #card }` | **No** — tooltip names the context, not the location; no "go to source" |

Category: **Existing but needs polish** (the model is 70% there), and it is
the single highest-value item. It is also Otter's differentiator: no generic
site builder can say "this value comes from line 12 of your program".

### 2. Style panel organization

| Webstudio section | Otter | Category |
|---|---|---|
| Layout (display, direction, wrap, align, justify, gap, grid templates) | Layout section: display, direction, wrap, gap, grid columns/rows stepper, justify-items, align | Already in Otter |
| Grid generator / presets / named areas | Column stepper + track overlay only | Useful later |
| `grid-auto-flow`, auto rows/columns | Missing (raw editor only) | Useful later |
| Flex child (grow, shrink, basis, align-self, order, link to parent) | Mixed into Layout as `flex` shorthand, `align-self`, `order`; no grow/shrink/basis fields, no parent link | Existing but needs polish |
| Grid child (column/row start-end, justify/align-self) | `grid-column`/`grid-row` span controls | Existing but needs polish |
| Size (w/h, min/max, overflow, object-fit, aspect-ratio) | Size section has all of these | Already in Otter |
| Space (padding/margin box) | Spacing box model, per-side, presets 0–32 | Already in Otter |
| Position (position, offsets, z-index) | Position section | Already in Otter |
| Typography | family, size, weight, line-height, letter-spacing, color, align, transform, style, decoration | Already in Otter; `text-shadow`, `text-overflow`, `text-wrap`, `white-space` missing (last one is source-backed but has no control) |
| Backgrounds (multi-layer, gradient stops, image, size, position, repeat, clip) | color, 2-stop linear gradient with angle, image, size | Existing but needs polish (single layer, 2 stops, no position/repeat) |
| Borders (per side) and radius (per corner) | border shorthand + per-corner radius | Existing but needs polish (no per-side border) |
| Outline | Missing | High-value missing (focus rings are an accessibility requirement) |
| Box shadows (layer list: x, y, blur, spread, color, inset) | One text field | Existing but needs polish |
| Filter / backdrop filter | backdrop-filter text field; filter missing | Useful later |
| Transitions (layer list, easing) | One text field | Existing but needs polish |
| Transforms (translate/rotate/scale fields, origin) | One `transform` text field | Useful later |
| Advanced (any property, autocomplete, non-standard warning) | Raw declarations list with `otter` superscript marking source-backed ones | Already in Otter; autocomplete and warnings would be polish |
| Style sources: Local vs Tokens (shared classes) | Only `#id` rules; shared class rules are an open checklist item | Useful later (Otter language question first) |
| States incl. custom and pseudo-elements (`::before`, `::placeholder`) | Normal / Hover / Pressed / Focused, forced on canvas | Existing; `disabled` and `::placeholder` are the useful additions |
| CSS variables | Parsed and preserved by the AST; no UI | Useful later |

### 3. Direct manipulation

| Behavior (source) | Otter | Category |
|---|---|---|
| Drag padding/margin/gap on canvas (Penpot, Webstudio) | Yes — grips on bands, one undo step per drag, Escape cancels | Already in Otter |
| Shift = opposite sides together, Alt = all sides (Penpot; Webstudio similar) | No modifiers on spacing drags | High-value missing |
| Scrub a number by dragging its label in the inspector | Yes on numeric field labels, radius and gradient angle (Shift ×10); not on the box-model numbers | Existing but needs polish |
| Resize with smart guides and sibling-size snapping | Yes | Already in Otter |
| Resize modifiers: Shift proportional, Alt from center (Penpot) | No | Useful later |
| Arrow nudge, Shift ×10 | Yes for absolute/fixed; Alt+arrow reorders among siblings | Already in Otter |
| Select parent / child: Shift+Enter / Enter (Penpot) | Enter selects first child, Escape selects parent, Tab/Shift+Tab walk siblings | Already in Otter |
| Wrap selection in flex / grid: Shift+A / Ctrl+Shift+A (Penpot) | Ctrl+G wraps in column, Ctrl+Shift+G in row; no grid wrap | Already in Otter (grid wrap useful later) |
| Align / distribute selection (Penpot Alt+A/H/D/W/V/S) | No | Useful later — only meaningful for absolute elements; flex alignment covers flow layout |
| Hide / lock (Penpot Ctrl+Shift+H / L) | No | High-value missing (designer-only hide; lock to stop accidental drags) |
| Zoom fit / selection / 100% (Penpot Shift+1/2/0) | Fit (Shift+1), zoom menu, Ctrl+wheel | Existing; zoom-to-selection missing |
| Canvas shortcuts listed in the command palette and shortcuts dialog | No — hard-coded in `canvas.js` keydown | Existing but needs polish |

### 4. Layers (Navigator / Layer Manager)

The tree exists (`hierarchy.js`), but the sidebar tab is labelled
**Outline**. In Design mode it shows the component tree; in Code mode the same
tab shows source symbols. A user looking for "Layers" does not find it, which
is part of why the app feels less capable than it is.

| Webstudio / Penpot behavior | Otter | Category |
|---|---|---|
| Click select, Ctrl multi-select | Yes | Already in Otter |
| Shift range select, Shift+Up/Down extend | No | Existing but needs polish |
| Drag reorder / re-nest | Yes | Already in Otter |
| Double-click rename | Yes | Already in Otter |
| Ctrl+Up/Down move among siblings, Ctrl+Left out of parent, Ctrl+Right into previous sibling (Webstudio) | Alt+arrows on canvas reorder only | High-value missing |
| Show/hide, lock per row | No | High-value missing |
| Lazy rendering of huge trees (Penpot) | No | Useful later — Otter UIs are small |
| A clear "Layers" name and icon in Design mode | Labelled "Outline" | High-value missing (cheap) |

### 5. Responsive model

Otter: `BREAKPOINTS` is a hard-coded array in `style-context.js`
(`base`, `(max-width: 900px)`, `(max-width: 600px)`). Three places assume it:

1. `StyleController.resolve()` builds the cascade chain by walking that
   array's **index order**, which is only correct for desktop-first
   `max-width` conditions.
2. `css-ast.js` sorts media blocks widest-first by parsing `(max-width: N)`
   only; any other condition keeps source order.
3. `real-style.js` simulates media on the canvas by **device width only**;
   a condition such as `(prefers-color-scheme: dark)` is kept as written, so it
   follows Studio's own window instead of the design.

Webstudio: Base plus any number of `max-width` or `min-width` breakpoints,
plus conditions (color scheme, reduced motion, orientation, pointer, contrast,
display mode), combinable, each simulated in the canvas by rewriting matching
media rules to always-true and the rest to always-false.

Category: the three presets are **Already in Otter**; the model is
**Existing but needs polish** — not a UI feature yet, but the three
assumptions above should be removed now, before more code depends on them.

### 6. Architecture (GrapesJS module boundaries)

GrapesJS `packages/core/src` separates: `asset_manager`, `block_manager`,
`canvas`, `code_manager`, `commands`, `css_composer`, `device_manager`,
`dom_components`, `keymaps`, `navigator`, `parser`, `selector_manager`,
`style_manager`, `trait_manager`, `undo_manager`, `storage_manager`, and more.

Otter already has clean seams for the model, CSS AST, style routing, value
parsing, and the real-render bridge. The two places that are becoming overly
coupled:

- **`canvas.js` (1947 lines)** mixes rendering, the overlay, every gesture,
  keyboard handling, and the context menu. Items 3 and 4 above all land in
  it. Split it before adding to it: `designer/canvas/render.js`,
  `overlay.js`, `gestures.js`, `keyboard.js`, `context-menu.js`.
- **Keyboard handling** in canvas and hierarchy bypasses
  `shell/commands.js`. A GrapesJS-style keymap (commands with ids, keymaps
  bound to ids) makes designer shortcuts discoverable in F1 and the
  shortcuts dialog, and lets the Layers panel and canvas share them.

`properties.js` (1322 lines) is large but coherent; split it into
`designer/style-manager/sections/*.js` only when a section is being
rewritten (provenance work touches all of them through `dot()` alone, so it
does not require the split).

Not recommended: a GrapesJS-style storage manager or HTML parser as source of
truth. Otter source is the document; that is the product.

### 7. Everything else considered

| Idea | Category | Why |
|---|---|---|
| Asset manager (images, fonts in the project, picker in Background/Typography) | Useful later | Real need for web apps; depends on how Otter references assets |
| Design tokens / shared classes | Useful later | Needs an Otter-language decision on shared styles first |
| Webstudio "Hide UI" (Ctrl+\) full-canvas mode | Useful later | Cheap, nice |
| Webstudio CMS, data variables, publishing/hosting | Not appropriate | Otter programs own their data and build output |
| Penpot vector tools, boolean ops, prototyping links, comments | Not appropriate | Otter is a programming IDE with a UI designer, not a drawing tool |
| Free-form absolute positioning as the default | Not appropriate | Otter deliberately keeps flow layout structural (checklist item "No hidden left/top in flow mode") |

## Recommended next designer improvements, in order

Each step is independently shippable and verified through the real Studio UI
and a compiled app, as the project rules require.

1. **Provenance model.** Add `StyleController.explain(comp, cssProp)`
   returning the winning value, its source kind (`otter`, `stylesheet`,
   `breakpoint`, `state`, `parent`, `compiler-forced`, `compiler-default`,
   `browser-default`), its location (`main.ot` line, or styles.css selector +
   media), and what it overrides / is overridden by. Pure logic, unit-tested in
   `designer-styles`. No UI change.
2. **Provenance UI.** Color the property *label* like Webstudio (keep the dot
   for reset), add red for "set here but overridden", and a hover card showing
   the chain with **Go to source** (opens `main.ot` at the line, or styles.css
   at the rule). Explain compiler-forced values in words ("rows always set
   `gap`; Studio writes `!important` so your value wins").
3. **Breakpoint model cleanup (no new UI).** Breakpoints become data
   (`{ id, label, media, previewWidth }`, stored with the project, defaulting to
   today's three). Replace index-order cascade with media evaluation against a
   simulated environment; teach `real-style.js` to simulate non-width
   conditions. The Desktop/Tablet/Mobile bar looks identical afterwards.
4. **Split `canvas.js` and route designer keys through the command
   registry.** Behavior-preserving refactor; the existing canvas suites must
   stay green. Designer shortcuts then show in F1 and Shortcuts.
5. **Layers panel.** Name it Layers in Design mode, add hide (designer-only)
   and lock per row, Shift range select, and Webstudio's Ctrl+arrow
   restructuring keys (shared with the canvas via step 4's commands).
6. **Spacing modifiers.** Shift = opposite sides, Alt = all sides on canvas
   grips; make the inspector's box-model numbers scrubbable with the same
   modifiers.
7. **Flex child / Grid child sections.** Show them based on the parent's
   layout, with grow/shrink/basis fields and a "select parent" link.
8. **Missing controls with real demand:** outline (focus rings), per-side
   borders, layered box-shadow editor, transition editor, `text-shadow`,
   `disabled` state and `::placeholder`.
9. **Zoom to selection** (Shift+2) and resize modifiers (Shift proportional,
   Alt from center).

Deliberately not in this list: tokens, assets, grid generator, custom
breakpoint UI. They are real but depend on steps 1–3 or on language
decisions.

## Outside the designer

The same review of the workbench (not the designer) found a quality problem
that is cheaper and more visible than any item above: the New Project, Build,
Settings and Shortcuts dialogs still use the old light theme on the navy
workbench. It is tracked in the checklist next to these items.
