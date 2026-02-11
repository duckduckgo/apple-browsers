This file configures AI coding assistants for the Apple monorepo.
Development rules are maintained in `.cursor/rules/` as the single source of truth.

**Personal preferences** (workflow, communication style, tool settings) belong in
your tool's user-level config, not here:
- Claude Code: `~/.claude/CLAUDE.md`
- Cursor: User-level settings

This repo-level file is for **team-shared conventions only**.

## Mandatory Rules

Detailed rules live in `.cursor/rules/`. Read from the list below when the request is relevant.

| File | Covers |
|------|--------|
| `general.mdc` | Project overview, architecture summary, rule index, quick-start checklists |
| `code-style.mdc` | Full Swift style guide: naming, formatting, closures, optionals, memory management |
| `anti-patterns.mdc` | What NOT to do: singletons, async mistakes, SwiftUI pitfalls, testing mistakes |
| `user-defaults-storage.mdc` | Storing settings or preferences via `KeyValueStore` |
| `pixels.mdc` | Defining, naming, or firing pixel telemetry events |

## Contextual Rules

Only consult this list of rules if explicitly asked by the user to check "cursor rules".

### Pixels & Analytics

| File | Covers | Read when... |
|------|--------|--------------|
| `analytics-patterns.mdc` | Structured pixel event definitions and fire patterns | Implementing structured analytics or pixel event patterns |
| `pixel-definitions.mdc` | Pixel registry JSON5 definitions and documentation | Defining or documenting pixel events in the registry |
| `instrumentation-facades.mdc` | Abstracting pixel/event instrumentation behind domain protocols | Creating instrumentation wrappers or simplifying verbose pixel code |

### Storage & Preferences

| File | Covers | Read when... |
|------|--------|--------------|
| `securevault-guidelines.mdc` | SecureVault (GRDB + SQLCipher) for encrypted data storage | Working with SecureVault, encrypted storage, or GRDB database code |

### Feature Flags & Experiments

| File | Covers | Read when... |
|------|--------|--------------|
| `feature-flags.mdc` | Type-safe feature flag patterns and protocols | Working with or checking feature flags |
| `feature-flags-addition.mdc` | Step-by-step pattern for adding new feature flags to iOS/macOS | Adding a new feature flag |
| `abn-experiment-framework.mdc` | A/B/N experiment framework for multi-variant testing | Setting up or modifying A/B/N experiments |

### Architecture & Project Structure

| File | Covers | Read when... |
|------|--------|--------------|
| `architecture.mdc` | Architecture guidelines: MVVM, multi-platform monorepo patterns | Making architectural decisions or understanding overall app structure |
| `project-structure.mdc` | Workspace layout, directory organization, target structure | Navigating the repo, creating new files/modules, or understanding project layout |
| `ios-architecture.mdc` | iOS-specific architecture: dependency injection, AppDependencies | Working on iOS app-level code, DI patterns, or AppDependencyProvider |
| `app-lifecycle-state-machine.mdc` | App lifecycle state machine (replaces traditional AppDelegate patterns) | Modifying app launch, background, or foreground lifecycle behavior |
| `shared-packages.mdc` | Shared packages structure, development, and cross-platform guidelines | Creating or modifying packages in SharedPackages/ |
| `browserserviceskit-integration.mdc` | BrowserServicesKit core library: privacy, protection, shared services | Integrating with or modifying BrowserServicesKit modules |
| `import-hygiene.mdc` | Import statement hygiene and preview-only import scoping | Cleaning up imports or scoping preview-only dependencies |

### macOS-Specific

| File | Covers | Read when... |
|------|--------|--------------|
| `macos-window-management.mdc` | WindowsManager, AppKit window patterns, tab management | Working on macOS window creation, tab management, or AppKit views |
| `macos-system-integration.mdc` | Background agents, services, system-level macOS integration | Working on macOS background services, agents, or system extensions |
| `macos-singletons-removal.mdc` | Pattern for removing .shared singletons via DI | Refactoring macOS singletons or adding new dependencies |

### SwiftUI & Design System

| File | Covers | Read when... |
|------|--------|--------------|
| `swiftui-style.mdc` | SwiftUI style guide with Design System integration | Building or refactoring SwiftUI views |
| `swiftui-advanced.mdc` | Advanced SwiftUI: ViewModifier composition, custom layouts | Implementing advanced SwiftUI patterns (custom modifiers, animations, layout) |
| `design-system-designresourceskit.mdc` | iOS design system via DesignResourcesKit (DRK) tokens | Using design tokens, colors, or typography from the design system |

### Testing

| File | Covers | Read when... |
|------|--------|--------------|
| `testing.mdc` | Unit testing guidelines, test structure, mocking patterns | Writing or modifying unit tests |
| `ui-testing.mdc` | macOS UI testing: UITestCase base class, workflows, assertions | Writing or modifying UI/integration tests for macOS |
| `maestro-device-selection.mdc` | Maestro test device selection (iPhone vs iPad simulators) | Configuring or running Maestro tests |

### Privacy & Browser Core

| File | Covers | Read when... |
|------|--------|--------------|
| `privacy-security.mdc` | Privacy by design and secure data handling principles | Making decisions about data handling or security |
| `ios-tracker-blocking-implementation.mdc` | iOS tracker blocking: content blockers + JS injection dual strategy | Working on content blocking, tracker protection, or privacy rules |
| `webkit-browser.mdc` | WebKit/WKWebView configuration, navigation, content rules | Working with WKWebView, web content, or browser navigation |
| `duckplayer.mdc` | DuckPlayer architecture: presenter pattern, video playback | Working on DuckPlayer features or video playback |
| `duckplayer-userscript-integration.mdc` | DuckPlayer UserScript: native-to-web bridging for YouTube/player | Modifying DuckPlayer UserScript communication or JS bridge |

### Subscription & Networking

| File | Covers | Read when... |
|------|--------|--------------|
| `subscription-architecture.mdc` | Subscription system: VPN, PIR, ITR, AI Chat, cross-platform activation | Working on subscription, purchase flows, or premium features |
| `network-quality-scoring.mdc` | NetworkQualityMonitor scoring algorithm (latency, bandwidth, DNS) | Working on network quality scoring or monitor algorithms |
| `network-quality-test-config.mdc` | NetworkQualityMonitor test parameters and phase configuration | Configuring network quality test parameters |
| `network-quality-testing.mdc` | NetworkQualityMonitor testing framework and architecture | Writing tests for or modifying NetworkQualityMonitor |
| `network-quality-variance-scoring.mdc` | Network quality variance scoring using Coefficient of Variation | Working on network quality variance display or scoring |

### Performance & Logging

| File | Covers | Read when... |
|------|--------|--------------|
| `performance-optimization.mdc` | Memory management, retain cycles, performance patterns | Optimizing performance or fixing memory issues |
| `logging-guidelines.mdc` | Apple Unified Logging System usage, privacy-conscious telemetry | Adding or modifying logging/telemetry capture |

### Development Workflow

| File | Covers | Read when... |
|------|--------|--------------|
| `development-commands.mdc` | Build instructions and commands for iOS/macOS development | Building the project or running development commands |
| `branch-naming-conventions.mdc` | Branch naming conventions and GitHub Flow | Creating branches or following git workflow |
| `pull-request.mdc` | PR creation guidelines, required info, Asana integration | Creating or reviewing pull requests |
