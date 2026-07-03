---
name: ddg-drk-add-icon
description: Invoke ONLY when the user explicitly runs /ddg-drk-add-icon or names this skill by name (e.g. "use ddg-drk-add-icon to add these SVGs"). Do NOT auto-invoke from symptom/intent matching — the skill mutates the apple-browsers asset catalog and Swift files and creates a git commit, so it must be user-initiated. If the user asks about adding icons or Swift package assets without naming this skill, answer directly instead. Inputs are a list of local paths and/or HTTP URLs (one entry per icon); category (Glyph/Color/Recolorable) and size are derived from each filename. Handles imageset/symbolset creation, Contents.json variants, and the camelCase accessor in the matching DesignSystemImages+*.swift file, in a single batch commit.
---

# ddg-drk-add-icon

## Overview

Imports one **or more** SVGs into the `DesignResourcesKitIcons` Swift package at `SharedPackages/Infrastructure/DesignResourcesKitIcons`. For each icon, three things must always change together:

1. An `*.imageset/` (or `*.symbolset/` for Recolorable) directory under `DesignSystemImages.xcassets/{Category}/{Size}/` containing the SVG.
2. A `Contents.json` in that directory — format differs by category.
3. A `public static var` accessor in the matching `DesignSystemImages+Glyphs.swift` / `+Color.swift` / `+Recolorable.swift`, inserted alphabetically inside the right `SizeN` enum.

Forgetting any of the three leaves the icon unusable.

## Inputs

- **Required:** one or more local paths and/or `http(s)` URLs to SVGs. A single icon is just a list of length one — treat the singular and batch cases the same way.
- **Optional, only if a filename doesn't follow convention:** category, size, accessor name (per-icon).

Inputs may mix local paths and URLs in the same invocation, and may span multiple categories/sizes — they don't have to be homogeneous.

## Filename convention (drives everything else)

| Category    | Filename                          | Example                       |
|-------------|-----------------------------------|-------------------------------|
| Glyph       | `Title-Case-{size}.svg`           | `Pin-Remove-12.svg`           |
| Color       | `Title-Case-Color-{size}.svg`     | `Chat-Color-12.svg`           |
| Recolorable | `lower-case-recolorable-{size}.svg` | `check-recolorable-24.svg`  |

Allowed sizes: Glyph `12/16/20/24`, Color `12/16/24/32/42/72/96/128`, Recolorable `24`.

If the file you were given doesn't match, **rename it to match before continuing**. Don't invent new size buckets — confirm with the user instead.

## Steps

Run steps 1–6 **for each input icon in the list** (they're independent — fetch all first, then process). Step 7 is a single verification pass at the end.

1. **Get the file locally.** If input is a URL, `curl -fL -o /tmp/<basename> <url>`. If local, just note the path. When given multiple URLs, you may run the `curl`s in parallel.
2. **Parse the filename** to derive:
   - Category (Glyph / Color / Recolorable — by presence of `-Color-` or `-Recolorable-`).
   - Size (trailing number before `.svg`).
   - Base name (everything before the category/size suffix).
   - Accessor name = base name lowerCamelCased. For Color, drop the `Color` suffix from the variable name but **keep it in the resource name** (e.g. `Chat-Color-12.svg` → accessor `chat`, resource `.chatColor12`). For Recolorable, same shape — drop `Recolorable` from the variable name but **keep it in the resource** (e.g. `check-recolorable-24.svg` → accessor `check`, resource `.checkRecolorable24`). For Glyph, no suffix to drop — the whole base name becomes the camelCased variable and the resource is `<variable><size>` (e.g. `Pin-Remove-12.svg` → accessor `pinRemove`, resource `.pinRemove12`).
3. **Create the imageset/symbolset directory:**
   - Glyph: `SharedPackages/Infrastructure/DesignResourcesKitIcons/Sources/DesignResourcesKitIcons/DesignSystemImages.xcassets/Glyphs/{size}px/{Filename-without-.svg}.imageset/`
   - Color: same root, `Color/{size}px/...imageset/` — **exception: `Color/32x/`** (no `p`, matches existing repo state).
   - Recolorable: `Recolorable/{size}px/{Title-Cased-filename-without-.svg}.symbolset/` — the directory is Title-Case (e.g. `Check-Recolorable-24.symbolset/`) to match how Glyph and Color imageset directories are cased. (The existing `check-recolorable-24.svg` SVG predates this convention; new icons should follow it.)
4. **Copy the SVG into that directory.** If needed, rename the SVG to match the imageset/symbolset directory name (e.g. drop `Check-Recolorable-24.svg` inside `Check-Recolorable-24.symbolset/`). he `filename` field in `Contents.json` (next step) must reference the SVG file name exactly.
5. **Write `Contents.json`** in that same directory. Use the variant for the category:

   **Glyph:**
   ```json
   {
     "images" : [{ "filename" : "Pin-Remove-12.svg", "idiom" : "universal" }],
     "info" : { "author" : "xcode", "version" : 1 },
     "properties" : { "template-rendering-intent" : "template" }
   }
   ```

   **Glyph with `Recolorable` in the filename** (e.g. `Check-Recolorable-16.svg`) — same category and folder layout as a regular Glyph, but **omit the `properties` block entirely** so the asset is treated as "Default image" (preserves the SVG's own colors) instead of "Template image" (tinted by foreground color):
   ```json
   {
     "images" : [{ "filename" : "Check-Recolorable-16.svg", "idiom" : "universal" }],
     "info" : { "author" : "xcode", "version" : 1 }
   }
   ```
   The accessor still keeps the full base name (including `Recolorable`), e.g. `checkRecolorable: DesignSystemImage { .init(resource: .checkRecolorable16) }`. Only the `Recolorable` (`.symbolset`) category drops the suffix from the accessor — Glyphs do not.

   **Color** (no `properties`):
   ```json
   {
     "images" : [{ "filename" : "Chat-Color-12.svg", "idiom" : "universal" }],
     "info" : { "author" : "xcode", "version" : 1 }
   }
   ```

   **Recolorable** (`symbols` array, `.symbolset`, hierarchical rendering):
   ```json
   {
     "info" : { "author" : "xcode", "version" : 1 },
     "properties" : { "symbol-rendering-intent" : "hierarchical" },
     "symbols" : [{ "filename" : "Check-Recolorable-24.svg", "idiom" : "universal" }]
   }
   ```

6. **Add the Swift accessor** to the right file in `SharedPackages/Infrastructure/DesignResourcesKitIcons/Sources/DesignResourcesKitIcons/`:
   - Glyph → `DesignSystemImages+Glyphs.swift`
   - Color → `DesignSystemImages+Color.swift`
   - Recolorable → `DesignSystemImages+Recolorable.swift`

   Find the `public enum Size{N}` block matching the icon's size and insert a new line **in alphabetical order by accessor name**:
   ```swift
   public static var pinRemove: DesignSystemImage { .init(resource: .pinRemove12) }
   ```
   The `.pinRemove12` reference is auto-generated by Xcode at build time from the imageset folder name — do not try to define it manually.

7. **Verify (once, after all icons are processed)**: `git status` should show, per icon, one new imageset/symbolset directory with two files (the SVG and `Contents.json`), plus modifications to the `DesignSystemImages+*.swift` file(s) for each category touched. The number of modified Swift files equals the number of distinct categories in the batch (1–3). Build the package in Xcode (or rely on the user's next build) — if any accessor still red-underlines, the corresponding imageset folder name is mistyped.

## Worked example (this just happened on `dominik/macos-26-menu-icons`)

Input: `/Users/ayoy/Downloads/Pin-Remove-12.svg`

- Category: Glyph (no `-Color-` / `-Recolorable-`). Size: 12. Base: `Pin-Remove`. Accessor: `pinRemove`.
- New dir: `.../Glyphs/12px/Pin-Remove-12.imageset/` with `Pin-Remove-12.svg` and the Glyph `Contents.json` (template intent).
- Inserted in `DesignSystemImages+Glyphs.swift` Size12 enum between `pin` and `platform`:
  ```swift
  public static var pinRemove: DesignSystemImage { .init(resource: .pinRemove12) }
  ```

Commit landed as `41d4ea6e95 Add Pin-Remove and Window-Duplicate 12px icons` — five files: two SVGs, two `Contents.json`, one Swift edit.

## Common mistakes

- **Wrong Contents.json for category.** Glyph without `template-rendering-intent` renders as filled black — not tinted. Color with `template-rendering-intent` strips the colors. **Exception:** Glyphs whose filename contains `Recolorable` (e.g. `Check-Recolorable-16.svg`) must omit `template-rendering-intent` so they render as Default and keep their own colors.
- **`.imageset` for Recolorable.** Recolorable must be `.symbolset` with `symbols` (not `images`) — Xcode silently ignores it otherwise.
- **`Color/32px/` instead of `Color/32x/`.** The 32-size directory is `32x` in this repo. All other sizes are `{N}px`.
- **Alphabetical insertion drift.** Several existing files (notably `+Color.swift` Size32 and Size128) aren't strictly alphabetical. Don't replicate the disorder — insert your line in the correct alphabetical position and leave neighbours alone.
- **Recolorable casing.** The `.symbolset` directory is Title-Case (e.g. `Check-Recolorable-24.symbolset/`) like the Glyph and Color imageset directories. The SVG inside should ideally follow the directory's casing (Title-Case) — note that the existing `check-recolorable-24.svg` uses lowercase historically; either works, but match the directory for new icons. The `filename` field in `Contents.json` must reference whatever the SVG is actually named.
- **Manually editing `ImageResource`.** The `.pinRemove12`, `.chatColor12`, etc. accessors are generated by Xcode from the asset catalog. Don't grep for them — they only exist post-build.

## Batching notes

When the input list has more than one icon:

- **One commit for the batch.** Don't make a commit per icon. Commit message convention from recent history: `Add <Title> and <Title> {size}px icons` (two icons, same size) or `Add <N> icons` / `Add <Title>, <Title>, and <Title> icons` when sizes/categories are mixed — match the style of nearby commits in `git log` for the asset catalog.
- **Swift edits coalesce.** All Glyphs land in `DesignSystemImages+Glyphs.swift`, all Colors in `+Color.swift`, all Recolorables in `+Recolorable.swift`. Open each file at most once; insert every new accessor in its correct `Size{N}` enum (alphabetically) before moving on.
- **Same size + same category = same enum.** When several icons share a size and category, insert them all into the same `Size{N}` block in one pass so you don't re-locate the block per icon.
- **Independent failures.** If one input is malformed (bad filename, wrong size bucket), stop and confirm with the user — don't silently skip it and ship the rest, since the user is expecting the full set.
- **Don't parallelise file writes.** Asset-catalog directory creation and Swift edits are cheap and ordering-sensitive (alphabetical insertion); run them sequentially. Only the initial `curl` fetches are worth parallelising.
