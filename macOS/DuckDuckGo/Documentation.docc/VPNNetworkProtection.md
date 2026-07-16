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

The main app talks to the VPN agent over two transports: XPC as the primary channel, and a Unix Domain Socket fallback for commands that must still work when XPC is unavailable — notably uninstall and quit, which can run while the agent's XPC service is being torn down.

`NetworkProtectionIPCClient` abstracts the transport so call sites never choose between them; `NetworkProtectionIPCTunnelController` wraps a client conforming to it and exposes the `TunnelController` interface.

## VPN Agent as Login Item

The VPN agent (`DuckDuckGoVPN.app`) runs as a login item to maintain VPN connectivity independent of the main browser:

Running as a separate login item is what lets the VPN survive a browser crash and reconnect on login without the browser running. It also means the agent is already alive when the browser needs it, so connecting is just an IPC call rather than a process launch.

## System Extension

`SystemExtensionManager` wraps install, uninstall, and upgrade of the packet-tunnel system extension. Installation requires explicit user approval in System Settings — the app submits the request but cannot complete activation on its own, which is why onboarding has to hand off to System Settings and wait. Once activated, the VPN configuration (`NETunnelProviderManager`) is created and saved to system preferences.

## VPN Features

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
- ``NetworkProtectionControllerTabExtension`` — the VPN's hook into the Tab architecture. As a per-tab navigation responder it holds the tunnel controller and reports VPN-while-searching usage when a DuckDuckGo search loads with the tunnel connected.
- `DuckDuckGoVPNAppDelegate` — the VPN agent's delegate; owns IPC server setup and the tunnel controller lifecycle inside the agent process.

## Topics

### Entry Points

- ``TunnelControllerProvider``
- ``NetworkProtectionControllerTabExtension``

### Related

- <doc:TabManagement>
