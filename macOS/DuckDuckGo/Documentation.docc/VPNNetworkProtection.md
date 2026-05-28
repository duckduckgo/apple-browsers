# VPN

macOS VPN architecture using system extensions, IPC communication, and the VPN agent.

## Overview

The macOS app implements VPN using Apple's Network Extension framework with a system extension architecture. The implementation separates concerns across multiple processes: the main browser app, a dedicated VPN agent, and a system extension that handles network traffic.

For the VPN package API documentation, see `TunnelController` in the VPN package.

## Architecture

The VPN runs across three processes: the main browser (`DuckDuckGo.app`), a dedicated VPN agent (`DuckDuckGoVPN.app`), and a packet-tunnel system extension. The browser talks to the agent over IPC (XPC primary, Unix Domain Sockets fallback). The agent talks to the system extension via Network Extension provider messages. The extension does the actual packet forwarding.

### Key Components

- `NetworkProtectionIPCClient` — protocol abstracting the IPC transport the main app uses to talk to the VPN agent. The concrete implementation is `VPNControllerXPCClient`.

- `NetworkProtectionIPCTunnelController` — the `TunnelController`-conforming class the main app actually uses. Wraps a `NetworkProtectionIPCClient` so callers can drive the tunnel without knowing where it lives.

- `NetworkProtectionTunnelController` — the underlying tunnel controller running inside the VPN agent. Manages `NETunnelProviderManager` and the system extension lifecycle.

- `DuckDuckGoVPN.app` — standalone VPN agent application. Runs as a login item for persistent VPN and hosts the IPC servers (XPC + UDS).

- `PacketTunnelProvider` — system extension that routes network traffic. WireGuard-based.

- `SystemExtensionManager` — wrapper around macOS `SystemExtensions` that handles installation, uninstallation, and upgrades.

## IPC Communication

The main app communicates with the VPN agent through two IPC mechanisms:

### XPC (Primary)

- Type-safe protocols
- Automatic process management
- macOS standard for inter-process communication
- Used for most VPN control operations

### Unix Domain Sockets (Fallback)

- Simple message passing
- Works when XPC connection unavailable
- Used for specific commands (uninstall, quit)
- Shared file system location

`NetworkProtectionIPCClient` abstracts the IPC transport; `NetworkProtectionIPCTunnelController` wraps a client conforming to it and exposes the `TunnelController` interface, so call sites in the main app don't need to know whether XPC or UDS is in use.

## VPN Agent as Login Item

The VPN agent (`DuckDuckGoVPN.app`) runs as a login item to maintain VPN connectivity independent of the main browser:

**Benefits:**
- VPN remains active if browser crashes
- Faster VPN startup (agent already running)
- Better system integration
- Independent lifecycle management

**Lifecycle:**
1. Browser registers agent as login item
2. Agent launches on login (or on-demand)
3. Agent initializes tunnel controller
4. Agent starts IPC servers (XPC + UDS)
5. Browser connects via IPC when needed
6. Agent persists until explicitly quit

## System Extension

The system extension provides the actual VPN functionality:

### Installation

1. Check if extension is already installed
2. Submit install request via `SystemExtensionManager`
3. User approves in System Settings
4. Extension activated
5. Create VPN configuration (`NETunnelProviderManager`)
6. Save configuration to system preferences

### Management

- Extensions auto-update with app updates
- Uninstall via `SystemExtensionManager.deactivate()`
- Status monitoring via `SystemExtensions` framework

## VPN Features

### Site-Specific Exclusions

The `NetworkProtectionControllerTabExtension` allows excluding specific domains from VPN routing. Traffic to excluded domains bypasses the VPN tunnel.

### Connection Monitoring

- `NetworkProtectionStatusReporter` — publishes connection status changes
- `NetworkProtectionLatencyMonitor` — tracks connection latency
- `NetworkProtectionConnectionBandwidthAnalyzer` — monitors data usage
- `NetworkProtectionTunnelFailureMonitor` — detects and reports failures

### State Management

VPN state and preferences are split across two stores:
- `VPNAppState` — app-side state in shared `UserDefaults` (`isUsingSystemExtension`, `dontAskAgainExclusionSuggestion`).
- `VPNSettings` — the broader settings store shared across processes, including `connectOnLogin`, selected location/server, DNS preferences, and exclusions.

Both back onto shared defaults so values are synchronized across the main app, the VPN agent, and the system extension, and persist across launches.

## Entry Points

- ``TunnelControllerProvider`` — vends the app's `NetworkProtectionIPCTunnelController` instance; the main app's entry point for VPN control.
- ``NetworkProtectionControllerTabExtension`` — per-tab VPN exclusion management, integrated into the Tab architecture.
- `DuckDuckGoVPNAppDelegate` — the VPN agent's delegate; owns IPC server setup and the tunnel controller lifecycle inside the agent process.

## Common Tasks

### Excluding a Domain

Use the tab extension to exclude specific sites from VPN routing. See `NetworkProtectionControllerTabExtension` for implementation.

## Topics

### Entry Points

- ``TunnelControllerProvider``
- ``NetworkProtectionControllerTabExtension``

### Related

- <doc:TabManagement>
