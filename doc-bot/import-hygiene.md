---
alwaysApply: true
title: "Import Hygiene & Preview-Only Imports"
description: "Rules to avoid unrequested import churn and scope SwiftUI to Debug previews only."
keywords: ["imports", "SwiftUI", "preview", "#Preview", "Common", "AppKit", "lint", "module"]
---

# Import Hygiene & Preview-Only Imports

## Purpose
Prevent accidental or unrequested import churn that causes build/lint issues and diffs unrelated to the task. Ensure SwiftUI is only imported where required (e.g., #Preview blocks) and avoid touching existing imports unless strictly necessary.

## Rules (Always Apply)

1. Do not change imports unless:
   - A new symbol is introduced that the compiler cannot resolve without the import
   - An existing import is provably unused and removal is part of the explicit task scope
   - The change resolves a red compiler error you introduced in this edit

2. Keep platform/framework imports minimal and local:
   - Prefer `import AppKit` for macOS UI code
   - Prefer `import UIKit` for iOS UI code
   - Do not add `import SwiftUI` to AppKit/UIKit view controllers unless they embed SwiftUI.

3. Scope SwiftUI to previews:
   - Only import `SwiftUI` inside `#if DEBUG` blocks for `#Preview` declarations
   - Example:
     ```swift
     #if DEBUG
     import SwiftUI
     @available(macOS 14.0, *)
     #Preview { MyViewController() }
     #endif
     ```

4. Keep Shared Modules stable:
   - Do not remove `import Common` or other project modules unless a dedicated cleanup task
   - If a module is required elsewhere in the file, do not move or duplicate it

5. Lint & Build first, then adjust:
   - If a file shows missing-types errors after your edits (e.g., `Cannot find type 'FireproofDomains'`), prefer adding the specific missing import required for those existing symbols
   - Avoid speculative imports

6. No import reordering for style-only reasons unless the repository enforces it via formatter

## Rationale
- Unnecessary import edits generate churn and can break platform- or target-specific build settings
- Scoping SwiftUI to previews avoids accidental framework inclusion and linking in non-preview code paths

## Examples

- CORRECT (AppKit-only controller):
  ```swift
  import AppKit
  import Common
  final class MyViewController: NSViewController { /* ... */ }
  ```

- CORRECT (preview-only SwiftUI):
  ```swift
  import AppKit
  import Common
  #if DEBUG
  import SwiftUI
  @available(macOS 14.0, *)
  #Preview { MyViewController() }
  #endif
  ```

- AVOID:
  ```swift
  import AppKit
  import SwiftUI  // Not needed in production path
  import Common
  ```

## Enforcement Guidance
- During PR review, reject changes that add/remove imports without a clear necessity
- Prefer comments in code review over automated reordering unless enforced by tooling