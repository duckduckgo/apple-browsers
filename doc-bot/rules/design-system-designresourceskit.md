---
alwaysApply: true
title: "DuckDuckGo iOS Design System & DesignResourcesKit (DRK)"
description: "DuckDuckGo iOS design system implementation through DesignResourcesKit including typography, colors, component strategy, enforcement mechanisms, and modularization guidelines"
keywords: ["design system", "DesignResourcesKit", "DRK", "typography", "colors", "icons", "UIKit", "SwiftUI", "Figma", "semantic colors", "Danger", "modularization"]
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

### Usage
**MANDATORY**: Use `Font(designSystemFont: .styleName)` for all text.

📖 **[See typography examples →](design-system-designresourceskit.examples.md#typography-examples)**

### Available Type Styles
- `.largeTitle` - Page titles and major headings
- `.title1`, `.title2`, `.title3` - Section headings
- `.body` - Primary body text (default)
- `.bodyLarge` - Emphasized body text
- `.bodySmall` - De-emphasized body text
- `.caption1`, `.caption2` - Supporting text
- `.footnote` - Fine print
- `.button` - Button text

## Color System

### Philosophy
**Semantic colors over literal colors**: Use `.textPrimary` instead of `.black`, use `.backgroundSecondary` instead of `.lightGray`.

### Mandatory Usage
**ALWAYS use `Color(designSystemColor: .tokenName)`** - NEVER hardcode colors.

📖 **[See color usage examples →](design-system-designresourceskit.examples.md#color-usage-examples)**

### Color Token Categories

**Text Colors**:
- `.textPrimary` - Primary text content
- `.textSecondary` - Supporting text
- `.textTertiary` - Disabled/placeholder text
- `.textInverted` - Text on dark backgrounds
- `.textLink` - Interactive links
- `.textError`, `.textSuccess`, `.textWarning` - Status messages

**Background Colors**:
- `.backgroundPrimary` - Main background
- `.backgroundSecondary` - Cards and sections  
- `.backgroundTertiary` - Subtle areas
- `.backgroundElevated` - Elevated surfaces

**Interactive Colors**:
- `.interactivePrimary` - Primary buttons/actions
- `.interactiveSecondary` - Secondary actions
- `.interactiveDisabled` - Disabled states

**Brand Colors**:
- `.brandPrimary` - DuckDuckGo orange
- `.brandSecondary` - Secondary brand color

## Icons & Glyphs

### Current State
Icons are **NOT yet in DesignResourcesKit**. They remain in the main iOS app.

### Usage Pattern
```swift
// Current pattern (will be updated when icons move to DRK)
Image(uiImage: DesignSystemImages.Glyphs.Size24.bookmark)
    .renderingMode(.template)
    .foregroundColor(Color(designSystemColor: .iconPrimary))
```

📖 **[See icon usage examples →](design-system-designresourceskit.examples.md#icon-usage-examples)**

## Component Patterns

### Philosophy
- **Consistency over customization**
- **Reuse common patterns**
- **Compose complex UIs from simple components**

### Available Components
📖 **[See component examples →](design-system-designresourceskit.examples.md#component-pattern-examples)**

## Implementation Guidelines

### SwiftUI Integration

**MANDATORY**: Always use design system tokens in SwiftUI views.

```swift
// ✅ CORRECT
Text("Title")
    .font(Font(designSystemFont: .title1))
    .foregroundColor(Color(designSystemColor: .textPrimary))

// ❌ INCORRECT  
Text("Title")
    .font(.system(size: 28, weight: .bold))
    .foregroundColor(.black)
```

### UIKit Integration

```swift
// ✅ CORRECT
label.font = UIFont(designSystemFont: .body)
label.textColor = UIColor(designSystemColor: .textPrimary)

// ❌ INCORRECT
label.font = UIFont.systemFont(ofSize: 17)
label.textColor = .black
```

## Dark Mode Support

**Automatic**: All design system colors automatically adapt to light/dark mode. **NEVER** manually check `colorScheme` or `traitCollection.userInterfaceStyle`.

📖 **[See dark mode examples →](design-system-designresourceskit.examples.md#dark-mode-adaptation-examples)**

## Adding New Design Elements

### When You Need New Colors
1. **First**: Check if existing semantic colors can work
2. **Then**: Discuss with design team
3. **Finally**: Add to DesignResourcesKit with proper semantic naming

### When You Need New Typography
1. **First**: Check if existing type styles can work  
2. **Then**: Consider if it's truly a new pattern vs. one-off styling
3. **Finally**: Add to DesignResourcesKit if it's a repeating pattern

### Process for Additions
1. Create issue in DesignResourcesKit repository
2. Get design team approval
3. Add with semantic naming
4. Update documentation
5. Use in implementation

## Enforcement

### Code Review Checklist
- [ ] No hardcoded colors (`.red`, `UIColor.blue`, `Color(red: 0.5...)`)
- [ ] No hardcoded fonts (`UIFont.systemFont`, `.system(size: 17)`)
- [ ] All text uses `Font(designSystemFont:)` or `UIFont(designSystemFont:)`
- [ ] All colors use `Color(designSystemColor:)` or `UIColor(designSystemColor:)`
- [ ] No manual dark mode handling

### SwiftLint Rules
We have custom SwiftLint rules that detect:
- Hardcoded color usage
- Direct system font usage
- Manual dark mode checks

### Danger Checks
Our Danger setup automatically checks for design system violations in pull requests.

## Migration Guide

### From Hardcoded Colors
```swift
// Before
.foregroundColor(.black)
.backgroundColor = UIColor.systemGray

// After  
.foregroundColor(Color(designSystemColor: .textPrimary))
.backgroundColor = UIColor(designSystemColor: .backgroundSecondary)
```

### From System Fonts
```swift
// Before
.font(.system(size: 17, weight: .medium))
.font = UIFont.systemFont(ofSize: 17)

// After
.font(Font(designSystemFont: .body))
.font = UIFont(designSystemFont: .body)
```

## Resources

- **Repository**: [DesignResourcesKit on GitHub](https://github.com/duckduckgo/DesignResourcesKit)
- **Figma**: [iOS Components](https://www.figma.com/file/GzGKD6gR24AHoUqVykX1ah/%F0%9F%93%B1-iOS-%26-iPadOS-Components)
- **Documentation**: This file + examples

---

📖 **For detailed implementation examples, see [design-system-designresourceskit.examples.md](design-system-designresourceskit.examples.md)**