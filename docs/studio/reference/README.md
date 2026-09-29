# Otter Studio reference design

The look Otter Studio is built toward. Two views of the same workbench,
designing a "Contact Manager" desktop app:

| Image | Shows |
|---|---|
| [otter-studio-reference-components-tab.png](otter-studio-reference-components-tab.png) | Designer with the **Components** tab (toolbox as a tile grid) |
| [otter-studio-reference-assets-tab.png](otter-studio-reference-assets-tab.png) | Designer with the **Assets** tab (project tree and resources) |

`Otter IDE reference image.png` at the repository root is **not** Otter
Studio: it is the reference for OtterGraph (an image editor). Do not design
Studio from it.

## What the reference has, area by area

**Header.** The otter mascot and "Otter / A more joyful way to build" on a
mountain-landscape band. The five modes (Code, Designer, Split, Designer
Right, Live App) as large centred tabs, the active one filled blue. The
project as a chip with a folder icon ("Contact Manager ▾"), then settings
and the window controls. No classic menu bar and no command box in the
header.

**Toolbar row.** Left: New, Open, Save ▾, Run ▾ (Run is the primary blue
button). Centre: the target (Desktop ▾), device buttons (desktop, tablet,
phone), zoom (100% ▾), light/dark. Right: Preview App ↗.

**Left panel: Components | Assets.**
- Components: a search box, then collapsible groups (Common, Layout, Data,
  Media) of square tiles, each an icon over a label (Button, Label, Text
  Box, Text Area, Combo Box, Check Box, Radio Button, List Box, Date Picker,
  Panel, Group Box, Tab Control, Split Panel, Scroll Panel, Grid, Stack
  Panel, Dock Panel, Spacer, Data Grid, List View, Tree View, Image, Icon,
  Progress Bar).
- Assets: "Project" tree (folders assets/images/icons/styles, the .ot files,
  data, styles, components, pages) with search / new / collapse actions, and
  a "Resources" list below (UI Controls, Layouts, Icons, Images, Themes).

**Centre.** Document tabs (main.ot, contact-manager.ot, +), then a
Design | Preview switch, then the canvas: dotted background, the window
with a "MainWindow" name chip and blue selection handles.

**Bottom, split in two.** Left: the code of the open document (Code |
Design Tree, or file tabs). Right: Output | Problems | Assistant (or
Search / Console). Output shows the build as steps with check marks
("Parsing ✓, Building UI ✓, Linking assets ✓, Success!").

**Right panel: Properties | Events | Styles.** A heading with the selected
element's type and name ("Button (btnAdd)"), then collapsible sections:
General (Name, Text, Icon, Style ▾, switches for Is Visible / Is Enabled),
Layout (X/Y and Width/Height side by side, four-field Margin and Padding,
alignment as icon button groups), Appearance (Font ▾, Font Size, colours as
a swatch plus hex, Border Radius).

**Look.** Dark navy panels with 8 px corners and 1 px borders, small gaps
between panels, 13 px interface text, one blue accent (#3B82F6), switches
instead of checkboxes, the landscape art showing at the window's edges.

## Differences from Studio today (2026-09-28), in the order to close them

1. Menus: Studio's Edit, Run and View menus were dead labels. The menu bar
   now comes from the command registry (js/shell/menu-bar.js). The
   reference has no menu bar; Studio keeps one (compact) because it is how
   people discover commands - to confirm with Jeff.
2. Header and toolbar row: brand band, centred mode tabs, project chip;
   New / Open / Save ▾ / Run ▾ on the left of a toolbar row, device and zoom
   in its centre (today they sit in the canvas's own toolbar), Preview App
   on the right.
3. Left panel as Components | Assets (today: an activity rail with Files,
   Toolbox, Layers, Search, Git, plus a Templates card). The toolbox becomes
   the tile grid; Files becomes Assets with Resources.
4. Right panel: Properties | Events | Styles, the element heading,
   collapsible sections, switches, paired fields, icon alignment groups,
   colour swatches.
5. Bottom split: code on the left, Output / Problems on the right, and
   Output's build steps with check marks.
6. The landscape art at the edges, and final spacing and type.

## Found along the way (not Studio's to fix)

- **A window's width is capped at 520 px in compiled web output.** The web
  compiler's shared stylesheet gives every `.otter-window` `max-width:
  520px`, which beats the window's own inline `width: 900px`. So
  `app is a window with ..., width 900` renders 520 px wide in the browser,
  and the designer (which shows the real compiled render) shows the same.
  Seen 2026-09-28 with `otter.ps1 web`; the fix belongs in
  src/Otter.Web.psm1 (an explicit width should lift the default cap) -
  for Jeff to decide, since it touches the release pipeline.
