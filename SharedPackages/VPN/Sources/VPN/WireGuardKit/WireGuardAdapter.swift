// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import Foundation
import NetworkExtension
import os.log
import Common

// MARK: - WireGuard Go Interface

/// This protocol abstracts the WireGuard Go library.
/// The Go library is only included in VPN packet tunnel provider targets that need it, to avoid being embedded in other targets such as apps and login items that don't use it.
public protocol WireGuardGoInterface {
    func turnOn(settings: UnsafePointer<CChar>, handle: Int32) -> Int32
    func turnOff(handle: Int32)
    func getConfig(handle: Int32) -> UnsafeMutablePointer<CChar>?
    func setConfig(handle: Int32, config: String) -> Int64
    func bumpSockets(handle: Int32)
    func disableSomeRoamingForBrokenMobileSemantics(handle: Int32)
    func setLogger(context: UnsafeMutableRawPointer?, logFunction: (@convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void)?)
}

// MARK: - WireGuard Adapter

public enum WireGuardAdapterEvent {
    /// Sent when the attempt to exit the temporary shutdown state fails for any reason.
    case endTemporaryShutdownStateAttemptFailure(Error)

    /// Sent when the adapter restart had already failed and a subsequent attempt to restart the backend succeeded.
    case endTemporaryShutdownStateRecoverySuccess

    /// Sent when the adapter restart had already failed and a subsequent attempt to restart the backend also failed.
    case endTemporaryShutdownStateRecoveryFailure(Error)
}

public enum WireGuardAdapterErrorInvalidStateReason: String {
    case alreadyStarted
    case alreadyStopped
    case updatedTunnelWhileStopped
}

public enum WireGuardAdapterError: CustomNSError {
    /// Failure to locate tunnel file descriptor.
    case cannotLocateTunnelFileDescriptor

    /// Failure to perform an operation in such state. Includes a reason why the error was returned.
    case invalidState(WireGuardAdapterErrorInvalidStateReason)

    /// Failure to resolve endpoints.
    case dnsResolution([DNSResolutionError])

    /// Failure to set network settings.
    case setNetworkSettings(Error)

    /// Failure to start WireGuard backend.
    case startWireGuardBackend(Error)

    /// Failure to set the configuration for the WireGuard adapter
    case setWireguardConfig(Error)

    static let wireguardAdapterDomain = "WireGuardAdapter"

    public var errorCode: Int {
        switch self {
        case .cannotLocateTunnelFileDescriptor: return 100
        case .invalidState: return 101
        case .dnsResolution: return 102
        case .setNetworkSettings: return 103
        case .startWireGuardBackend: return 104
        case .setWireguardConfig: return 105
        }
    }

    public var errorUserInfo: [String: Any] {
        switch self {
        case .cannotLocateTunnelFileDescriptor,
                .invalidState:
            return [:]
        case .dnsResolution(let errors):
            guard let firstError = errors.first else {
                return [:]
            }

            return [NSUnderlyingErrorKey: firstError as NSError]
        case .setNetworkSettings(let error):
            return [NSUnderlyingErrorKey: error as NSError]
        case .startWireGuardBackend(let error):
            return [NSUnderlyingErrorKey: error as NSError]
        case .setWireguardConfig(let error):
            return [NSUnderlyingErrorKey: error as NSError]
        }
    }
}

/// Enum representing internal state of the `WireGuardAdapter`
private enum State: CustomDebugStringConvertible {
    /// The tunnel is stopped
    case stopped

    /// The tunnel is up and running
    case started(_ handle: Int32, _ settingsGenerator: PacketTunnelSettingsGenerating)

    /// The tunnel is temporarily shutdown due to device going offline
    case temporaryShutdown(_ settingsGenerator: PacketTunnelSettingsGenerating)

    case snoozing

    var canStartAdapter: Bool {
        switch self {
        case .stopped, .snoozing: return true
        case .started, .temporaryShutdown: return false
        }
    }

    var debugDescription: String {
        switch self {
        case .stopped:
            return "State: stopped"
        case .started(let handle, let settingsGenerator):
            return "State: started(handle: \(handle), settingsGenerator: \(settingsGenerator))"
        case .temporaryShutdown(let settingsGenerator):
            return "State: temporaryShutdown(settingsGenerator: \(settingsGenerator))"
        case .snoozing:
            return "State: snoozing"
        }
    }
}

// swiftlint:disable:next type_body_length
final class WireGuardAdapter: WireGuardAdapterProtocol {
    public typealias LogHandler = (WireGuardLogLevel, String) -> Void
    typealias PacketTunnelSettingsGeneratorProvider = (TunnelConfiguration, [Endpoint?]) -> PacketTunnelSettingsGenerating

    /// WireGuard configuration fields
    ///
    private enum ConfigurationFields: String {
        case rxBytes = "rx_bytes"
        case txBytes = "tx_bytes"
        case mostRecentHandshake = "last_handshake_time_sec"

        var configLinePrefix: String {
            switch self {
            case .rxBytes:
                return "\(rawValue)="
            case .txBytes:
                return "\(rawValue)="
            case .mostRecentHandshake:
                return "\(rawValue)="
            }
        }
    }

    /// Network routes monitor.
    private let pathMonitorProvider: () -> PathMonitoring
    private var networkMonitor: PathMonitoring?

    /// Factory for creating packet tunnel settings generators.
    private let packetTunnelSettingsGeneratorProvider: (TunnelConfiguration, [Endpoint?]) -> PacketTunnelSettingsGenerating

    /// DNS resolver used to resolve peer endpoints.
    private let dnsResolver: DNSResolving

    /// Packet tunnel provider.
    private weak var packetTunnelProvider: PacketTunnelProviding?

    /// Handles events from the adapter.
    private let eventHandler: WireGuardAdapterEventHandling

    /// Log handler closure.
    private let logHandler: LogHandler

    /// Private queue used to synchronize access to `WireGuardAdapter` members.
    private let workQueue = DispatchQueue(label: "WireGuardAdapterWorkQueue")

    /// Adapter state.
    private var state: State = .stopped

    /// Keeps track of whether a recovery attempt from temporary shutdown has already failed.
    private var temporaryShutdownRecoveryFailed = false

    private let wireGuardInterface: WireGuardGoInterface

    /// Tunnel device file descriptor.
    private let tunnelFileDescriptorProvider: TunnelFileDescriptorProviding

    /// Returns the tunnel device interface name, or nil on error.
    /// - Returns: String.
    public var interfaceName: String? {
        guard let tunnelFileDescriptor = tunnelFileDescriptorProvider.currentFileDescriptor() else { return nil }

        var buffer = [UInt8](repeating: 0, count: Int(IFNAMSIZ))

        return buffer.withUnsafeMutableBufferPointer { mutableBufferPointer in
            guard let baseAddress = mutableBufferPointer.baseAddress else { return nil }

            var ifnameSize = socklen_t(IFNAMSIZ)
            let result = getsockopt(
                tunnelFileDescriptor,
                2 /* SYSPROTO_CONTROL */,
                2 /* UTUN_OPT_IFNAME */,
                baseAddress,
                &ifnameSize)

            if result == 0 {
                return String(cString: baseAddress)
            } else {
                return nil
            }
        }
    }

    // MARK: - Initialization

    /// Designated initializer.
    /// - Parameter packetTunnelProvider: an instance of `NEPacketTunnelProvider`. Internally stored
    ///   as a weak reference.
    /// - Parameter logHandler: a log handler closure.

    init(with packetTunnelProvider: PacketTunnelProviding,
         wireGuardInterface: WireGuardGoInterface,
         eventHandler: WireGuardAdapterEventHandling,
         logHandler: @escaping LogHandler,
         pathMonitorProvider: @escaping () -> PathMonitoring = { PathMonitor() },
         packetTunnelSettingsGeneratorProvider: @escaping PacketTunnelSettingsGeneratorProvider = { configuration, resolvedEndpoints in
        PacketTunnelSettingsGenerator(tunnelConfiguration: configuration, resolvedEndpoints: resolvedEndpoints)
    },
         dnsResolver: DNSResolving = DefaultDNSResolver(),
         tunnelFileDescriptorProvider: TunnelFileDescriptorProviding = UtunFileDescriptorProvider()) {
        Logger.networkProtectionMemory.debug("[+] WireGuardAdapter")

        self.packetTunnelProvider = packetTunnelProvider
        self.wireGuardInterface = wireGuardInterface
        self.eventHandler = eventHandler
        self.logHandler = logHandler
        self.pathMonitorProvider = pathMonitorProvider
        self.packetTunnelSettingsGeneratorProvider = packetTunnelSettingsGeneratorProvider
        self.dnsResolver = dnsResolver
        self.tunnelFileDescriptorProvider = tunnelFileDescriptorProvider

        setupLogHandler()
    }

    deinit {
        Logger.networkProtectionMemory.debug("[-] WireGuardAdapter")

        // Force remove logger to make sure that no further calls to the instance of this class
        // can happen after deallocation.
        wireGuardInterface.setLogger(context: nil, logFunction: nil)

        // Cancel network monitor
        networkMonitor?.cancel()

        // Shutdown the tunnel
        if case .started(let handle, _) = self.state {
            wireGuardInterface.turnOff(handle: handle)
        }
    }

    // MARK: - Public methods

    enum GetBytesTransmittedError: Error {
        case couldNotObtainAdapterConfiguration
    }

    /// Retrieves the sum of all bytes read and transmitted through the WireGuard tunnel interface since the connection was established.
    ///
    /// - Throws: ConfigReadingError
    /// - Returns: A pair with the sum of Rx bytes and Tx bytes since the tunnel was started.
    ///
    func getBytesTransmitted() async throws -> (rx: UInt64, tx: UInt64) {
        try await withCheckedThrowingContinuation { continuation in
            getRuntimeConfiguration { configuration in
                guard let configuration = configuration else {
                    continuation.resume(throwing: GetBytesTransmittedError.couldNotObtainAdapterConfiguration)
                    return
                }

                let lines = configuration.components(separatedBy: .newlines)
                let bytesTransmitted = lines.reduce((rx: UInt64(0), tx: UInt64(0)), { partialResult, line in
                    if line.hasPrefix(ConfigurationFields.rxBytes.configLinePrefix) {
                        let additionalRx = UInt64(line.dropFirst(ConfigurationFields.rxBytes.configLinePrefix.count)) ?? 0
                        return (partialResult.rx + additionalRx, partialResult.tx)
                    } else if line.hasPrefix(ConfigurationFields.txBytes.configLinePrefix) {
                        let additionalTx = UInt64(line.dropFirst("tx_bytes=".count)) ?? 0
                        return (partialResult.rx, partialResult.tx + additionalTx)
                    }

                    return partialResult
                })

                continuation.resume(returning: bytesTransmitted)
            }
        }
    }

    /// Retrieves the number of seconds of the most recent handshake for the previously added peer entry, expressed relative to the Unix epoch.
    ///
    /// - Throws: ConfigReadingError
    /// - Returns: Interval between the most recent handshake and the Unix epoch.
    ///
    func getMostRecentHandshake() async throws -> TimeInterval {
        try await withCheckedThrowingContinuation { continuation in
            getRuntimeConfiguration { configuration in
                guard let configuration = configuration else {
                    continuation.resume(throwing: GetBytesTransmittedError.couldNotObtainAdapterConfiguration)
                    return
                }

                var numberOfSeconds = UInt64(0)
                let lines = configuration.components(separatedBy: .newlines)
                for line in lines where line.hasPrefix(ConfigurationFields.mostRecentHandshake.configLinePrefix) {
                    numberOfSeconds = UInt64(line.dropFirst(ConfigurationFields.mostRecentHandshake.configLinePrefix.count)) ?? 0
                    break
                }

                continuation.resume(returning: TimeInterval(numberOfSeconds))
            }
        }
    }

    /// Returns a runtime configuration from WireGuard.
    /// - Parameter completionHandler: completion handler.
    func getRuntimeConfiguration(completionHandler: @escaping (String?) -> Void) {
        workQueue.async {
            guard case .started(let handle, _) = self.state else {
                completionHandler(nil)
                return
            }

            if let settings = self.wireGuardInterface.getConfig(handle: handle) {
                completionHandler(String(cString: settings))
                free(settings)
            } else {
                completionHandler(nil)
            }
        }
    }

    /// Start the tunnel.
    /// - Parameters:
    ///   - tunnelConfiguration: tunnel configuration.
    ///   - completionHandler: completion handler.
    func start(tunnelConfiguration: TunnelConfiguration, completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        workQueue.async {
            guard self.state.canStartAdapter else {
                completionHandler(.invalidState(.alreadyStarted))
                return
            }

            let networkMonitor = self.pathMonitorProvider()
            networkMonitor.pathUpdateHandler = { [weak self] status in
                self?.didReceivePathUpdate(status: status)
            }
            networkMonitor.start(queue: self.workQueue)

            do {
                let settingsGenerator = try self.makeSettingsGenerator(with: tunnelConfiguration)
                try self.setNetworkSettings(settingsGenerator.generateNetworkSettings())

                let (wgConfig, resolutionResults) = settingsGenerator.uapiConfiguration()
                self.logEndpointResolutionResults(resolutionResults)

                Logger.networkProtection.debug("UAPI configuration is \(String(reflecting: wgConfig), privacy: .public)")

                self.state = .started(
                    try self.startWireGuardBackend(wgConfig: wgConfig),
                    settingsGenerator
                )
                self.networkMonitor = networkMonitor
                completionHandler(nil)
            } catch let error as WireGuardAdapterError {
                networkMonitor.cancel()
                completionHandler(error)
            } catch {
                fatalError()
            }
        }
    }

    /// Stop the tunnel.
    /// - Parameter completionHandler: completion handler.
    func stop(completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        workQueue.async {
            Logger.networkProtection.debug("Stopping: \(self.state.debugDescription)")
            switch self.state {
            case .started(let handle, _):
                self.wireGuardInterface.turnOff(handle: handle)

            case .temporaryShutdown, .snoozing:
                break

            case .stopped:
                completionHandler(.invalidState(.alreadyStopped))
                return
            }

            self.networkMonitor?.cancel()
            self.networkMonitor = nil

            self.state = .stopped

            completionHandler(nil)
        }
    }

    func snooze(completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        workQueue.async {
            switch self.state {
            case .started(let handle, _):
                self.wireGuardInterface.turnOff(handle: handle)

            case .temporaryShutdown, .snoozing:
                break

            case .stopped:
                completionHandler(.invalidState(.alreadyStopped))
                return
            }

            self.networkMonitor?.cancel()
            self.networkMonitor = nil

            self.state = .snoozing

            try? self.setNetworkSettings(nil)

            completionHandler(nil)
        }
    }

    /// Update runtime configuration.
    /// - Parameters:
    ///   - tunnelConfiguration: tunnel configuration.
    ///   - reassert: whether the connection should reassert or not.
    ///   - completionHandler: completion handler.
    func update(tunnelConfiguration: TunnelConfiguration,
                reassert: Bool = true,
                completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        workQueue.async {
            if case .stopped = self.state {
                completionHandler(.invalidState(.updatedTunnelWhileStopped))
                return
            }

            if reassert {
                self.packetTunnelProvider?.reasserting = true
            }

            defer {
                if reassert {
                    self.packetTunnelProvider?.reasserting = false
                }
            }

            do {
                let settingsGenerator = try self.makeSettingsGenerator(with: tunnelConfiguration)
                let settings = settingsGenerator.generateNetworkSettings()

                Logger.networkProtection.debug("Updating network settings: \(String(reflecting: settings), privacy: .public)")
                try self.setNetworkSettings(settings)

                switch self.state {
                case .started(let handle, _):
                    let (wgConfig, resolutionResults) = settingsGenerator.uapiConfiguration()
                    self.logEndpointResolutionResults(resolutionResults)

                    Logger.networkProtection.debug("UAPI configuration is \(String(reflecting: wgConfig), privacy: .public)")

                    let result = self.wireGuardInterface.setConfig(handle: handle, config: wgConfig)

                    if result < 0 {
                        let error = NSError(domain: WireGuardAdapterError.wireguardAdapterDomain, code: Int(result))
                        throw WireGuardAdapterError.setWireguardConfig(error)
                    }

                    #if os(iOS)
                    self.wireGuardInterface.disableSomeRoamingForBrokenMobileSemantics(handle: handle)
                    #endif

                    self.state = .started(handle, settingsGenerator)

                case .temporaryShutdown:
                    self.state = .temporaryShutdown(settingsGenerator)

                case .snoozing:
                    assertionFailure("Attempted to update WireGuard adapter while snoozing")

                case .stopped:
                    fatalError()
                }

                completionHandler(nil)
            } catch let error as WireGuardAdapterError {
                completionHandler(error)
            } catch {
                fatalError()
            }
        }
    }

    // MARK: - Private methods

    /// Setup WireGuard log handler.
    private func setupLogHandler() {
        let loggerFunction: @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void = { adapter, logLevel, message in
            guard let adapter = adapter, let message = message else { return }

            let unretainedSelf = Unmanaged<WireGuardAdapter>.fromOpaque(adapter)
                .takeUnretainedValue()

            let swiftString = String(cString: message).trimmingCharacters(in: .newlines)
            let tunnelLogLevel = WireGuardLogLevel(rawValue: logLevel) ?? .verbose

            unretainedSelf.logHandler(tunnelLogLevel, swiftString)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        wireGuardInterface.setLogger(context: context, logFunction: loggerFunction)
    }

    /// Set network tunnel configuration.
    /// This method ensures that the call to `setTunnelNetworkSettings` does not time out, as in
    /// certain scenarios the completion handler given to it may not be invoked by the system.
    ///
    /// - Parameters:
    ///   - networkSettings: an instance of type `NEPacketTunnelNetworkSettings`.
    /// - Throws: an error of type `WireGuardAdapterError`.
    private func setNetworkSettings(_ networkSettings: NEPacketTunnelNetworkSettings?) throws {

        guard let packetTunnelProvider else {
            // If there's no packet tunnel provider it means the tunnel is either shut down
            // or shutting down.
            return
        }

        var systemError: Error?
        let condition = NSCondition()

        // Activate the condition
        condition.lock()
        defer { condition.unlock() }

        packetTunnelProvider.setTunnelNetworkSettings(networkSettings) { error in
            systemError = error
            condition.signal()
        }

        // Packet tunnel's `setTunnelNetworkSettings` times out in certain
        // scenarios & never calls the given callback.
        let setTunnelNetworkSettingsTimeout: TimeInterval = 5 // seconds

        if condition.wait(until: Date().addingTimeInterval(setTunnelNetworkSettingsTimeout)) {
            if let systemError = systemError {
                throw WireGuardAdapterError.setNetworkSettings(systemError)
            }
        } else {
            self.logHandler(.error, "setTunnelNetworkSettings timed out after 5 seconds; proceeding anyway")
        }
    }

    /// Resolve peers of the given tunnel configuration.
    /// - Parameter tunnelConfiguration: tunnel configuration.
    /// - Throws: an error of type `WireGuardAdapterError`.
    /// - Returns: The list of resolved endpoints.
    private func resolvePeers(for tunnelConfiguration: TunnelConfiguration) throws -> [Endpoint?] {
        let endpoints = tunnelConfiguration.peers.map { $0.endpoint }
        let resolutionResults = dnsResolver.resolveSync(endpoints: endpoints)
        let resolutionErrors = resolutionResults.compactMap { result -> DNSResolutionError? in
            if case .failure(let error) = result {
                return error
            } else {
                return nil
            }
        }
        assert(endpoints.count == resolutionResults.count)
        guard resolutionErrors.isEmpty else {
            throw WireGuardAdapterError.dnsResolution(resolutionErrors)
        }

        let resolvedEndpoints = resolutionResults.map { result -> Endpoint? in
            // swiftlint:disable:next force_try
            return try! result?.get()
        }

        return resolvedEndpoints
    }

    /// Start WireGuard backend.
    /// - Parameter wgConfig: WireGuard configuration
    /// - Throws: an error of type `WireGuardAdapterError`
    /// - Returns: tunnel handle
    private func startWireGuardBackend(wgConfig: String) throws -> Int32 {
        guard let tunnelFileDescriptor = tunnelFileDescriptorProvider.currentFileDescriptor() else {
            throw WireGuardAdapterError.cannotLocateTunnelFileDescriptor
        }

        let handle = wireGuardInterface.turnOn(settings: wgConfig, handle: tunnelFileDescriptor)
        if handle < 0 {
            let error = NSError(domain: WireGuardAdapterError.wireguardAdapterDomain,
                                code: Int(handle))
            throw WireGuardAdapterError.startWireGuardBackend(error)
        }
        #if os(iOS)
        wireGuardInterface.disableSomeRoamingForBrokenMobileSemantics(handle: handle)
        #endif
        return handle
    }

    /// Resolves the hostnames in the given tunnel configuration and return settings generator.
    /// - Parameter tunnelConfiguration: an instance of type `TunnelConfiguration`.
    /// - Throws: an error of type `WireGuardAdapterError`.
    /// - Returns: an instance conforming to `PacketTunnelSettingsGenerating`.
    private func makeSettingsGenerator(with tunnelConfiguration: TunnelConfiguration) throws -> PacketTunnelSettingsGenerating {
        return packetTunnelSettingsGeneratorProvider(
            tunnelConfiguration,
            try self.resolvePeers(for: tunnelConfiguration)
        )
    }

    /// Log DNS resolution results.
    /// - Parameter resolutionErrors: an array of type `[DNSResolutionError]`.
    private func logEndpointResolutionResults(_ resolutionResults: [EndpointResolutionResult?]) {
        for case .some(let result) in resolutionResults {
            switch result {
            case .success((let sourceEndpoint, let resolvedEndpoint)):
                if sourceEndpoint.host == resolvedEndpoint.host {
                    self.logHandler(.verbose, "DNS64: mapped \(sourceEndpoint.host) to itself.")
                } else {
                    self.logHandler(.verbose, "DNS64: mapped \(sourceEndpoint.host) to \(resolvedEndpoint.host)")
                }
            case .failure(let resolutionError):
                self.logHandler(.error, "Failed to resolve endpoint \(resolutionError.address): \(resolutionError.errorDescription ?? "(nil)")")
            }
        }
    }

    /// Helper method used by network path monitor.
    /// - Parameter status: new network status
    private func didReceivePathUpdate(status: Network.NWPath.Status) {
        self.logHandler(.verbose, "Network change detected with \(status) route")

        #if os(macOS)
        if case .started(let handle, _) = self.state {
            wireGuardInterface.bumpSockets(handle: handle)
        }
        #elseif os(iOS)
        switch self.state {
        case .started(let handle, let settingsGenerator):
            if status.isSatisfiable {
                let (wgConfig, resolutionResults) = settingsGenerator.endpointUapiConfiguration()
                self.logEndpointResolutionResults(resolutionResults)

                _ = self.wireGuardInterface.setConfig(handle: handle, config: wgConfig)
                self.wireGuardInterface.disableSomeRoamingForBrokenMobileSemantics(handle: handle)
                self.wireGuardInterface.bumpSockets(handle: handle)
            } else {
                self.logHandler(.verbose, "Connectivity offline, pausing backend.")

                self.state = .temporaryShutdown(settingsGenerator)
                self.temporaryShutdownRecoveryFailed = false
                self.wireGuardInterface.turnOff(handle: handle)
            }

        case .temporaryShutdown(let settingsGenerator):
            guard status.isSatisfiable else { return }

            self.logHandler(.verbose, "Connectivity online, resuming backend.")

            do {
                try self.setNetworkSettings(settingsGenerator.generateNetworkSettings())

                let (wgConfig, resolutionResults) = settingsGenerator.uapiConfiguration()
                self.logEndpointResolutionResults(resolutionResults)

                self.state = .started(
                    try self.startWireGuardBackend(wgConfig: wgConfig),
                    settingsGenerator
                )

                if self.temporaryShutdownRecoveryFailed {
                    self.eventHandler.handle(.endTemporaryShutdownStateRecoverySuccess)
                }

                self.temporaryShutdownRecoveryFailed = false
            } catch {
                self.logHandler(.error, "Failed to restart backend: \(error.localizedDescription)")

                if self.temporaryShutdownRecoveryFailed {
                    self.eventHandler.handle(.endTemporaryShutdownStateRecoveryFailure(error))
                } else {
                    self.eventHandler.handle(.endTemporaryShutdownStateAttemptFailure(error))
                    self.temporaryShutdownRecoveryFailed = true
                }
            }

        case .stopped, .snoozing:
            // no-op
            break
        }
        #else
        #error("Unsupported")
        #endif
    }
}

/// A enum describing WireGuard log levels defined in `api-apple.go`.
enum WireGuardLogLevel: Int32 {
    case verbose = 0
    case error = 1
}

private extension Network.NWPath.Status {
    /// Returns `true` if the path is potentially satisfiable.
    var isSatisfiable: Bool {
        switch self {
        case .requiresConnection, .satisfied:
            return true
        case .unsatisfied:
            return false
        @unknown default:
            return true
        }
    }
}
