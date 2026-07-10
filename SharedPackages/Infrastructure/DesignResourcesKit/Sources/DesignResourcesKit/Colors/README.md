# DesignResourcesKit colours

This directory is the single source of the app's colours for both iOS and macOS. Everything a
feature draws with — `Color(designSystemColor:)`, `NSColor(designSystemColor:)`,
`Color(baseColor:)`, `Color(singleUseColor:)` — resolves here.

The code is organised into five **tiers**. Swift Package Manager has no per-directory access
control, so the folder boundaries are not enforced by the compiler — **this README is the
enforcement mechanism.** If you are adding or changing a colour, read the [dependency rule](#the-dependency-rule)
and the [decision table](#where-does-a-new-colour-go) before you touch anything.

> **Migration status (2026-07).** This layout was introduced in Phase 1 of an in-progress
> colour-system migration. The authoritative, self-contained plan is kept alongside the tooling
> at `scripts/color-system-implementation-plan.md`. Two things described below are *targets*, not
> yet wired up:
> 1. **Generation.** The palette lookup tables are hand-written today. From Phase 4 they are
>    generated from a Figma export by `scripts/color-sync.py`; the files that will carry a
>    `⚠ GENERATED` header are called out below.
> 2. **One shared vocabulary.** Today macOS resolves through the `Shared*` tier while iOS keeps
>    a parallel enum and palette layer under `iOS/` subfolders. Only **Primitives** and
>    **Utilities** are genuinely cross-platform right now. The two vocabularies converge (iOS drops
>    its parallel layer) in Phases 4–6.

---

## The three axes

A rendered colour is chosen along three independent axes. Keeping them separate is what makes the
system tractable.

| Axis | What picks it | Where |
|---|---|---|
| **① Palette / theme** | `DesignSystemPalette.current` | Set once at launch on iOS; on every theme switch on macOS. macOS also has 7 themes (Cool Gray … Violet); iOS has none. |
| **② Legacy vs rebrand** | a property of the selected palette | `DesignSystemPalette.current.isRebranded` on both platforms — `.default` = rebranded, `.legacy` = pre-2026. The host app selects the palette at launch from the 2026 rebrand flag. *After the flag is removed:* gone entirely (only `.default` remains). |
| **③ Light vs dark** | the OS trait / appearance | Resolved lazily at render time from a `DynamicColor`'s light/dark pair (the `Utilities/` tier). Never branch on this yourself. |

The rebrand flag (axis ②) is temporary. Everything legacy is quarantined so that removing the
flag is a *delete-files* exercise, never an untangle-logic one — see `Primitives/Legacy/` and the
`.legacy` palette.

---

## The request pipeline

One request flows strictly downward through the tiers:

```
    Color(designSystemColor: .textPrimary)              ← API tier: public initializer
      → DesignSystemPalette.current.paletteDefinition   ← API tier: which palette is active
        → paletteDefinition.dynamicColor(for: .textPrimary)   ← Palettes tier: name → DynamicColor
          → DynamicColor(light:, dark:)                 ← value, sourced from a Primitive or inline hex
            → .color / .dynamicProvider                 ← Utilities tier: trait-reactive Color/UIColor/NSColor
```

The vocabulary case (`.textPrimary`) names *what* the colour is for; the active palette decides
*which* concrete `DynamicColor` that name maps to; the `Utilities/` tier resolves light/dark at draw time.

The resolver that performs "name → `DynamicColor`" is platform-split today:
- **macOS:** `Palettes/SharedColorPaletteDefinition+DynamicColors.swift` (switch) + the palette
  structs' `static var … : DynamicColor` tables.
- **iOS:** `Palettes/iOS/ColorPaletteDefinition.swift` (protocol) + `DefaultColorPalette` /
  `RebrandedColorPalette` (`Palettes/iOS/`).

---

## The tiers

```
Colors/
├── README.md            you are here
│
├── Utilities/           ⓪ trait-reactive machinery — how a colour becomes a Color/UIColor/NSColor
│   ├── DynamicColor.swift            a light/dark value pair, resolved lazily
│   ├── Color+Hex.swift               0xRRGGBB[AA] → Color
│   ├── UIKitDynamicColor.swift       DynamicColor → UIColor
│   ├── AppKitDynamicColor.swift      DynamicColor → NSColor
│   └── TintShade.swift               overlay opacity steps
│
├── Primitives/          ① the ONLY place hand-written hex is allowed to live
│   ├── RebrandingColor.swift         shared 2026 ramps (GrayScale, Eggshell, Mandarin, …).
│   │                                 Generated from Figma; do not hand-edit after Phase 3.
│   └── Legacy/                       pre-2026 ramps + one-off xHEX globals. Frozen. Deleted
│                                     wholesale when the rebrand flag is removed.
│
├── Semantic/            ② the vocabulary — case names only, no values
│   ├── SharedDesignSystemColor.swift macOS + (later) shared enum, grouped by Figma group
│   └── iOS/                          iOS's own DesignSystemColor + SingleUseColor.
│                                     TEMPORARY: merges into the shared enum in Phase 6.
│
├── Palettes/            ③ name → DynamicColor lookup tables (one per palette/theme)
│   ├── SharedColorPaletteDefinition.swift            protocol: the full set of tokens
│   ├── SharedColorPaletteDefinition+DynamicColors.swift   macOS resolver (case → DynamicColor)
│   ├── SharedColorPaletteDefinition+BaseColors.swift      macOS BaseColor resolver
│   ├── FigmaColorPalette.swift       macOS pre-2026 default  (→ renamed LegacyColorPalette, Phase 4)
│   ├── LatestColorPalette.swift      macOS rebranded default (→ renamed DefaultColorPalette, Phase 4)
│   ├── Themes/                       macOS-only themes (Cool Gray … Violet); iOS never sees these
│   └── iOS/                          iOS palette layer. TEMPORARY: becomes a thin adapter over the
│                                     generated palettes in Phase 5, deleted in Phase 6.
│
└── API/                 the public surface — signatures are frozen until Phase 6
    ├── ColorExtensions.swift         Color/UIColor/NSColor(designSystemColor:/singleUseColor:/baseColor:)
    ├── ColorPalette.swift            DesignSystemPalette.current + the ColorPalette enum (selection);
    │                                 `.isRebranded` is the single rebrand switch since Phase 2
    ├── ColorPalette+BaseColors.swift iOS BaseColor resolver
    └── BaseColor.swift               the raw-ramp escape hatch (no semantic meaning)
```

### The dependency rule

**A tier may reference names from its own tier or a *lower-numbered* tier — never a higher one.**

| Tier | May depend on | Must never depend on |
|---|---|---|
| ⓪ Utilities | (nothing in `Colors/`) | anything above |
| ① Primitives | Utilities | Semantic, Palettes, API |
| ② Semantic | (nothing — pure names) | Palettes, API |
| ③ Palettes | Semantic, Primitives, Utilities | API |
| API | everything below | — |

Practical consequences:
- **Values live at the bottom, names in the middle, selection at the top.** A primitive never
  knows a semantic name; a semantic enum never knows a hex value; the two meet only in a Palette.
- **No hand-written hex above `Primitives/`.** Generated palette files may contain hex (63% of
  semantic tokens carry baked-in opacity that has no primitive), but each such value is
  Figma-generated and carries a provenance comment — never typed by hand.
- **Feature code outside this package touches only the `API/` initializers and the public
  vocabulary** (`DesignSystemColor`, `SingleUseColor`, `BaseColor`). The palette tables,
  primitives, and utilities are implementation details.

---

## Where does a new colour go?

Follow the first row that matches.

| You have… | Put it in | Notes |
|---|---|---|
| A **raw ramp value** from the Figma rebrand palette | `Primitives/RebrandingColor.swift` | Don't hand-edit — re-export from Figma and regenerate (Phase 3+). |
| A **semantic colour** design has defined in a Figma theme (e.g. `Surface/Backdrop`) | the vocabulary — add to the manifest, regenerate | It appears as a case in `Semantic/…` and resolves through every palette in `Palettes/`. Every Figma-mapped token gets a case (there is no "staged" state). |
| A semantic colour that is **used app-wide but not yet in Figma** | `Palettes/ManualColorTokens.swift` *(arrives Phase 4)* | Hand-written escape hatch. File a request for design to tokenise it, after which it graduates into the manifest and this entry disappears. |
| A colour used in **exactly one place** on iOS | `SingleUseColor` (`Semantic/iOS/SingleUseColor.swift`) | See the [promotion rule](#the-singleusecolor-promotion-rule). |
| A **legacy-only** value | nowhere — legacy is frozen | `Primitives/Legacy/` and `LegacyColorPalette` are being deleted, not extended. |
| A raw ramp swatch with **no semantic meaning** (rare) | `BaseColor` (`API/BaseColor.swift`) | Resolved through the active palette so it still tracks palette changes. |

If a colour would force a hand-written hex value above the `Primitives/` tier, stop: it belongs
in a primitive, in Figma, or (temporarily) in `ManualColorTokens`.

---

## The `SingleUseColor` promotion rule

`SingleUseColor` is a deliberately narrow escape hatch for a colour needed in **one** place that
isn't (yet) part of the semantic system.

> **The moment a `SingleUseColor` is needed in a second place, promote it** to a semantic token
> (`DesignSystemColor` / the shared vocabulary) instead of reading the single-use case from two
> call sites.

This keeps the hatch from ratcheting into a shadow vocabulary. Promotion means: add the token to
the manifest, map the legacy iOS case to it, and migrate both call sites. Single-use cases that
survive triage (genuinely one place) stay; everything else graduates. The onboarding-only
`SingleUseColor.Rebranding` shim is a temporary bulk exception and is removed in Phase 6.

---

## The Figma update loop

The system is designed so that a design change is a **regenerate-and-review** step, not a
hand-edit-in-five-places chore. Once the tooling lands (Phase 3+):

1. Designer re-exports the colour tokens from Figma.
2. Drop the export verbatim into `scripts/color-tokens/` (never hand-edit exported JSON).
3. Run `scripts/color-sync.py check` (all subcommands) to see the drift against the code.
4. Review the reported drift, then `update` / `generate`.
5. The **parity suite** (below) reports the exact rendered-colour diff.
6. Review the diff and commit the regenerated files + the new baseline together.

One command, one reviewable diff, no hand edits. The Figma ⇄ code correspondence:

| Figma | Code | Mechanism |
|---|---|---|
| `Color Palette (Rebrand)` | `Primitives/RebrandingColor.swift` | `color-sync.py primitives update` |
| `Theme Color/Default` | rebranded default palette | `color-sync.py semantic generate` |
| `Theme Color/Default (Pre 2026)` | legacy default palette | 〃 |
| `Theme Color/{Cool Gray … Violet}` | `Palettes/Themes/*` (macOS only) | 〃 |
| token paths + manifest | the semantic enum + protocol + resolver | 〃 |
| not in Figma | `Palettes/ManualColorTokens.swift` | hand-written, flagged `"manual": true` in the manifest |

---

## The parity guardrail

`Tests/DesignResourcesKitTests/ColorParityTests.swift` resolves **every reachable colour, in
every palette, in light and dark** to an RGBA hex string and diffs it against committed baselines
(`Tests/DesignResourcesKitTests/Baselines/{ios,macos}-colors.json`). It is the safety net for
every change in this directory: a move, a rename, or a regeneration must leave the diff **empty**
unless the change is a deliberate, reviewed value change.

- Run it: `swift test` (macOS); `xcodebuild test -scheme DesignResourcesKit -destination 'platform=iOS Simulator,name=…'` (iOS).
- Re-record after an intentional value change: `RECORD=1 swift test` (macOS), or pass
  `TEST_RUNNER_RECORD=1` to the simulator run — then review the baseline diff like any other.
- Never edit a baseline to make a red suite pass. An unexpected non-zero diff is a bug to
  investigate, not a baseline to overwrite.
