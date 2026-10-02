# OtterBoard — Flagship Desktop Showcase Application

**Plan. Build. Create. Together.**

`OtterBoard` is a flagship desktop productivity and project management application built **100% in pure Otter** (`.ot`). It demonstrates modern desktop UI development, state management, persistent data, and modular architecture with **0 host-language workaround LOC**.

---

## Visual Direction & Aesthetics

- **Deep Navy Palette**: `#0B1120` canvas with `#0F172A` sidebar and `#1E293B` panel cards.
- **Water-Blue Accent**: `#0EA5E9` (primary) and `#38BDF8` (highlights) with `#06B6D4` (cyan) and `#8B5CF6` (purple) accents.
- **Rudy Identity**: Integrated branding and footer inspiration: *"Small steps build big things."*
- **Desktop Window**: 1600 × 1000 responsive desktop canvas.

---

## Architecture & Project Structure

```
projects/OtterBoard/
├── otter.json              # D118 standard project manifest
├── main.ot                 # Application entry point & desktop UI layout
├── OTTERBOARD.md           # Flagship documentation
├── assets/
│   └── styles.css          # Visual styling system & token definitions
├── src/
│   ├── models/
│   │   └── types.ot        # Domain models (Project, TaskItem, NoteItem, Activity, Settings)
│   ├── data/
│   │   └── store.ot        # Seed data & atomic JSON persistence
│   ├── services/
│   │   └── board_service.ot# Query, search, task completion & analytics calculations
│   └── ui/
│       └── components.ot   # Card, badge, progress & row visual formatters
└── tests/
    └── board_test.ot       # Automated test suite
```

---

## Demonstrated Capabilities

1. **Desktop UI Composition**: `create window`, `create heading`, `create text box`, `create button`, `create card`, `create scroll`, `create row`, `create column`, and `show app`.
2. **Dynamic Collections & Iteration**: `for each p in projects` generating cards, task rows, and pinned sidebar items.
3. **Structured Domain Models**: `a Project has ...`, `a TaskItem has ...` instantiated with clean constructor functions.
4. **Local Data Persistence**: Atomic JSON serialization via `write jsonText to filePath atomically` (D72).
5. **Interactive Event Handlers**: `when <button> is clicked:` for state saving, task toggling, and navigation.

---

## Toolchain Verification

From repository root:

```powershell
# Validate project syntax and types
otter check projects/OtterBoard

# Run automated test suites
otter test projects/OtterBoard

# Build distribution bundle into dist/
otter build projects/OtterBoard

# Publish package archive into publish/
otter publish projects/OtterBoard
```

---

## Opening in Otter Studio / IDE

To launch `OtterBoard` inside Otter Studio:

```powershell
# Launch Otter Studio
.\otter.cmd studio
```

Then select `projects/OtterBoard` to inspect files in the Editor and UI Designer.
