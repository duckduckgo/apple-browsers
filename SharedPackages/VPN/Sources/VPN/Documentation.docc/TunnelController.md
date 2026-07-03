# ``TunnelController``

Control VPN tunnel connections through a unified protocol interface.

## Overview

The ``TunnelController`` protocol isolates VPN control from the Network Extension and IPC machinery behind it. Call sites — and tests — start, stop, and command the tunnel through one interface without knowing whether the real controller lives in-process, in the VPN agent across an IPC boundary, or is a mock.

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

- ``TunnelSessionProvider``

### Commands

- ``VPNCommand``

### Status

- ``ConnectionStatus``
