# DuckWireGuard

An experimental, standalone Swift implementation of the WireGuard client protocol.
The supported platforms are macOS 12.3 or later and iOS 15 or later. The Developer-ID
macOS system extension and iOS packet-tunnel extension use the native engine in
Debug builds through the separate `VPNDebug` adapter.

## Dependencies

There are no external Swift package dependencies or Go components.

| Requirement | Implementation |
| --- | --- |
| X25519 key agreement and randomness | Apple CryptoKit `Curve25519.KeyAgreement` |
| ChaCha20-Poly1305 authenticated encryption | Apple CryptoKit `ChaChaPoly` |
| BLAKE2s hashing, keyed MAC, HMAC, and WireGuard KDF | Internal Swift implementation of RFC 7693 and the WireGuard construction |
| XChaCha20-Poly1305 cookie decryption | Internal HChaCha20 subkey derivation followed by CryptoKit `ChaChaPoly` |
| UDP for the command-line probe | Apple Network framework `NWConnection` |
| IP packet I/O in the debug adapter | Apple NetworkExtension `NEPacketTunnelFlow.readPackets` / `writePackets` |

The protocol engine takes and returns `Data`. It owns neither sockets nor a tunnel
interface. It can therefore be tested without NetworkExtension entitlements.

The debug adapter preserves automatic or explicitly configured MTU settings.
It reads the effective tunnel-interface MTU after settings and path changes and caches
that value for padding. It does not query the interface for each packet. If the effective
MTU is unavailable, the adapter adds no padding to automatically sized packets; it
preserves their IP payload and WireGuard authentication. Explicit MTU limits still
bound padding. Each prepared packet captures its padding policy with its nonce.

Using Apple's packet-flow APIs for a real tunnel will require a packet-tunnel
extension, its entitlements, network settings, and a packet pump; those are outside
this initial package.

The internal cryptographic helpers are experimental and have not been independently
audited. This package is for development and interoperability testing.

## API

`WireGuardPeer` represents one configured remote peer. The caller serializes access
to this reference type and owns the UDP endpoint, scheduling, and packet routing.
Copies of a reference share session counters, avoiding nonce reuse from value copies.
Keys are 32-byte `Data` values; `generatePrivateKey()` creates a local private key.

```swift
import DuckWireGuard

let peer = try WireGuardPeer(
    privateKey: localPrivateKey,
    peerPublicKey: serverPublicKey,
    presharedKey: optionalPresharedKey
)

// Send this UDP payload to the configured server.
let initiation = try peer.initiateHandshake()

// Feed UDP datagrams from that server into the engine.
switch try peer.receive(receivedDatagram) {
case .handshakeResponse(let response):
    // Send promptly. Responder keys become sendable only after authenticated confirmation.
    // Send `response` over UDP.
    break
case .handshakeComplete:
    // Send promptly: confirms the new keys to the responder.
    let confirmation = try peer.keepalive()
    // Send `confirmation` over UDP.
case .cookieReceived:
    // The cookie is cached. Wait for the normal retry timer before initiating again.
    break
case .packet(let ipPacket):
    // Deliver the unpadded IP packet through Apple's packet-flow write API.
    break
case .keepalive:
    break
}

// Encrypt each raw IP packet read through Apple's packet-flow read API.
let outgoingDatagram = try peer.encrypt(outgoingIPPacket)
```

The example shows the protocol boundary; application-specific send and packet-flow
operations are intentionally supplied by the caller.

The implementation supports initiating and responding to the Noise IKpsk2 handshake,
authenticating responses, cookie challenges, optional pre-shared keys, encrypted
IPv4/IPv6 packets, empty keepalives, and a receive replay window. `isEstablished`
reports whether a usable session exists. `needsRekey` tells the caller to initiate
a new handshake; key lifetime and counter limits also reject expired sessions.
The previous receive session remains available during a rekey overlap. A responder stages
its next keypair until an authenticated transport datagram confirms it. Check
`handshakeGeneration` around `receive` to observe confirmation without losing its first
IP packet. `isAwaitingConfirmation` distinguishes staged responder keys, and
`currentSessionIsInitiator` supports the role-specific rekey timers. `reset()` clears
handshake keys, sessions and cookies while retaining the authenticated initiation
timestamp watermark, preventing handshake replays after a transport/key reset.

The core leaves retry/keepalive/rekey timers, endpoint management, IP policy, routing,
DNS, and packet I/O to its caller. The debug adapter supplies those integration
responsibilities. The core accepts authenticated initiations from its configured peer.
Outgoing initiations are rate limited to one every five seconds. Incoming initiations
have an independent pre-DH budget of eight attempts, replenished at 50 attempts per
second after a valid MAC1; rejected authentication still consumes that budget.
Authenticated timestamp replay and accepted-initiation rate checks remain separate.
Its continuous monotonic age clock advances through system sleep.

## Debug integration

The separate `VPNDebug` product implements the existing adapter protocol using
`NEPacketTunnelFlow` and `NWConnection`. The adapter reuses DDG's existing
registration, keys, selected endpoint, and generated routes/DNS. One background queue
owns mutable protocol state to keep nonce allocation, replay checks, and key changes
ordered. Encryption workers use immutable snapshots so they can run in parallel
without sharing mutable session state.

The native backend is enabled for the Developer-ID system extension's Debug
configuration. Build and launch normally:

```sh
~/Developer/ddg-ai-scripts/run macos "macOS Browser"
```

The Debug app's `DEPLOYMENT_LOCATION` setting is enabled for VPN testing, so the
build installs and launches `/Applications/DEBUG/DuckDuckGo.app`.

Set `DUCK_WIREGUARD_DEBUG_FLAGS=` when building to test the Go backend instead.
The setting is consumed by the macOS system extension and iOS packet-tunnel target's
Debug configurations. Both require `DEBUG` and `DUCK_WIREGUARD_POC`; macOS also
requires `NETP_SYSTEM_EXTENSION`. CI, Release, Review, Alpha, the App Store extension,
and non-Debug iOS configurations retain the existing Go-backed adapter. The Go
dependency is retained. `VPNDebug` implementation code is excluded in release builds,
and the existing `VPN` target has no dependency on the native engine.

The iOS packet-tunnel target's Debug configuration also enables `DUCK_WIREGUARD_POC`.
Build and launch on a paired iPhone with:

```sh
DDG_RUN_DEVICE=<device-identifier> ~/Developer/ddg-ai-scripts/run ios "iOS Browser"
```

To rebuild and reinstall the existing Go adapter instead, append
`DUCK_WIREGUARD_DEBUG_FLAGS=` to that command.

The iOS adapter limits queued packet payloads to 8 MiB; macOS uses 32 MiB. Device
installation requires the existing development signing profiles. Native interface
names are available on iOS 18 or macOS 15 and later; older versions use the existing
fallback when the name is unavailable.

When available, the provider's native virtual-interface name supports the existing
connection tester. If unavailable, the existing startup error handling continues
without that tester. Live DDG interoperability, browsing, and routing under the
signed provider's actual VPN settings require a local debug run; unit tests and
the standalone UDP probe do not verify them.

## macOS probe

The `duck-wireguard-probe` executable completes an authenticated exchange with an existing
WireGuard server. It does not create a tunnel, change routes, or test browsing.
The server must already have the public
key corresponding to the configured local private key in its peer configuration.

Create a private JSON file outside the repository, using base64-encoded keys:

```json
{
  "host": "your-test-server.example",
  "port": 51820,
  "privateKey": "<base64 local private key>",
  "peerPublicKey": "<base64 server public key>"
}
```

Add `"presharedKey": "<base64 pre-shared key>"` when required by the server.
Keep this file private and out of version control.

Build and test from the worktree:

```sh
~/Developer/ddg-ai-scripts/build macos DuckWireGuard -derivedDataPath /tmp/duck-wireguard-derived
~/Developer/ddg-ai-scripts/test macos DuckWireGuard -derivedDataPath /tmp/duck-wireguard-derived
```

Run the built executable:

```sh
/tmp/duck-wireguard-derived/Build/Products/Debug/duck-wireguard-probe /path/to/private-config.json
```

The probe retries after five seconds plus jitter, caches cookie challenges, and
times out after ten seconds. As initiator, it succeeds after authenticating a handshake
response and submitting an encrypted keepalive to the OS; that does not prove remote
receipt. As responder, it succeeds after receiving authenticated transport that confirms
the new keys. Live server interoperability remains unverified until the probe is run
with test-server credentials.

## Protocol references and validation

- [WireGuard protocol and cryptography](https://www.wireguard.com/protocol/)
- [WireGuard technical whitepaper](https://www.wireguard.com/papers/wireguard.pdf)
- [WireGuard userspace configuration interface](https://www.wireguard.com/xplatform/)
- [RFC 7693: BLAKE2](https://www.rfc-editor.org/rfc/rfc7693)
- [XChaCha20 and HChaCha20 construction](https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03)
- [Apple CryptoKit](https://developer.apple.com/documentation/cryptokit)
- [Apple packet-flow API](https://developer.apple.com/documentation/networkextension/nepackettunnelflow)

The typed Swift API does not implement the `wg` command's userspace control socket
or its text configuration protocol. Those are separate from WireGuard's wire format.

Tests cover independent cryptographic vectors, deterministic handshake and transport
fixtures, malformed packets, authentication failures, replay rejection, and session
limits. The fixture generator uses Python's standard-library BLAKE2s/HMAC and
OpenSSL 3's X25519/ChaCha20-Poly1305, independently of the Swift implementation.
Python and OpenSSL are only needed to regenerate those fixtures, not to build or
run the package. See `Tests/DuckWireGuardTests/Fixtures` for the generator.

The native probe has also completed a localhost UDP handshake against an independent
Python/OpenSSL responder, which authenticated the initiation and decrypted its
encrypted keepalive. This verifies the local UDP exchange; compatibility with a
running DDG or reference WireGuard server is still unverified.
