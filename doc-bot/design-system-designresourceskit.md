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

### UIKit Usage

DRK defines **static functions on UIFont** for all typography:

```swift
// ✅ CORRECT: Use DRK typography functions directly
let titleLabel = UILabel()
titleLabel.font = UIFont.daxTitle1()
titleLabel.text = "Main Title"

let bodyLabel = UILabel()
bodyLabel.font = UIFont.daxBody()
bodyLabel.text = "Body content that scales with dynamic type"

let captionLabel = UILabel()
captionLabel.font = UIFont.daxCaption()
titleLabel.text = "Small caption text"
```

#### Available Typography Styles

```swift
// Large titles and headers
UIFont.daxTitle1()      // Largest title
UIFont.daxTitle2()      // Secondary title
UIFont.daxTitle3()      // Tertiary title

// Body text
UIFont.daxBody()        // Standard body text
UIFont.daxBodySemibold() // Emphasized body text

// Small text
UIFont.daxCaption()     // Caption text
UIFont.daxFootnote()    // Footnote text

// Special cases
UIFont.daxCallout()     // Callout text
UIFont.daxSubheadline() // Subheading text
```

#### Best Practices for UIKit

```swift
// ✅ CORRECT: Use typography directly without modification
class FeatureViewController: UIViewController {
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var bodyLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Typography is automatically configured for dynamic type
        titleLabel.font = UIFont.daxTitle2()
        bodyLabel.font = UIFont.daxBody()
        
        // Colors should also come from design system
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
        bodyLabel.textColor = UIColor(designSystemColor: .textSecondary)
    }
}

// ❌ INCORRECT: Don't modify or override DRK fonts
titleLabel.font = UIFont.daxBody().withSize(18) // Don't override size
bodyLabel.font = UIFont.systemFont(ofSize: 16)  // Don't use system fonts
```

### SwiftUI Usage

DRK provides **view modifiers and extensions** for SwiftUI that should be used instead of direct font access:

```swift
// ✅ CORRECT: Use DRK view modifiers
struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Main Title")
                .daxTitle1()
                .foregroundColor(Color(designSystemColor: .textPrimary))
            
            Text("Secondary heading")
                .daxTitle3()
                .foregroundColor(Color(designSystemColor: .textPrimary))
            
            Text("Body content that automatically supports dynamic type and accessibility features.")
                .daxBody()
                .foregroundColor(Color(designSystemColor: .textSecondary))
            
            Text("Small caption text")
                .daxCaption()
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
        .padding()
    }
}

// ❌ INCORRECT: Don't use .font() modifier
Text("Title")
    .font(.title2) // This makes it harder to spot design system violations

Text("Body")
    .font(Font(UIFont.daxBody())) // Don't access UIFont directly
```

#### Available SwiftUI Typography Modifiers

```swift
// View modifiers for typography
.daxTitle1()        // Largest title
.daxTitle2()        // Secondary title  
.daxTitle3()        // Tertiary title
.daxBody()          // Standard body text
.daxBodySemibold()  // Emphasized body text
.daxCaption()       // Caption text
.daxFootnote()      // Footnote text
.daxCallout()       // Callout text
.daxSubheadline()   // Subheading text
```

#### SwiftUI Code Review Guidelines

**When reviewing PRs**: Look for `.font()` usage as a red flag:

```swift
// 🚨 RED FLAG: Using .font() likely indicates design system violation
Text("Title")
    .font(.title) // Should be .daxTitle2() or similar

Text("Body")  
    .font(.system(size: 16)) // Should be .daxBody()

// ✅ CORRECT: Using DRK modifiers
Text("Title")
    .daxTitle2()

Text("Body")
    .daxBody()
```

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
```swift
// UIKit
label.textColor = UIColor(designSystemColor: .textPrimary)    // Main text
label.textColor = UIColor(designSystemColor: .textSecondary)  // Supporting text
label.textColor = UIColor(designSystemColor: .textLink)       // Interactive text

// SwiftUI
Text("Primary text")
    .foregroundColor(Color(designSystemColor: .textPrimary))

Text("Secondary text")
    .foregroundColor(Color(designSystemColor: .textSecondary))

Text("Link text")
    .foregroundColor(Color(designSystemColor: .textLink))
```

#### Background Colors
```swift
// UIKit
view.backgroundColor = UIColor(designSystemColor: .background)  // Main app background
view.backgroundColor = UIColor(designSystemColor: .surface)     // Card/panel background
view.backgroundColor = UIColor(designSystemColor: .panel)       // Secondary panel

// SwiftUI
VStack {
    // Content
}
.background(Color(designSystemColor: .background))

Rectangle()
    .fill(Color(designSystemColor: .surface))
```

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

```swift
// ❌ NEVER: Hardcoded colors
view.backgroundColor = UIColor.black
text.foregroundColor = Color.blue
button.setTitleColor(UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0), for: .normal)

// ❌ NEVER: System colors for app content
view.backgroundColor = UIColor.systemBackground  // Use .background instead
label.textColor = UIColor.label                 // Use .textPrimary instead

// ❌ NEVER: Manual dark mode handling
@Environment(\.colorScheme) var colorScheme
let textColor = colorScheme == .dark ? Color.white : Color.black // Use semantic colors!

// ✅ CORRECT: Always use semantic design system colors
view.backgroundColor = UIColor(designSystemColor: .background)
label.textColor = UIColor(designSystemColor: .textPrimary)
```

## Enforcement and Code Review

### Automated Enforcement

#### Danger Integration
**Asset catalog enforcement**: We use [Danger](https://danger.systems/) to prevent new colors being added directly to iOS app asset catalogs:

```ruby
# Dangerfile example
if git.added_files.any? { |file| file.include?("Assets.xcassets") && file.include?("colorset") }
  fail("🚨 New colors detected in asset catalog. Use DesignResourcesKit instead!")
end
```

This ensures all colors go through the design system rather than being added ad-hoc.

### Manual Code Review Checklist

#### ✅ Look for in PRs:
- **DRK typography usage**: `UIFont.daxTitle1()`, `.daxBody()` modifiers
- **DRK color usage**: `UIColor(designSystemColor: .textPrimary)`
- **No hardcoded colors**: No hex values, RGB tuples, or named colors
- **No `.font()` modifiers** in SwiftUI (red flag for design system violations)
- **Semantic naming**: Colors described by purpose, not appearance

#### 🚨 Red flags in PRs:
```swift
// RED FLAGS - should be caught in review
.font(.title)                           // Should use .daxTitle2()
UIColor.black                          // Should use design system color
Color(red: 0.1, green: 0.2, blue: 0.3) // Should use semantic color
UIColor.systemBlue                     // Should use .accent or appropriate semantic color
```

#### ✅ Good patterns to approve:
```swift
// GOOD PATTERNS - approve these
Text("Title").daxTitle2()
UIFont.daxBody()
UIColor(designSystemColor: .textPrimary)
Color(designSystemColor: .background)
```

### Opportunistic Improvements

**Most of the iOS app currently does not use the design system**, so you're encouraged to:

1. **Opportunistically refactor** old code to use DRK when you encounter it
2. **Update hardcoded colors** to semantic colors when working in an area
3. **Replace system fonts** with DRK typography when touching text styling
4. **File follow-up tickets** for systematic cleanup when you notice patterns

#### Example: Opportunistic Refactoring

```swift
// BEFORE: Legacy hardcoded styling
class OldViewController: UIViewController {
    @IBOutlet weak var titleLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = UIColor.black
    }
}

// AFTER: Updated to use design system
class OldViewController: UIViewController {
    @IBOutlet weak var titleLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.font = UIFont.daxTitle2()
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
    }
}
```

## Components

### Current State: Minimal Component Library

We primarily use **system components** rather than custom ones, following iOS design guidelines. This is different from our Android app which has more custom components.

**Philosophy**: 
- **System components first** - leverages platform conventions
- **Custom components only when needed** - avoid overengineering
- **Reusable when patterns emerge** - extract when used in multiple places

### Existing Custom Components

#### Blue Button (Reusable)
Our primary custom component used across multiple screens:

```swift
// Current usage (likely not yet in DRK)
class DuckBlueButton: UIButton {
    override func awakeFromNib() {
        super.awakeFromNib()
        backgroundColor = UIColor(designSystemColor: .buttonPrimaryBackground)
        setTitleColor(UIColor(designSystemColor: .buttonPrimaryText), for: .normal)
        titleLabel?.font = UIFont.daxBody()
        layer.cornerRadius = 8
    }
}

// Future: Should be moved to DRK as reusable component
```

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

```swift
// Example: Converting blue button to DRK component
public struct DRKPrimaryButton: View {
    let title: String
    let action: () -> Void
    
    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Text(title)
                .daxBody()
                .foregroundColor(Color(designSystemColor: .buttonPrimaryText))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .background(Color(designSystemColor: .buttonPrimaryBackground))
        .cornerRadius(8)
    }
}
```

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

**In consuming app (iOS/macOS)**:

```swift
// Package.swift or Xcode package manager
.package(url: "https://github.com/duckduckgo/DesignResourcesKit", from: "1.2.0")
```

**Testing DRK changes**:
- Test in both **light and dark modes**
- Verify **dynamic type scaling** works correctly  
- Check **accessibility** with larger text sizes
- Test on **different device sizes**

### Local Development

**For iterating on DRK**:

```bash
# Clone both repositories
git clone https://github.com/duckduckgo/DesignResourcesKit
git clone https://github.com/duckduckgo/apple-browsers

# Use local package for development
# In Xcode: File > Add Package Dependencies > Add Local...
# Point to local DesignResourcesKit directory
```

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