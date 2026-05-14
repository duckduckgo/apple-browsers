# Tunnel Controller

Control VPN tunnel connections through a unified protocol interface.

## Overview

The ``TunnelController`` protocol provides a platform-agnostic interface for controlling VPN tunnel connections. It abstracts the underlying Network Extension framework details, allowing applications to start, stop, and manage VPN tunnels consistently across different implementations.

## Core Protocol

The ``TunnelController`` protocol defines the essential operations for VPN tunnel management:

```swift
// Start VPN
await tunnelController.start()

// Stop VPN
await tunnelController.stop()

// Send commands
try await tunnelController.command(.expireRegistrationKey)

// Check connection status
let isConnected = await tunnelController.isConnected
```

### Available Commands

The ``VPNCommand`` enum defines commands that can be sent to the tunnel:

- `.expireRegistrationKey` — Expire the current registration key
- `.removeSystemExtension` — Remove the system extension
- `.removeVPNConfiguration` — Remove the VPN configuration
- `.restartAdapter` — Restart the VPN adapter
- `.sendTestNotification` — Send a test notification
- `.uninstallVPN(showNotification:)` — Uninstall the VPN, optionally surfacing a notification
- `.simulateSubscriptionExpirationInTunnel` — Test subscription-expiration handling in the tunnel
- `.quitAgent` — Quit the VPN agent
- `.createLogSnapshot` — Snapshot logs for debugging
- `.triggerLeakCheck` — Run a leak check against the active tunnel

## Connection Status

The ``ConnectionStatus`` enum represents the current state of the VPN connection:

- `.notConfigured` - VPN is not configured
- `.disconnected` - VPN is configured but not connected
- `.connecting` - VPN is establishing connection
- `.connected(connectedDate:)` - VPN is connected (includes connection timestamp)
- `.reasserting` - VPN is re-establishing connection
- `.disconnecting` - VPN is disconnecting
- `.snoozing` - VPN is temporarily paused

## Implementations

Different platforms and contexts provide their own implementations of ``TunnelController``:

- **iOS/macOS App**: Uses `NETunnelProviderManager` to manage system-level VPN
- **IPC Client**: Communicates with VPN agent via XPC or Unix Domain Sockets
- **Testing**: Mock implementations for unit and UI testing

## Topics

### Protocols

- ``TunnelController``
- ``TunnelSessionProvider``

### Commands

- ``VPNCommand``

### Status

- ``ConnectionStatus``

## See Also

- `PacketTunnelProvider` - The system extension that handles actual VPN traffic
- `VPNSettings` - Configuration for VPN tunnel behavior
