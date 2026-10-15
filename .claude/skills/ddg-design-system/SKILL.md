---
name: ddg-design-system
description: Use when creating, changing or reviewing UI on iOS or macOS, including colors, typography, icons, shadows, spacing and reusable components from DesignResourcesKit (DRK), DesignResourcesKitIcons or UIComponents.
---

# Design system (DRK)

Figma defines the design intent. The code in `SharedPackages/Infrastructure/DesignResourcesKit`,
`SharedPackages/Infrastructure/DesignResourcesKitIcons` and `SharedPackages/UIComponents` defines
what is available; read it rather than assuming an API exists.

## Lookup order

For every color, font, icon or piece of repeated styling, stop at the first step that fits:

1. A DRK semantic color or typography style, or a DRKIcons asset in the matching size.
2. A common component, modifier or preset in UIComponents, or an existing usage nearby. Look
   before writing your own buttons, shadows, borders, corner radii or spacing.
3. Nothing fits: ask the user what to do. Figma and a designer should resolve the doubt.

`SingleUseColor` is the fallback when no semantic color fits. When you use one, say so explicitly
to the user and recommend confirming with a designer that no semantic color applies.

## Do

- Use semantic colors (`Color(designSystemColor:)`, `UIColor(designSystemColor:)`,
  `NSColor(designSystemColor:)`) and keep the screen's palette wiring and light/dark behavior.
- iOS: use DRK typography (`UIFont.daxBodyRegular()`, `.daxTitle1()` and similar) and keep
  Dynamic Type working; fix layouts for larger text rather than disabling it. macOS: DRK
  typography is iOS only, so follow the feature's existing conventions.
- Prefer system components when they meet the design.

## Don't

- Use `baseColor:` initializers, hex or RGB literals, or new color assets in the apps. They
  bypass palettes and dark mode.
- Duplicate a DRKIcons icon in app assets or swap it for a lookalike SF Symbol.
- Replace intentional platform, feature or branding differences with the nearest token just to
  remove literals, or restyle unrelated UI during a focused change.
- Add speculative abstractions. Extract shared code when a pattern actually repeats.

## Stop and ask a designer

- Ownership of a component is unclear, or it is unclear whether a visual difference is
  intentional.
- No existing token, icon or component matches the design.
- The change touches a shared element. List its other usages and show how they are affected
  before finalizing.

## Where new things go

- Figma atoms (colors, common typography): DRK, with purpose-based names (`textPrimary`, not
  `black`) and both light and dark values.
- Icons: DRKIcons, added with the `ddg-drk-add-icon` skill, which the user runs.
- Reusable composed UI and components: UIComponents.
- Feature-specific styling that is not part of the design system: keep it local, with a short
  comment on why it differs.

## Before finishing

- Check light and dark mode and any palette or theme variants.
- iOS: check Dynamic Type up to accessibility sizes.
- For a changed shared element, check its other consumers, not only the screen you worked on.
