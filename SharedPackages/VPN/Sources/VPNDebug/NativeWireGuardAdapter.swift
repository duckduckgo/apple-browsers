//
//  NativeWireGuardAdapter.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if DEBUG && (os(macOS) || os(iOS))
import DuckWireGuard
import Darwin
import Foundation
import Network
import NetworkExtension
import VPN

/// Experimental packet-flow adapter. The extension explicitly opts in to this backend.
/// The provider is attached after its initializer has completed; this object never owns it.
public final class NativeWireGuardAdapter: WireGuardAdapterProtocol {
    struct IO {
        var applySettings: (NEPacketTunnelNetworkSettings?, @escaping (Swift.Error?) -> Void) -> Void
        var readPackets: (@escaping ([Data], [NSNumber]) -> Void) -> Void
        var writePackets: ([Data], [NSNumber]) -> Bool
        var setReasserting: (Bool) -> Void
        var cancelTunnel: (Swift.Error) -> Void
        var interfaceMTU: (() -> Int?)?
    }

    private enum State { case stopped, starting, running, snoozing }

    private enum Failure: LocalizedError {
        case providerMissing, unsupportedConfiguration, operationCancelled, startupTimedOut, settingsTimedOut, settingsUpdateInProgress

        var errorDescription: String? {
            switch self {
            case .providerMissing: return "The native WireGuard adapter has no packet-tunnel provider."
            case .unsupportedConfiguration: return "The native WireGuard MVP requires exactly one peer with a UDP endpoint."
            case .operationCancelled: return "The native WireGuard operation was cancelled."
            case .startupTimedOut: return "Native WireGuard network setup did not complete within 15 seconds."
            case .settingsTimedOut: return "Native WireGuard network settings did not complete before the deadline."
            case .settingsUpdateInProgress: return "A native WireGuard network settings update is already in progress."
            }
        }
    }

    let queue = DispatchQueue(label: "com.duckduckgo.vpn.native-wireguard")
    private weak var attachedProvider: NEPacketTunnelProvider?
    private let makeTransport: (Endpoint) -> NativeWireGuardTransport
    private let makePeer: (TunnelConfiguration) throws -> WireGuardPeer
    private let monotonicTime: () -> TimeInterval
    private let epochTime: () -> TimeInterval
    private let retryJitter: () -> TimeInterval
    private let automaticTimers: Bool
    private let log: (String) -> Void
    private var io: IO?
    private var state: State = .stopped
    private var configuration: TunnelConfiguration?
    private var peer: WireGuardPeer?
    private var transport: NativeWireGuardTransport?
    private var transportReady = false
    private var networkMonitor: NWPathMonitor?
    private var timer: DispatchSourceTimer?
    private var timerUpdateQueued = false
    private var timerEpoch: UInt64 = 0
    private var armedTimerDeadline: TimeInterval?
    // The injected scheduler and its callback run on the owner queue, like DispatchSourceTimer.
    var scheduleProtocolTimer: ((TimeInterval?, @escaping () -> Void) -> Void)? {
        didSet { timerEpoch &+= 1; armedTimerDeadline = nil; requestTimerUpdate() }
    }
    private var receivingRekeyRequested = false
    private var generation: UInt64 = 0
    private var transportGeneration: UInt64 = 0
    private var packetReadID: UUID?
    private var pendingCompletion: ((WireGuardAdapterError?) -> Void)?
    private var operationStarted: TimeInterval = 0
    private var settingsUpdate: SettingsUpdate?

    private struct SettingsUpdate {
        let id = UUID()
        let configuration: TunnelConfiguration
        let peer: WireGuardPeer
        let previousSettings: NEPacketTunnelNetworkSettings
        let reassert: Bool
        let completion: (WireGuardAdapterError?) -> Void
        var deadline: TimeInterval
        var failure: WireGuardAdapterError?
    }
    private var handshakeTransmissions = 0
    private var handshakeRetryExhausted = false
    private var handshakeCleanupDeadline: TimeInterval?
    private var nextHandshake: TimeInterval?
    private var nextReconnect: TimeInterval?
    private var lastActivity: TimeInterval = 0
    private var unansweredPacketDeadline: TimeInterval?
    private var passiveKeepalive: TimeInterval?
    private var lastHandshake: TimeInterval = 0
    private var lastKeyExchange: TimeInterval?
    private var receivedBytes: UInt64 = 0
    private var sentBytes: UInt64 = 0
    private var inFlightSends = 0
    private var inFlightPacketSends = 0
    private var pendingKeepalive = false
    private var keepaliveInFlight = false
    private var pendingInitiation: Data?
    private var pendingResponse: Data?
    private var pendingPackets = PacketQueue<Data>()
    private var encryptionGroups = PacketQueue<EncryptionGroup>()
    private let encryptionWorkers = EncryptionWorkers(count: min(4, ProcessInfo.processInfo.activeProcessorCount))
    private var activeEncryptionJobs = 0
    private var encryptionGeneration: UInt64 = 0
    private let maximumQueuedBytes: Int
    private(set) var queuedPacketBytes = 0
    private(set) var queuedPacketCount = 0
    private(set) var droppedPacketCount: UInt64 = 0
    // Injectable scheduling lets tests hold and reorder groups without sleeps.
    var scheduleEncryption: ((@escaping () -> Void) -> Void)?

    private final class EncryptionGroup {
        let generation: UInt64
        let packets: [WireGuardPeer.PreparedPacket]
        var datagrams: [Data?]?
        var nextIndex = 0

        init(packets: [WireGuardPeer.PreparedPacket], generation: UInt64) {
            self.packets = packets
            self.generation = generation
        }
    }

    /// Keep dequeue cost independent of the packet backlog size.
    private struct PacketQueue<Element> {
        private var storage: [Element?] = Array(repeating: nil, count: 64)
        private var head = 0
        private(set) var count = 0
        var isEmpty: Bool { count == 0 }
        var first: Element? { count == 0 ? nil : storage[head] }

        mutating func append(_ element: Element) {
            growIfNeeded()
            storage[(head + count) % storage.count] = element
            count += 1
        }

        mutating func prepend(_ element: Element) {
            growIfNeeded()
            head = (head + storage.count - 1) % storage.count
            storage[head] = element
            count += 1
        }

        mutating func popFirst() -> Element? {
            guard count > 0 else { return nil }
            let element = storage[head]
            storage[head] = nil
            head = (head + 1) % storage.count
            count -= 1
            return element
        }

        mutating func removeAll() { self = PacketQueue() }

        private mutating func growIfNeeded() {
            guard count == storage.count else { return }
            var larger = [Element?](repeating: nil, count: storage.count * 2)
            for offset in 0..<count { larger[offset] = storage[(head + offset) % storage.count] }
            storage = larger
            head = 0
        }
    }

    /// Reuse bounded drain loops so packet bursts do not create one GCD task per group.
    private final class EncryptionWorkers {
        private let queue = DispatchQueue(label: "com.duckduckgo.vpn.native-wireguard.encrypt", qos: .userInitiated, attributes: .concurrent)
        private let lock = NSLock()
        private let count: Int
        private var jobs = PacketQueue<() -> Void>()
        private var active = 0

        init(count: Int) { self.count = max(1, count) }

        func submit(_ work: @escaping () -> Void) {
            lock.lock()
            jobs.append(work)
            let needsWorker = active < count
            if needsWorker { active += 1 }
            lock.unlock()
            if needsWorker { queue.async { self.drain() } }
        }

        private func next() -> (() -> Void)? {
            lock.lock()
            defer { lock.unlock() }
            guard let work = jobs.popFirst() else { active -= 1; return nil }
            return work
        }

        private func drain() {
            while let work = next() { autoreleasepool { work() } }
        }
    }

    private var pathSatisfied: Bool?
    private var pendingPathRecovery: UUID?
    // Inject scheduling so path handoff tests do not depend on wall-clock timing.
    var schedulePathRecovery: ((@escaping () -> Void) -> Void)?
    private static let maximumQueuedPackets = 65_536
    private static let encryptionGroupSize = 32
    private static let maximumEncryptionGroups = 8
    // Go permits the initial initiation plus 19 retransmissions (MaxTimerHandshakes + 2).
    // Count actual submissions, so time asleep never consumes the retry budget.
    private static let maximumHandshakeTransmissions = 20
    private static let maximumInFlightSends = 64
    // Maximum payload that remains inside an IPv4 UDP datagram after WireGuard padding/overhead.
    private static let maximumPacketLength = 65_472
    private var cachedInterfaceMTU: Int?
    private var configuredPacketLimit: Int? {
        guard let mtu = configuration?.interface.mtu, mtu > 0 else { return nil }
        return Int(mtu)
    }
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    public convenience init(logHandler: @escaping (String) -> Void = { _ in }) {
#if os(iOS)
        let maximumQueuedBytes = 8 * 1024 * 1024
#else
        let maximumQueuedBytes = 32 * 1024 * 1024
#endif
        self.init(
            io: nil,
            makeTransport: { UDPWireGuardTransport(endpoint: $0) },
            makePeer: Self.makeConfiguredPeer,
            monotonicTime: { Double(mach_continuous_time()) * Self.secondsPerTick },
            epochTime: { Date().timeIntervalSince1970 },
            maximumQueuedBytes: maximumQueuedBytes,
            retryJitter: { Double.random(in: 0...0.333) },
            automaticTimers: true,
            logHandler: logHandler
        )
    }

    init(io: IO?,
         makeTransport: @escaping (Endpoint) -> NativeWireGuardTransport,
         makePeer: @escaping (TunnelConfiguration) throws -> WireGuardPeer,
         monotonicTime: @escaping () -> TimeInterval,
         epochTime: @escaping () -> TimeInterval,
         maximumQueuedBytes: Int = 32 * 1024 * 1024,
         retryJitter: @escaping () -> TimeInterval = { 0 },
         automaticTimers: Bool = false,
         logHandler: @escaping (String) -> Void = { _ in }) {
        self.io = io
        self.makeTransport = makeTransport
        self.makePeer = makePeer
        self.monotonicTime = monotonicTime
        self.epochTime = epochTime
        self.maximumQueuedBytes = max(0, maximumQueuedBytes)
        self.retryJitter = retryJitter
        self.automaticTimers = automaticTimers
        self.log = logHandler
    }

    deinit {
        timer?.cancel()
        networkMonitor?.cancel()
        transport?.cancel()
    }

    public func attach(to provider: NEPacketTunnelProvider) {
        attachedProvider = provider
        queue.async {
            guard self.io == nil else {
                self.log("Native WireGuard provider was already attached.")
                return
            }
            self.io = IO(
                applySettings: { [weak provider] settings, completion in
                    guard let provider else { completion(Failure.providerMissing); return }
                    provider.setTunnelNetworkSettings(settings, completionHandler: completion)
                },
                readPackets: { [weak provider] completion in
                    provider?.packetFlow.readPackets(completionHandler: completion)
                },
                writePackets: { [weak provider] packets, protocols in
                    provider?.packetFlow.writePackets(packets, withProtocols: protocols) ?? false
                },
                setReasserting: { [weak provider] in provider?.reasserting = $0 },
                cancelTunnel: { [weak provider] in provider?.cancelTunnelWithError($0) },
                interfaceMTU: { [weak provider] in
                    guard #available(macOS 15.0, iOS 18.0, *), let name = provider?.virtualInterface?.name else { return nil }
                    return Self.readInterfaceMTU(named: name)
                }
            )
        }
    }

    /// Keep interface syscalls off the per-packet path.
    static func readInterfaceMTU(named name: String) -> Int? {
        guard !name.isEmpty, name.utf8.count < Int(IFNAMSIZ) else { return nil }
        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var request = ifreq()
        withUnsafeMutableBytes(of: &request.ifr_name) { bytes in
            for (index, byte) in name.utf8.enumerated() { bytes[index] = byte }
        }
        // sys/sockio.h defines SIOCGIFMTU as _IOWR('i', 51, struct ifreq).
        // Swift cannot import that sizeof-based macro. Match sys/ioccom.h's
        // _IOC encoding using the actual imported struct layout instead.
        let command = UInt(IOC_INOUT) | ((UInt(MemoryLayout<ifreq>.size) & UInt(IOCPARM_MASK)) << 16)
            | (UInt(UInt8(ascii: "i")) << 8) | 51
        guard Darwin.ioctl(descriptor, command, &request) == 0 else { return nil }
        let mtu = Int(request.ifr_ifru.ifru_mtu)
        return mtu > 0 ? mtu : nil
    }

    private func refreshInterfaceMTU() {
        let measured = io?.interfaceMTU?()
        let refreshed = measured.flatMap { (1...65_535).contains($0) ? $0 : nil }
        if cachedInterfaceMTU != refreshed {
            cachedInterfaceMTU = refreshed
            // Padding was bound at reservation time. Discard old ciphertext and reserve
            // new nonces for its unsent plaintext if the effective limit changed.
            requeueEncryptionGroups()
        }
    }

    private func paddingLimit(for packet: Data) -> Int {
        // While an OS settings request is unresolved, avoid adding bytes under either
        // the old or the new MTU. The packet-flow payload itself remains unchanged.
        guard settingsUpdate == nil else { return packet.count }
        let limit: Int?
        if let configuredPacketLimit {
            limit = cachedInterfaceMTU.map { min(configuredPacketLimit, $0) } ?? configuredPacketLimit
        } else {
            limit = cachedInterfaceMTU
        }
        // An automatic-MTU cache may lag a path change. Never reject an OS-delivered
        // packet solely because it is larger than that cache; simply add no padding.
        return max(packet.count, limit ?? packet.count)
    }

    public var interfaceName: String? {
        if #available(macOS 15.0, iOS 18.0, *) { return attachedProvider?.virtualInterface?.name }
        return nil
    }

    public func start(tunnelConfiguration: TunnelConfiguration, completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        queue.async {
            guard self.state == .stopped || self.state == .snoozing else {
                completionHandler(.invalidState(.alreadyStarted))
                return
            }
            self.configure(tunnelConfiguration, reassert: false, completion: completionHandler)
        }
    }

    public func update(tunnelConfiguration: TunnelConfiguration,
                       reassert: Bool,
                       completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        queue.async {
            guard self.state != .stopped else {
                completionHandler(.invalidState(.updatedTunnelWhileStopped))
                return
            }
            self.configure(tunnelConfiguration, reassert: reassert, completion: completionHandler)
        }
    }

    public func stop(completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        queue.async {
            guard self.state != .stopped else {
                completionHandler(.invalidState(.alreadyStopped))
                return
            }
            self.deactivate(to: .stopped)
            self.configuration = nil
            completionHandler(nil)
        }
    }

    public func snooze(completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        queue.async {
            guard self.state != .stopped else {
                completionHandler(.invalidState(.alreadyStopped))
                return
            }
            self.deactivate(to: .snoozing)
            let generation = self.generation
            self.pendingCompletion = completionHandler
            self.io?.applySettings(nil) { error in
                self.queue.async {
                    guard self.generation == generation else { return }
                    self.finishOperation(error.map(WireGuardAdapterError.setNetworkSettings))
                }
            }
            self.queue.asyncAfter(deadline: .now() + 5) {
                guard self.generation == generation, self.state == .snoozing,
                      self.pendingCompletion != nil else { return }
                self.finishOperation(.setNetworkSettings(Failure.settingsTimedOut))
            }
        }
    }

    public func getBytesTransmitted() async throws -> (rx: UInt64, tx: UInt64) {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: (self.receivedBytes, self.sentBytes)) }
        }
    }

    public func getMostRecentHandshake() async throws -> TimeInterval {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.lastHandshake) }
        }
    }

    public func getRuntimeConfiguration(completionHandler: @escaping (String?) -> Void) {
        queue.async {
            guard self.state == .running, let configuredPeer = self.configuration?.peers.first else {
                completionHandler(nil)
                return
            }
            // These counters count authenticated encrypted transport datagrams, including keepalives.
            completionHandler("public_key=\(configuredPeer.publicKey.hexKey)\nrx_bytes=\(self.receivedBytes)\ntx_bytes=\(self.sentBytes)\nlast_handshake_time_sec=\(UInt64(self.lastHandshake))\nlast_handshake_time_nsec=0\n")
        }
    }

    private static func makeConfiguredPeer(_ configuration: TunnelConfiguration) throws -> WireGuardPeer {
        guard configuration.peers.count == 1, let configuredPeer = configuration.peers.first,
              configuredPeer.endpoint != nil else { throw Failure.unsupportedConfiguration }
        return try WireGuardPeer(
            privateKey: configuration.interface.privateKey.rawValue,
            peerPublicKey: configuredPeer.publicKey.rawValue,
            presharedKey: configuredPeer.preSharedKey?.rawValue
        )
    }

    private func configure(_ supplied: TunnelConfiguration,
                           reassert: Bool,
                           completion: @escaping (WireGuardAdapterError?) -> Void) {
        defer { requestTimerUpdate() }
        guard let io else { completion(.startWireGuardBackend(Failure.providerMissing)); return }
        let configuration = TunnelConfiguration(name: supplied.name, interface: supplied.interface, peers: supplied.peers)
        let peer: WireGuardPeer
        do {
            peer = try makePeer(configuration)
        } catch {
            completion(.startWireGuardBackend(error))
            return
        }
        if state == .running, let previousConfiguration = self.configuration {
            beginSettingsUpdate(configuration: configuration, peer: peer, previousConfiguration: previousConfiguration,
                                reassert: reassert, completion: completion)
            return
        }
        activate(configuration: configuration, peer: peer, reassert: reassert, completion: completion)
        let generation = self.generation
        io.applySettings(makeNetworkSettings(for: configuration)) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                guard self.generation == generation, self.state == .starting else { return }
                if let error {
                    self.finishOperation(.setNetworkSettings(error))
                    self.deactivate(to: .stopped)
                } else {
                    self.connect()
                }
            }
        }
    }

    private func activate(configuration: TunnelConfiguration, peer: WireGuardPeer, reassert: Bool,
                          completion: @escaping (WireGuardAdapterError?) -> Void) {
        deactivate(to: .starting)
        self.configuration = configuration
        self.peer = peer
        pendingCompletion = completion
        operationStarted = monotonicTime()
        receivedBytes = 0
        sentBytes = 0
        lastHandshake = 0
        lastKeyExchange = nil
        io?.setReasserting(reassert)
        startScheduling()
    }

    private func makeNetworkSettings(for configuration: TunnelConfiguration) -> NEPacketTunnelNetworkSettings {
        configuration.makePacketTunnelNetworkSettings()
    }

    private func beginSettingsUpdate(configuration: TunnelConfiguration, peer: WireGuardPeer,
                                     previousConfiguration: TunnelConfiguration, reassert: Bool,
                                     completion: @escaping (WireGuardAdapterError?) -> Void) {
        defer { requestTimerUpdate() }
        guard settingsUpdate == nil else {
            completion(.setNetworkSettings(Failure.settingsUpdateInProgress))
            return
        }
        let update = SettingsUpdate(configuration: configuration, peer: peer,
                                    previousSettings: makeNetworkSettings(for: previousConfiguration), reassert: reassert,
                                    completion: completion, deadline: monotonicTime() + 15)
        settingsUpdate = update
        cachedInterfaceMTU = nil
        requeueEncryptionGroups()
        let id = update.id
        if reassert { io?.setReasserting(true) }
        io?.applySettings(makeNetworkSettings(for: configuration)) { [weak self] error in
            self?.queue.async { [weak self] in self?.completeSettingsUpdate(id: id, error: error) }
        }
    }

    private func completeSettingsUpdate(id: UUID, error: Swift.Error?) {
        defer { requestTimerUpdate() }
        guard let update = settingsUpdate, update.id == id, update.failure == nil else { return }
        if let error {
            restorePreviousSettings(id: id, failure: .setNetworkSettings(error))
            return
        }
        settingsUpdate = nil
        activate(configuration: update.configuration, peer: update.peer, reassert: update.reassert, completion: update.completion)
        connect()
    }

    private func restorePreviousSettings(id: UUID, failure: WireGuardAdapterError) {
        defer { requestTimerUpdate() }
        guard var update = settingsUpdate, update.id == id, update.failure == nil else { return }
        update.failure = failure
        update.deadline = monotonicTime() + 5
        settingsUpdate = update
        io?.applySettings(update.previousSettings) { [weak self] error in
            self?.queue.async { [weak self] in self?.completeSettingsRestore(id: id, error: error) }
        }
    }

    private func completeSettingsRestore(id: UUID, error: Swift.Error?) {
        defer { requestTimerUpdate() }
        guard let update = settingsUpdate, update.id == id, let failure = update.failure else { return }
        settingsUpdate = nil
        if let error {
            deactivate(to: .stopped)
            io?.cancelTunnel(error)
        } else {
            refreshInterfaceMTU()
            io?.setReasserting(false)
        }
        update.completion(failure)
    }

    private func serviceSettingsUpdateDeadline(time: TimeInterval) {
        guard let update = settingsUpdate, time >= update.deadline else { return }
        if update.failure == nil {
            // An unresolved settings request cannot be cancelled. Do not race another
            // request against it: stop this provider rather than guessing OS apply order.
            settingsUpdate = nil
            deactivate(to: .stopped)
            io?.cancelTunnel(Failure.settingsTimedOut)
            update.completion(.setNetworkSettings(Failure.settingsTimedOut))
        } else {
            completeSettingsRestore(id: update.id, error: Failure.settingsTimedOut)
        }
    }

    private func finishOperation(_ error: WireGuardAdapterError?) {
        defer { requestTimerUpdate() }
        let completion = pendingCompletion
        pendingCompletion = nil
        io?.setReasserting(false)
        completion?(error)
    }

    private func deactivate(to state: State) {
        let updateCompletion = settingsUpdate?.completion
        settingsUpdate = nil
        generation &+= 1
        finishOperation(.startWireGuardBackend(Failure.operationCancelled))
        self.state = state
        cancelProtocolScheduling()
        networkMonitor?.cancel()
        networkMonitor = nil
        pathSatisfied = nil
        pendingPathRecovery = nil
        cancelTransport()
        peer?.reset()
        peer = nil
        cachedInterfaceMTU = nil
        pendingPackets.removeAll()
        queuedPacketBytes = 0
        queuedPacketCount = 0
        droppedPacketCount = 0
        receivingRekeyRequested = false
        updateCompletion?(.startWireGuardBackend(Failure.operationCancelled))
        // A packet-flow read cannot be cancelled. Its callback keeps ownership until it returns,
        // even across stop/update/start, so a second reader is never issued on the same flow.
    }

    private func cancelTransport(preservingSession: Bool = false) {
        defer { requestTimerUpdate() }
        transportGeneration &+= 1
        transport?.cancel()
        transport = nil
        transportReady = false
        inFlightSends = 0
        inFlightPacketSends = 0
        // Worker capacity is released only by physical completion, across reconnects too.
        // Unsent plaintext returns to the FIFO; old ciphertext can never reach a new session.
        requeueEncryptionGroups()
        pendingKeepalive = false
        keepaliveInFlight = false
        if !preservingSession {
            pendingInitiation = nil
            pendingResponse = nil
            handshakeTransmissions = 0
            handshakeRetryExhausted = false
            handshakeCleanupDeadline = nil
            nextHandshake = nil
            unansweredPacketDeadline = nil
            passiveKeepalive = nil
        }
        nextReconnect = nil
    }

    private func connect() {
        defer { requestTimerUpdate() }
        guard state == .starting || state == .running,
              let endpoint = configuration?.peers.first?.endpoint else { return }
        // Replacing a UDP socket does not replace the authenticated peer. Keep live
        // keys, receive replay history, send counters and any pending handshake retry.
        cancelTransport(preservingSession: true)
        let transport = makeTransport(endpoint)
        self.transport = transport
        let generation = self.generation
        let transportGeneration = self.transportGeneration
        transport.start(queue: queue) { [weak self] state in
            guard let self else { return }
            self.queue.async {
                guard self.generation == generation, self.transportGeneration == transportGeneration else { return }
                switch state {
                case .ready:
                    self.nextReconnect = nil
                    guard !self.transportReady else { return }
                    self.transportReady = true
                    self.state = .running
                    self.lastActivity = self.monotonicTime()
                    self.receiveDatagram()
                    self.resumeProtocolOnTransport()
                    self.readPackets()
                    self.finishOperation(nil)
                case .failed(let error): self.transportFailed(error)
                case .waiting:
                    self.nextReconnect = self.monotonicTime() + 2
                default: break
                }
                self.requestTimerUpdate()
            }
        }
    }

    private func resumeProtocolOnTransport() {
        defer { requestTimerUpdate() }
        refreshInterfaceMTU()
        if pendingResponse != nil { flushControl() }
        if peer?.isAwaitingConfirmation == true, peer?.isEstablished != true,
           nextHandshake == nil, pendingInitiation == nil, queuedPacketCount == 0 { return }
        if peer?.isEstablished == true {
            // Confirm live keys on the new path before requesting an age-based rekey.
            sendKeepalive()
            rearmHandshakeForTraffic()
            flushPackets()
            return
        }
        rearmHandshakeForTraffic()
        if pendingInitiation != nil {
            // This initiation was constructed while the old transport had no control
            // capacity, so submit it now and space retries from its actual send time.
            flushControl()
        } else if nextHandshake.map({ monotonicTime() >= $0 }) ?? true {
            initiateHandshake()
        }
    }

    private func transportFailed(_ error: Swift.Error) {
        defer { requestTimerUpdate() }
        log("Native WireGuard UDP transport failed: \(error.localizedDescription)")
        cancelTransport(preservingSession: true)
        nextReconnect = monotonicTime() + 2
    }

    private func initiateHandshake() {
        defer { requestTimerUpdate() }
        guard transportReady, let peer else { return }
        if handshakeRetryExhausted {
            handshakeRetryExhausted = false
            handshakeTransmissions = 0
        }
        let time = monotonicTime()
        do {
            let initiation = try peer.initiateHandshake()
            nextHandshake = time + 5 + max(0, min(0.333, retryJitter()))
            pendingInitiation = initiation
            flushControl()
        } catch {
            // Index collisions and the peer's rate limit are retried by the same bounded timer.
            nextHandshake = time + 5 + max(0, min(0.333, retryJitter()))
            log("Native WireGuard handshake initiation failed: \(error.localizedDescription)")
        }
    }

    private func startScheduling() {
        if automaticTimers {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .distantFuture)
            timer.resume()
            self.timer = timer

            let monitor = NWPathMonitor()
            let generation = self.generation
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self, self.generation == generation else { return }
                self.handleNetworkPathUpdate(status: path.status)
            }
            monitor.start(queue: queue)
            networkMonitor = monitor
        }
        requestTimerUpdate()
    }

    private func cancelProtocolScheduling() {
        timerEpoch &+= 1
        timerUpdateQueued = false
        armedTimerDeadline = nil
        timer?.cancel()
        timer = nil
        scheduleProtocolTimer?(nil, {})
    }

    /// Avoid rescheduling the timer once per packet during a callback burst.
    private func requestTimerUpdate() {
        guard automaticTimers || scheduleProtocolTimer != nil else { return }
        guard !timerUpdateQueued else { return }
        timerUpdateQueued = true
        let generation = self.generation
        queue.async { [weak self] in
            guard let self, self.generation == generation else { return }
            self.timerUpdateQueued = false
            self.updateProtocolTimer()
        }
    }

    private func updateProtocolTimer() {
        let deadline = nextProtocolDeadline()
        guard deadline != armedTimerDeadline else { return }
        armedTimerDeadline = deadline
        timerEpoch &+= 1
        let epoch = timerEpoch
        let generation = self.generation
        let fire = { [weak self] in
            guard let self, self.generation == generation, self.timerEpoch == epoch else { return }
            self.armedTimerDeadline = nil
            self.timerEpoch &+= 1
            self.tick()
        }
        if let scheduleProtocolTimer {
            scheduleProtocolTimer(deadline, fire)
        } else if let deadline {
            timer?.setEventHandler(handler: fire)
            timer?.schedule(deadline: .now() + max(0, deadline - monotonicTime()), leeway: .milliseconds(1))
        } else {
            timer?.setEventHandler {}
            timer?.schedule(deadline: .distantFuture)
        }
    }

    /// The earliest actionable protocol deadline. Blocked writes are rearmed by send completions,
    /// not by repeatedly scheduling an already-expired deadline on a full transport.
    func nextProtocolDeadline() -> TimeInterval? {
        guard state == .starting || state == .running else { return nil }
        var deadlines: [TimeInterval] = []
        if state == .starting { deadlines.append(operationStarted + 15) }
        if let update = settingsUpdate { deadlines.append(update.deadline) }
        if let handshakeCleanupDeadline { deadlines.append(handshakeCleanupDeadline) }
        if let lastKeyExchange { deadlines.append(lastKeyExchange + 540) }
        if pathSatisfied != false, let nextReconnect { deadlines.append(nextReconnect) }
        guard state == .running, transportReady, let peer else { return deadlines.min() }
        if pendingInitiation == nil, let nextHandshake { deadlines.append(nextHandshake) }
        if nextHandshake == nil, pendingInitiation == nil,
           let unansweredPacketDeadline { deadlines.append(unansweredPacketDeadline) }
        appendKeepaliveDeadlines(peer: peer, to: &deadlines)
        return deadlines.min()
    }

    private func appendKeepaliveDeadlines(peer: WireGuardPeer, to deadlines: inout [TimeInterval]) {
        let interval = TimeInterval(configuration?.peers.first?.persistentKeepAlive ?? 0)
        if peer.isEstablished {
            guard !keepaliveInFlight, !pendingKeepalive else { return }
            if interval > 0 { deadlines.append(lastActivity + interval) }
            if let passiveKeepalive { deadlines.append(passiveKeepalive) }
        } else if interval > 0, nextHandshake == nil, pendingInitiation == nil {
            // A configured keepalive can start a new attempt after retry exhaustion.
            deadlines.append(lastActivity + interval)
        }
    }

    /// Called on `queue` for every default-path callback, including satisfied-to-satisfied
    /// handoffs. A first satisfied callback describes the path used by the initial transport.
    func handleNetworkPathUpdate(status: Network.NWPath.Status) {
        defer { requestTimerUpdate() }
        guard state == .starting || state == .running else { return }
        let initialPath = pathSatisfied == nil
        let satisfied = status == .satisfied
        if !initialPath, cachedInterfaceMTU != nil {
            // The OS can change the TUN MTU before the coalesced socket recovery.
            // Use unpadded snapshots until readiness refreshes the effective limit.
            cachedInterfaceMTU = nil
            requeueEncryptionGroups()
        }
        pathSatisfied = satisfied
        guard satisfied else {
            pendingPathRecovery = nil
            cancelTransport(preservingSession: true)
            return
        }
        guard !initialPath, pendingPathRecovery == nil else { return }
        let recovery = UUID()
        pendingPathRecovery = recovery
        let generation = self.generation
        let transportGeneration = self.transportGeneration
        let reconnect = { [weak self] in
            guard let self, self.generation == generation, self.pendingPathRecovery == recovery else { return }
            self.pendingPathRecovery = nil
            guard self.pathSatisfied == true, self.transportGeneration == transportGeneration else { return }
            self.connect()
        }
        if let schedulePathRecovery {
            schedulePathRecovery(reconnect)
        } else {
            queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: reconnect)
        }
    }

    /// Called on `queue`; the internal entry point also lets tests advance a deterministic clock.
    func tick() {
        defer { requestTimerUpdate() }
        let time = monotonicTime()
        serviceSettingsUpdateDeadline(time: time)
        if state == .starting, time - operationStarted >= 15 {
            finishOperation(.startWireGuardBackend(Failure.startupTimedOut))
            deactivate(to: .stopped)
            return
        }
        guard state == .running || state == .starting else { return }
        if let handshakeCleanupDeadline, time >= handshakeCleanupDeadline {
            self.handshakeCleanupDeadline = nil
            peer?.reset()
            pendingInitiation = nil
            pendingResponse = nil
            pendingKeepalive = false
            requeueEncryptionGroups()
            while let packet = pendingPackets.popFirst() { releaseQueuedPacket(packet) }
        }
        if let lastKeyExchange, time - lastKeyExchange >= 540 {
            peer?.reset()
            self.lastKeyExchange = nil
        }
        if let nextReconnect, time >= nextReconnect, pathSatisfied != false {
            connect()
        }
        guard state == .running, transportReady, let peer else { return }
        serviceSessionTimers(time: time, peer: peer)
    }

    private func serviceSessionTimers(time: TimeInterval, peer: WireGuardPeer) {
        if let nextHandshake {
            if time >= nextHandshake {
                if handshakeTransmissions >= Self.maximumHandshakeTransmissions {
                    exhaustHandshakeRetries(peer: peer)
                } else {
                    initiateHandshake()
                }
            }
        } else if unansweredPacketDeadline.map({ time >= $0 }) ?? false {
            initiateHandshake()
        }
        let keepaliveInterval = TimeInterval(configuration?.peers.first?.persistentKeepAlive ?? 0)
        let persistentKeepaliveDue = keepaliveInterval > 0 && time - lastActivity >= keepaliveInterval
        if persistentKeepaliveDue, !peer.isEstablished {
            // A configured persistent keepalive is fresh outbound activity, even
            // without keys. Go stages it and thereby starts a new handshake episode.
            rearmHandshakeForTraffic()
        }
        guard peer.isEstablished else { return }
        if !keepaliveInFlight && (persistentKeepaliveDue || (passiveKeepalive.map { time >= $0 } ?? false)) {
            sendKeepalive()
        }
        flushPackets()
    }

    private func exhaustHandshakeRetries(peer: WireGuardPeer) {
        log("Native WireGuard handshake retry episode exhausted; waiting for traffic or network recovery.")
        handshakeRetryExhausted = true
        // Go also bounds the lifetime of an incomplete first exchange. Completed
        // sessions already have the separate lastKeyExchange + 540 cleanup deadline.
        if lastKeyExchange == nil, handshakeCleanupDeadline == nil {
            handshakeCleanupDeadline = monotonicTime() + 540
        }
        nextHandshake = nil
        pendingInitiation = nil
        pendingKeepalive = false
        passiveKeepalive = nil
        unansweredPacketDeadline = nil
        // Like Go's staged queue, discard traffic waiting for usable keys. Already
        // prepared packets may still drain under a live current session during rekey.
        if !peer.isEstablished { requeueEncryptionGroups() }
        while let packet = pendingPackets.popFirst() { releaseQueuedPacket(packet) }
    }

    private func rearmHandshakeForTraffic(freshActivity: Bool = true) {
        guard let peer, !peer.isEstablished || peer.needsRekey else { return }
        if freshActivity {
            // Go resets its retransmission count for a new outbound request before
            // checking the five-second rate guard. Our count includes the initiation:
            // keep one only when the active episode already has a submitted message.
            let submittedEpisode = nextHandshake != nil && pendingInitiation == nil && handshakeTransmissions > 0
            handshakeTransmissions = submittedEpisode ? 1 : 0
            handshakeRetryExhausted = false
        }
        guard !handshakeRetryExhausted, nextHandshake == nil, pendingInitiation == nil else { return }
        // Fresh outbound activity can require our own exchange even while a responder
        // next session is waiting for confirmation, as in Go's SendStagedPackets.
        initiateHandshake()
    }

    private func send(_ datagram: Data, containsPacket: Bool = false, isKeepalive: Bool = false) -> Bool {
        guard transportReady, let transport, inFlightSends < Self.maximumInFlightSends,
              !containsPacket || inFlightPacketSends < Self.maximumInFlightSends - 1 else { return false }
        let generation = self.generation
        let transportGeneration = self.transportGeneration
        inFlightSends += 1
        if containsPacket { inFlightPacketSends += 1 }
        if isKeepalive { keepaliveInFlight = true }
        transport.send(datagram) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                guard self.generation == generation, self.transportGeneration == transportGeneration else { return }
                self.completedSend(datagram, containsPacket: containsPacket, isKeepalive: isKeepalive, error: error)
            }
        }
        return true
    }

    private func completedSend(_ datagram: Data, containsPacket: Bool, isKeepalive: Bool, error: NWError?) {
        defer { requestTimerUpdate() }
        inFlightSends -= 1
        if containsPacket { inFlightPacketSends -= 1 }
        if isKeepalive { keepaliveInFlight = false }
        if let error {
            transportFailed(error)
            return
        }
        if datagram.first == 1 || datagram.first == 2 {
            // Handshake traffic also refreshes the persistent-keepalive deadline.
            lastActivity = monotonicTime()
            passiveKeepalive = nil
        }
        if datagram.first == 4 {
            sentBytes &+= UInt64(datagram.count)
            lastActivity = monotonicTime()
            passiveKeepalive = nil
            if containsPacket, unansweredPacketDeadline == nil {
                // Draw once for the first unanswered data packet, matching Go's timersDataSent.
                unansweredPacketDeadline = monotonicTime() + 15 + max(0, min(0.333, retryJitter()))
            }
            if peer?.needsRekey == true { rearmHandshakeForTraffic() }
        }
        flushControl()
        flushPackets()
    }

    private func sendKeepalive() {
        defer { requestTimerUpdate() }
        pendingKeepalive = true
        flushControl()
    }

    private func flushControl() {
        defer { requestTimerUpdate() }
        guard transportReady, inFlightSends < Self.maximumInFlightSends else { return }
        if let pendingResponse {
            guard send(pendingResponse) else { return }
            self.pendingResponse = nil
        }
        if pendingKeepalive, !keepaliveInFlight, let peer, peer.isEstablished,
           let keepalive = try? peer.keepalive(), send(keepalive, isKeepalive: true) {
            pendingKeepalive = false
        }
        if let pendingInitiation, send(pendingInitiation) {
            self.pendingInitiation = nil
            handshakeTransmissions += 1
            // A control slot may only become available long after the initiation was created.
            // Space retransmissions from actual submission to UDP, not from key construction.
            nextHandshake = monotonicTime() + 5 + max(0, min(0.333, retryJitter()))
        }
    }

    private func receiveDatagram() {
        guard let transport, transportReady else { return }
        let generation = self.generation
        let transportGeneration = self.transportGeneration
        transport.receive { [weak self] datagrams, error in
            guard let self else { return }
            self.queue.async {
                guard self.generation == generation, self.transportGeneration == transportGeneration else { return }
                if let error { self.transportFailed(error); return }
                // Keep reads queued before spending time decrypting the completed batch.
                self.receiveDatagram()
                var packets: [Data] = []
                var protocols: [NSNumber] = []
                packets.reserveCapacity(datagrams.count)
                protocols.reserveCapacity(datagrams.count)
                for datagram in datagrams {
                    if let packet = self.consume(datagram) {
                        packets.append(packet)
                        protocols.append(NSNumber(value: packet[packet.startIndex] >> 4 == 4 ? AF_INET : AF_INET6))
                    }
                }
                if !packets.isEmpty, self.io?.writePackets(packets, protocols) == false {
                    self.log("Native WireGuard packet-flow write rejected a batch.")
                }
            }
        }
    }

    private func recordHandshakeCompletion() {
        lastHandshake = epochTime()
        lastKeyExchange = monotonicTime()
        lastActivity = monotonicTime()
        unansweredPacketDeadline = nil
        handshakeTransmissions = 0
        handshakeRetryExhausted = false
        handshakeCleanupDeadline = nil
        receivingRekeyRequested = false
        nextHandshake = nil
        pendingInitiation = nil
        pendingResponse = nil
    }

    private func rekeyAfterAuthenticatedReceive(peer: WireGuardPeer) {
        guard !receivingRekeyRequested, peer.needsRekeyAfterReceiving else { return }
        receivingRekeyRequested = true
        if nextHandshake == nil, pendingInitiation == nil { initiateHandshake() }
    }

    private func consume(_ datagram: Data) -> Data? {
        defer { requestTimerUpdate() }
        guard let peer else { return nil }
        let handshakeGeneration = peer.handshakeGeneration
        do {
            let result = try peer.receive(datagram)
            let handshakeCompleted = handshakeGeneration != peer.handshakeGeneration
            if handshakeCompleted { recordHandshakeCompletion() }
            defer { if handshakeCompleted { flushPackets() } }
            switch result {
            case .handshakeComplete:
                sendKeepalive()
            case .handshakeResponse(let response):
                handshakeCleanupDeadline = nil
                lastKeyExchange = monotonicTime()
                lastActivity = monotonicTime()
                unansweredPacketDeadline = nil
                // Keep at most the latest response and give it the reserved control slot.
                pendingResponse = response
                pendingInitiation = nil
                // Preserve an existing retransmit episode: crossed initiations can leave
                // both responders awaiting confirmation until a fresh jittered retry.
                flushControl()
            case .cookieReceived:
                // The outstanding handshake timer retains the >=5s+jitter rate limit.
                break
            case .keepalive:
                rekeyAfterAuthenticatedReceive(peer: peer)
                receivedBytes &+= UInt64(datagram.count)
                lastActivity = monotonicTime()
                unansweredPacketDeadline = nil
            case .packet(let packet):
                rekeyAfterAuthenticatedReceive(peer: peer)
                guard let ranges = configuration?.peers.first?.allowedIPs,
                      Self.permits(packet, source: true, ranges: ranges) else { return nil }
                receivedBytes &+= UInt64(datagram.count)
                lastActivity = monotonicTime()
                unansweredPacketDeadline = nil
                if passiveKeepalive == nil { passiveKeepalive = monotonicTime() + 10 }
                return packet
            }
        } catch {
            // Authenticated transport confirms responder keys even if its IP payload is invalid.
            if handshakeGeneration != peer.handshakeGeneration {
                recordHandshakeCompletion()
                flushPackets()
            }
            // Malformed, unauthenticated, stale and replayed UDP packets are dropped.
        }
        return nil
    }

    private func readPackets() {
        guard state == .running, packetReadID == nil, let io else { return }
        let readID = UUID()
        packetReadID = readID
        let generation = self.generation
        io.readPackets { [weak self] packets, _ in
            guard let self else { return }
            self.queue.async {
                guard self.packetReadID == readID else { return }
                self.packetReadID = nil
                guard self.state == .running else { return }
                if self.generation == generation {
                    for packet in packets { self.enqueue(packet) }
                    self.flushPackets()
                }
                self.readPackets()
            }
        }
    }

    private func enqueue(_ packet: Data) {
        defer { requestTimerUpdate() }
        guard packet.count <= min(configuredPacketLimit ?? Self.maximumPacketLength, Self.maximumPacketLength),
              let ranges = configuration?.peers.first?.allowedIPs,
              Self.permits(packet, source: false, ranges: ranges) else { return }
        guard queuedPacketCount < Self.maximumQueuedPackets,
              packet.count <= maximumQueuedBytes - queuedPacketBytes else {
            droppedPacketCount &+= 1
            if droppedPacketCount == 1 { log("Native WireGuard outbound buffer full; dropping packets.") }
            return
        }
        pendingPackets.append(packet)
        queuedPacketBytes += packet.count
        queuedPacketCount += 1
        rearmHandshakeForTraffic()
    }

    private func releaseQueuedPacket(_ packet: Data) {
        queuedPacketBytes -= packet.count
        queuedPacketCount -= 1
    }

    private func flushPackets() {
        defer { requestTimerUpdate() }
        guard state == .running, transportReady, let peer else { return }
        guard peer.isEstablished else {
            // A worker finishing after key expiry is outgoing work too; it must not
            // depend on an idle polling tick to request usable keys for the backlog.
            if queuedPacketCount > 0, !handshakeRetryExhausted { rearmHandshakeForTraffic(freshActivity: false) }
            return
        }
        flushControl()
        if let first = encryptionGroups.first, !peer.canSend(first.packets[first.nextIndex]) {
            requeueEncryptionGroups()
        }
        flushEncryptedGroups()
        prepareEncryptionGroups(peer: peer)
        // Single-packet groups can complete immediately without a worker round trip.
        flushEncryptedGroups()
    }

    private func requeueEncryptionGroups() {
        encryptionGeneration &+= 1
        var packets: [Data] = []
        while let group = encryptionGroups.popFirst() {
            packets.append(contentsOf: group.packets[group.nextIndex...].map(\.packet))
        }
        for packet in packets.reversed() { pendingPackets.prepend(packet) }
    }

    private func flushEncryptedGroups() {
        guard !pendingKeepalive, pendingInitiation == nil, pendingResponse == nil,
              inFlightSends < Self.maximumInFlightSends,
              inFlightPacketSends < Self.maximumInFlightSends - 1,
              encryptionGroups.first?.datagrams != nil else { return }
        transport?.batch {
            // Each completed FIFO head may leave while later groups are still encrypting.
            while let group = encryptionGroups.first, let datagrams = group.datagrams {
                while group.nextIndex < group.packets.count {
                    if let datagram = datagrams[group.nextIndex], !send(datagram, containsPacket: true) { return }
                    releaseQueuedPacket(group.packets[group.nextIndex].packet)
                    group.nextIndex += 1
                }
                _ = encryptionGroups.popFirst()
            }
        }
    }

    private func prepareEncryptionGroups(peer: WireGuardPeer) {
        while !pendingPackets.isEmpty, activeEncryptionJobs < Self.maximumEncryptionGroups,
              encryptionGroups.count < Self.maximumEncryptionGroups {
            var prepared: [WireGuardPeer.PreparedPacket] = []
            prepared.reserveCapacity(Self.encryptionGroupSize)
            var sessionUnavailable = false
            for _ in 0..<Self.encryptionGroupSize {
                guard let packet = pendingPackets.popFirst() else { break }
                do { prepared.append(try peer.prepare(packet, maximumPacketLength: paddingLimit(for: packet))) } catch WireGuardPeer.Error.invalidPacket {
                    releaseQueuedPacket(packet)
                } catch {
                    pendingPackets.prepend(packet)
                    sessionUnavailable = true
                    break
                }
            }
            if !prepared.isEmpty { startEncryption(prepared) }
            if sessionUnavailable { return }
        }
    }

    private func startEncryption(_ prepared: [WireGuardPeer.PreparedPacket]) {
        let group = EncryptionGroup(packets: prepared, generation: encryptionGeneration)
        encryptionGroups.append(group)
        if prepared.count == 1 {
            group.datagrams = [try? prepared[0].encrypt()]
            return
        }
        activeEncryptionJobs += 1
        let work = { [weak self] in
            let datagrams = prepared.map { try? $0.encrypt() }
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.activeEncryptionJobs -= 1
                if group.generation == self.encryptionGeneration { group.datagrams = datagrams }
                self.flushPackets()
            }
        }
        if let scheduleEncryption { scheduleEncryption(work) } else { encryptionWorkers.submit(work) }
    }

    static func permits(_ packet: Data, source: Bool, ranges: [IPAddressRange]) -> Bool {
        let bytes = [UInt8](packet)
        guard let version = bytes.first.map({ $0 >> 4 }) else { return false }
        let offset: Int
        let length: Int
        switch version {
        case 4: offset = source ? 12 : 16; length = 4
        case 6: offset = source ? 8 : 24; length = 16
        default: return false
        }
        guard bytes.count >= offset + length else { return false }
        return ranges.contains { range in
            let network = [UInt8](range.address.rawValue)
            guard network.count == length, Int(range.networkPrefixLength) <= length * 8 else { return false }
            for bit in 0..<Int(range.networkPrefixLength) {
                let mask = UInt8(0x80) >> (bit % 8)
                if bytes[offset + bit / 8] & mask != network[bit / 8] & mask { return false }
            }
            return true
        }
    }

}
#endif
