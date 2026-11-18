# DuckWireGuard

An experimental, standalone Swift implementation of the WireGuard client protocol.
The supported platforms are macOS 12.3 or later and iOS 15 or later.

## Dependencies

There are no external Swift package dependencies or Go components.

| Requirement | Implementation |
| --- | --- |
| X25519 key agreement and randomness | Apple CryptoKit `Curve25519.KeyAgreement` |
| ChaCha20-Poly1305 authenticated encryption | Apple CryptoKit `ChaChaPoly` |
| BLAKE2s hashing, keyed MAC, HMAC, and WireGuard KDF | Internal Swift implementation of RFC 7693 and the WireGuard construction |
| XChaCha20-Poly1305 cookie decryption | Internal HChaCha20 subkey derivation followed by CryptoKit `ChaChaPoly` |
| UDP for the command-line probe | Apple Network framework `NWConnection` |

The protocol engine takes and returns `Data`. It owns neither sockets nor a tunnel
interface. It can therefore be tested without NetworkExtension entitlements.

Using Apple's packet-flow APIs for a real tunnel will require a packet-tunnel
extension, its entitlements, network settings, and a packet pump; those are outside
this initial package.

## API

`WireGuardPeer` represents one configured remote peer and stays alive across rekeys.
Each transport keypair has its own nonce counter and replay history. The caller serializes
access to the peer and owns the UDP endpoint, scheduling, and packet routing.
Copies of a reference share counters, avoiding nonce reuse from value copies.
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
    // Deliver the unpadded IP packet to the caller's packet interface.
    break
case .keepalive:
    break
}

// Encrypt each outgoing raw IP packet.
let outgoingDatagram = try peer.encrypt(outgoingIPPacket)
```

The example shows the protocol boundary; application-specific send and packet I/O
operations are intentionally supplied by the caller.

The implementation supports initiating and responding to the Noise IKpsk2 handshake,
authenticating responses, cookie challenges, optional pre-shared keys, encrypted
IPv4/IPv6 packets, empty keepalives, and a receive replay window. `isEstablished`
reports whether a usable session exists. `needsRekey` tells the caller to initiate
a new handshake; key lifetime and counter limits also reject expired sessions.
The previous receive keypair remains available during a rekey overlap. A responder stages
its next keypair until an authenticated transport datagram confirms it. Check
`handshakeGeneration` around `receive` to observe confirmation without losing its first
IP packet. `isAwaitingConfirmation` distinguishes staged responder keys. `reset()` clears
handshake keys, transport keypairs and cookies while retaining the authenticated initiation
timestamp watermark, preventing handshake replays after a transport/key reset.

The core leaves retry/keepalive/rekey timers, endpoint management, IP policy, routing,
DNS, and packet I/O to its caller. The core accepts authenticated initiations from
its configured peer.
Outgoing initiations are rate limited to one every five seconds. Incoming initiations
and responses share a pre-DH budget of eight attempts, replenished at 50 attempts per
second. This is a local defensive policy; attempts with a valid MAC1 consume the budget
even when subsequent authentication fails.
Authenticated timestamp replay and accepted-initiation rate checks remain separate.
Its continuous monotonic age clock advances through system sleep.

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
deployed WireGuard server is not verified by this loopback exchange.
