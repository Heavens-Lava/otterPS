# Proposal: what `round` means (needs Jeff's decision)

Status: **proposal only.** Nothing in the language or compilers has changed.
Changing what `round` means is a SPEC-DECISIONS entry and, for a new word,
parser work (Codex).

## What happens today (audited 2026-09-29)

The same word gives four different answers depending on the path:

| Where | `round` (bare) | `round 12` | `radius 12` |
|---|---|---|---|
| Web, controls and cards (`x is a button with round`, Otter.Web.psm1 ~626) | **9999px - a pill** | *ignored* | 12px |
| Web, layout blocks (Otter.Web.psm1 ~155) | 12px | 12px | - |
| WPF (Otter.UI.psm1 ~1720, cards/borders only) | 12px | 12px | - |
| Studio (before today) | wrote any numeric radius as bare `round` | - | - |

The pill comes from Batch 1 (`b136aa3`), which tests it on purpose
(`pillBtn is a button with text "Pill", round` -> `border-radius: 9999px`
in tests/Web.Tests.ps1). On a card or panel the same word makes a capsule,
which is what made the Studio acceptance cards unusable.

Studio's own part is fixed (commit after `5df61e2`): it now writes
`radius N` for a number and keeps a bare `round` exactly as the author
wrote it, so it no longer creates pills by accident.

## Proposed contract

Three words, each meaning one thing on every kind and every target:

| Source | Meaning | CSS / WPF |
|---|---|---|
| `round` | ordinary rounded corners | 8px (one theme value) |
| `radius N` (and `round N` as an alias) | exactly N px | Npx / CornerRadius N |
| `pill` | fully rounded ends: buttons, badges, tags, search boxes | 9999px |

Optionally `circle` (50%) for avatars and icon buttons - only if there is a
real use; it can wait.

Why: `round` reads as "has rounded corners", which is what a card, panel,
input or button almost always wants. A pill is a deliberate shape and gets
its own word, so a card can never become a capsule by accident.

## What changing it would take

1. A SPEC-DECISIONS entry (Jeff).
2. Parser: `pill` as a flag word beside `round` and `spread`
   (Otter.Parser.psm1 ~1380/1459) - Codex.
3. Web: one mapping for all paths (bare `round` -> 8px, `round N` -> Npx,
   `pill` -> 9999px); WPF: the same on Border, Button and TextBox templates.
4. Tests: Web.Tests' `pillBtn` becomes `pill`; add `round` -> 8px on a card
   and a button, and `round 12` on the controls path (it is ignored today).
5. Examples that meant a pill switch to `pill` (e.g. examples/jeffreymacy.ot:
   `avatarBadge` and `navPlanBtn`).
6. Studio: `pill` as a toggle beside the radius field; `round` reads as 8px.

This is a visible change for existing programs: every bare `round` on a
control goes from pill to 8px corners. That is the point of the change, but
it should be a conscious decision.
