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
