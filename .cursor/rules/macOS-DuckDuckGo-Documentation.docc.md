---
title: macOS App Documentation Rules
description: File-specific rules for macOS/DuckDuckGo/Documentation.docc/** - app-level documentation guidelines
keywords: [documentation, macOS, app docs, integration, DocC]
alwaysApply: false
filePath: "macOS/DuckDuckGo/Documentation.docc/**"
---

# macOS App Documentation Rules

**Applies to**: `macOS/DuckDuckGo/Documentation.docc/**`

## Focus

This directory contains **app-level** documentation for the macOS browser:
- How the macOS app integrates with packages
- macOS-specific architecture patterns
- Platform-specific implementations (system extensions, IPC, etc.)
- Feature coordination within the app

## What Belongs Here

✅ **DO document**:
- macOS app architecture (Tab system, MainWindow, Coordinators)
- Integration with packages (how macOS uses TunnelController, UserScript, etc.)
- Platform-specific features (system extensions, VPN agent, menu bar)
- UI components (NavigationBar, Preferences, MenuSystem)
- macOS-specific patterns and best practices

❌ **DON'T document**:
- Package protocol APIs (those go in package docs)
- Protocol definitions (unless app-specific like BookmarkManager)
- Generic patterns that iOS also uses (those go in package docs)

## Code Guidelines

**Minimize inline code** - Keep total to ~10-15 blocks across ALL articles:
- Prefer file references: "See `ClassName.swift`"
- Prefer architecture diagrams
- Link to package docs for API examples
- Only show code for truly unique app patterns

## Cross-Referencing

Always link to package docs for API details:

```markdown
For the TunnelController API, see `TunnelController` in the VPN package.
See <doc:UserScript> in BrowserServicesKit for protocol documentation.
```

## Article Structure Template

```markdown
# Feature Name

Brief overview of the macOS app feature.

## Overview

What this feature does in the context of the macOS app.

For the [Package] API, see `ProtocolName` in the [Package] package.

## Architecture

macOS-specific architecture:
- How components are organized
- Process boundaries (if any)
- Integration points

## Key Components

- Component descriptions with file paths
- macOS-specific implementations
- File references, not code blocks

## Common Tasks

How to work with this feature in the macOS app:
- Brief procedural descriptions
- File references
- Link to package docs for API usage

## Related Topics

- Links to other app docs
- Links to package docs
- Links to related features
```

## Examples

See existing articles:
- `VPNNetworkProtection.md` - Good example of app integration docs
- `UserScripts.md` - Good example of linking to package docs
- `TabManagement.md` - Good example of app architecture docs
