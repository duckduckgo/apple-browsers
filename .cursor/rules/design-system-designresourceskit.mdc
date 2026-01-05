---
alwaysApply: true
---

# DuckDuckGo iOS Design System & DesignResourcesKit (DRK)

## Overview

The DuckDuckGo iOS design system is implemented through **DesignResourcesKit (DRK)**, a shared Swift package that contains our design tokens, type styles, colors, and design system elements.

**Repository**: [https://github.com/duckduckgo/DesignResourcesKit](https://github.com/duckduckgo/DesignResourcesKit)

**Figma Designs**: [🖱️ iOS & iPadOS Components](https://www.figma.com/file/GzGKD6gR24AHoUqVykX1ah/%F0%9F%93%B1-iOS-%26-iPadOS-Components?type=design&node-id=3938%3A23329&mode=design&t=0fuiNF84nnV5zExC-1)

### What DRK Contains

✅ **Currently Included**:
- **Type styles and typography** (based on system styles)
- **Semantic color system** (with light/dark mode support)
- **Design tokens and foundations**

🔄 **Future Expansion**:
- **Reusable components** (when patterns emerge)
- **Advanced interaction patterns**

❌ **Not Included**:
- **Icons** (remain in iOS app directly for now)

## ⚠️ Critical Rule: Don't Break the Design System

> **If you take only one thing away from this documentation**: 
> **Don't add new colors or type styles outside of the design system without reading the guidelines below.**

Breaking the design system:
- **Undermines consistency** across the app
- **Creates maintenance debt** with scattered styles
- **Breaks accessibility** features like dynamic type
- **Fragments the user experience**

## Typography System

### Philosophy

Our typography system is **based on system styles** rather than hardcoded sizes. This ensures:
- **Automatic dynamic type support** for accessibility
- **Consistent scaling** across different user preferences
- **Platform-appropriate styling** that feels native

### UIKit Usage

DRK defines **static functions on UIFont** for all typography.

**Example:** See [uikit-typography-usage.swift](design-system-designresourceskit/uikit-typography-usage.swift)

#### Available Typography Styles

**Example:** See [uikit-typography-styles.swift](design-system-designresourceskit/uikit-typography-styles.swift)

#### Best Practices for UIKit

**Example:** See [uikit-typography-best-practices.swift](design-system-designresourceskit/uikit-typography-best-practices.swift)

### SwiftUI Usage

DRK provides **view modifiers and extensions** for SwiftUI that should be used instead of direct font access.

**Example:** See [swiftui-typography-usage.swift](design-system-designresourceskit/swiftui-typography-usage.swift)

#### Available SwiftUI Typography Modifiers

**Example:** See [swiftui-typography-modifiers.swift](design-system-designresourceskit/swiftui-typography-modifiers.swift)

#### SwiftUI Code Review Guidelines

**When reviewing PRs**: Look for `.font()` usage as a red flag.

**Example:** See [swiftui-code-review-red-flags.swift](design-system-designresourceskit/swiftui-code-review-red-flags.swift)

### Emergency Escape Hatch (Avoid!)

**For legacy layout fixes only**: If you absolutely must disable dynamic type, there's a deliberately obtusely named function:

```swift
// ❌ LAST RESORT: Only for fixing legacy layouts
let fixedFont = UIFont.daxFontOutsideOfTheDesignSystemToFixLegacyLayoutBreakage()
```

**Important Notes**:
- This function **may not exist** in current DRK versions
- If you need it, you must **revert the commit** that removed it: [Commit 971979d](https://github.com/duckduckgo/DesignResourcesKit/pull/1/commits/971979d3dcd95567b9812b800eb22ab1611ce3a5)
- This is **deliberately annoying** to discourage usage
- **Always prefer** fixing the layout to support dynamic type instead

## Color System

### Semantic Color Approach

Our color system uses **semantic naming** rather than literal colors (e.g., "primary text" instead of "black"). This enables:
- **Automatic dark mode support**
- **Future theme flexibility**
- **Accessibility compliance**
- **Consistent visual hierarchy**

### Color Categories

#### Text Colors
**UIKit Example:** See [colors-text-uikit.swift](design-system-designresourceskit/colors-text-uikit.swift)

**SwiftUI Example:** See [colors-text-swiftui.swift](design-system-designresourceskit/colors-text-swiftui.swift)

#### Background Colors
**Example:** See [colors-background.swift](design-system-designresourceskit/colors-background.swift)

#### Control Colors
```swift
// UIKit
button.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
button.backgroundColor = UIColor(designSystemColor: .controlsFillSecondary)

// SwiftUI
Button("Action") { }
    .foregroundColor(Color(designSystemColor: .controlsFillPrimary))
    .background(Color(designSystemColor: .controlsFillSecondary))
```

#### Button-Specific Colors
```swift
// UIKit
primaryButton.backgroundColor = UIColor(designSystemColor: .buttonPrimaryBackground)
primaryButton.setTitleColor(UIColor(designSystemColor: .buttonPrimaryText), for: .normal)

secondaryButton.backgroundColor = UIColor(designSystemColor: .buttonSecondaryBackground)
secondaryButton.setTitleColor(UIColor(designSystemColor: .buttonSecondaryText), for: .normal)

// SwiftUI
Button("Primary Action") { }
    .foregroundColor(Color(designSystemColor: .buttonPrimaryText))
    .background(Color(designSystemColor: .buttonPrimaryBackground))

Button("Secondary Action") { }
    .foregroundColor(Color(designSystemColor: .buttonSecondaryText))
    .background(Color(designSystemColor: .buttonSecondaryBackground))
```

#### Accent Colors
```swift
// UIKit
view.tintColor = UIColor(designSystemColor: .accent)

// SwiftUI
Image(systemName: "heart.fill")
    .foregroundColor(Color(designSystemColor: .accent))
```

### Anti-patterns: What NOT to Do

**Example:** See [colors-anti-patterns.swift](design-system-designresourceskit/colors-anti-patterns.swift)

## Enforcement and Code Review

### Automated Enforcement

#### Danger Integration
**Asset catalog enforcement**: We use [Danger](https://danger.systems/) to prevent new colors being added directly to iOS app asset catalogs.

**Example:** See [danger-integration.rb](design-system-designresourceskit/danger-integration.rb)

### Manual Code Review Checklist

#### ✅ Look for in PRs:
- **DRK typography usage**: `UIFont.daxTitle1()`, `.daxBody()` modifiers
- **DRK color usage**: `UIColor(designSystemColor: .textPrimary)`
- **No hardcoded colors**: No hex values, RGB tuples, or named colors
- **No `.font()` modifiers** in SwiftUI (red flag for design system violations)
- **Semantic naming**: Colors described by purpose, not appearance

#### Code Review Examples

**Example:** See [code-review-checklist.swift](design-system-designresourceskit/code-review-checklist.swift)

### Opportunistic Improvements

**Most of the iOS app currently does not use the design system**, so you're encouraged to:

1. **Opportunistically refactor** old code to use DRK when you encounter it
2. **Update hardcoded colors** to semantic colors when working in an area
3. **Replace system fonts** with DRK typography when touching text styling
4. **File follow-up tickets** for systematic cleanup when you notice patterns

#### Example: Opportunistic Refactoring

**Example:** See [opportunistic-refactoring.swift](design-system-designresourceskit/opportunistic-refactoring.swift)

## Components

### Current State: Minimal Component Library

We primarily use **system components** rather than custom ones, following iOS design guidelines. This is different from our Android app which has more custom components.

**Philosophy**: 
- **System components first** - leverages platform conventions
- **Custom components only when needed** - avoid overengineering
- **Reusable when patterns emerge** - extract when used in multiple places

### Existing Custom Components

#### Blue Button (Reusable)
Our primary custom component used across multiple screens.

**Example:** See [blue-button-component.swift](design-system-designresourceskit/blue-button-component.swift)

**Candidate for DRK**: This button is used in multiple places and should be extracted into DesignResourcesKit as a reusable component.

### Future Component Strategy

#### When to Create Components

**✅ Create a component when**:
- Pattern is used in **3+ different contexts**
- Styling is **complex or specialized**
- Behavior needs to be **consistent across usage**
- Component **encapsulates design system tokens**

**❌ Don't create a component when**:
- Used in only **one place** (keep it local)
- **System component exists** that meets needs
- Component would be **overly generic** or complex

#### Emerging Patterns to Watch

Look for these patterns that might become components:

```swift
// Bottom sheets - if format becomes consistent
struct BottomSheetView: View {
    // Consistent styling, behavior, animation
    // Could become reusable component
}

// Info cards/panels - if layout patterns emerge  
struct InfoCardView: View {
    // Standard card styling with DRK colors
    // Could be extracted if reused
}

// Form elements - if custom styling is needed
struct FormFieldView: View {
    // Consistent form field styling
    // Could become component library
}
```

#### Component Creation Process

1. **Identify the pattern** in your current work
2. **Check if existing implementations** could be generalized
3. **Design the API** to be flexible but opinionated
4. **Implement using DRK tokens** for colors, typography, spacing
5. **Add to DesignResourcesKit** package
6. **Update existing usages** to use the new component
7. **Document the component** with usage examples

**Example:** See [component-creation-example.swift](design-system-designresourceskit/component-creation-example.swift)

## Modularization Strategy

### Why DRK is a Separate Package

**High friction is a feature**: Making DRK a separate module provides beneficial constraints:

1. **Immutability encouragement**: Changes require more thought and process
2. **API stability**: Forces consideration of breaking changes
3. **Reusability**: Can be shared across iOS/macOS if needed
4. **Clear boundaries**: Separates design tokens from app logic
5. **Version control**: Can be tagged and versioned independently

### Design System Evolution

**Original Discussion**: [Tech Design: How to modularise iOS/macOS design system elements](✓ Tech Design: How to modularise iOS/macOS design system elements)

**Guiding Principles**:
- **Start minimal**: Don't over-engineer early
- **Evolve based on usage**: Add components when patterns emerge
- **Maintain consistency**: All additions should follow established patterns
- **Document decisions**: Keep rationale for future developers

## Working with DesignResourcesKit

### Adding New Design Tokens

**Process for adding colors/typography**:

1. **Design system first**: Ensure token is defined in Figma
2. **Semantic naming**: Use purpose-based names (`textPrimary` not `black`)
3. **Light/dark variants**: Define both light and dark mode values
4. **PR to DRK**: Add to DesignResourcesKit repository
5. **Update app**: Use new tokens in consuming apps
6. **Documentation**: Update usage examples and guidelines

### Updating DRK Version

**In consuming app (iOS/macOS):**

**Example:** See [updating-drk-version.swift](design-system-designresourceskit/updating-drk-version.swift)

**Testing DRK changes**:
- Test in both **light and dark modes**
- Verify **dynamic type scaling** works correctly  
- Check **accessibility** with larger text sizes
- Test on **different device sizes**

### Local Development

**For iterating on DRK:**

**Example:** See [local-development.sh](design-system-designresourceskit/local-development.sh)

## Resources and References

### Official Resources

- **GitHub Repository**: [duckduckgo/DesignResourcesKit](https://github.com/duckduckgo/DesignResourcesKit)
- **Figma Designs**: [iOS & iPadOS Components](https://www.figma.com/file/GzGKD6gR24AHoUqVykX1ah/%F0%9F%93%B1-iOS-%26-iPadOS-Components?type=design&node-id=3938%3A23329&mode=design&t=0fuiNF84nnV5zExC-1)

### Related Documentation

- **Colors**: [Tech Design: How to organise colors and icons in iOS and macOS wrt the design system](✓ Tech Design: How to organise colors and icons in iOS and macOS wrt the design system)
- **Colors Update**: [Tech Design: Redefine design system colors in DesignResourcesKit](✓ Tech Design: Redefine design system colors in DesignResourcesKit)
- **Typography**: [Tech Design: How to organise typography/label styles in iOS and macOS wrt the design system](✓ Tech Design: How to organise typography/label styles in iOS and macOS wrt the design system)
- **Enforcement**: [Use danger to stop new colors being added to the iOS app](✓ Use danger to stop new colors being added to the iOS app)

### Quick Reference

#### UIKit Checklist
- [ ] Use `UIFont.daxTitle1()`, `UIFont.daxBody()`, etc.
- [ ] Use `UIColor(designSystemColor: .textPrimary)` etc.
- [ ] No hardcoded colors or fonts
- [ ] No system colors for app content

#### SwiftUI Checklist  
- [ ] Use `.daxTitle1()`, `.daxBody()` modifiers
- [ ] Use `Color(designSystemColor: .textPrimary)` etc.
- [ ] Avoid `.font()` modifier (red flag in reviews)
- [ ] No hardcoded colors

#### Code Review Checklist
- [ ] No new colors in asset catalogs
- [ ] DRK typography used consistently
- [ ] Semantic color naming
- [ ] No hardcoded styling
- [ ] Opportunistic improvements to legacy code

---

**Remember**: The design system is only as strong as our commitment to using it. Every PR is an opportunity to improve consistency and user experience.
