//
//  SubscriptionOnboardingVPNActivationViewModel.swift
//  DuckDuckGo
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

import Combine
import Foundation
import VPN

/// Drives the VPN activation screen (the same screen in two states: off and on). It fetches the original
/// connection info while off (caching it as the "hidden" card once on), starts the VPN through the
/// injected controller, and — when the tunnel reaches connected — describes the new (egress) IP and location
/// from the shared server-info observer (the same source the VPN settings screen reads) and reports
/// completion up to the flow via ``SubscriptionOnboardingSectionDelegate``.
final class SubscriptionOnboardingVPNActivationViewModel: ObservableObject {

    /// The two states of the single activation screen.
    enum ConnectionState: Equatable {
        case off
        case on
    }

    /// The lifecycle of one connection-info fetch, kept as its own axis separate from ``ConnectionState`` so
    /// the two orthogonal concerns — what the user/tunnel is doing vs. whether the IP lookup has resolved —
    /// are never squeezed into one combined state.
    enum ConnectionInfoState: Equatable {
        case idle
        case loading
        case loaded(SubscriptionOnboardingConnectionInfo)
        case failed

        /// A fetch should (re)start only when nothing is in flight or already resolved; a prior failure is
        /// retried on the next appearance, mirroring the previous "retry while still unresolved" behavior.
        var shouldStartFetch: Bool {
            switch self {
            case .idle, .failed: return true
            case .loading, .loaded: return false
            }
        }
    }

    /// Shown in the IP row of an info card until the corresponding fetch resolves (or when it has no value,
    /// e.g. entering with the VPN already on, which never fetches the original IP).
    static let ipPlaceholder = "-.-.-"
    /// Shown in the location row of an info card until the corresponding fetch resolves.
    static let locationPlaceholder = "-,-"

    @Published private(set) var connectionState: ConnectionState

    /// The original (pre-VPN) connection, fetched while off and retained.
    @Published private(set) var originalConnectionInfo: ConnectionInfoState = .idle
    /// The VPN egress server info (address + location) from the shared server-info observer — the same source
    /// the VPN settings screen reads. Address and location are read independently, matching that screen.
    @Published private(set) var vpnServerInfo: NetworkProtectionStatusServerInfo = .unknown

    /// Whether the customer declined the system VPN-configuration prompt, observed from the controller's
    /// configuration-denied signal. Persists across retries and clears once the tunnel connects.
    @Published private(set) var didDenyVPNPermission = false

    private let connectionInfoService: SubscriptionOnboardingConnectionInfoService
    private let vpnController: SubscriptionOnboardingVPNControlling
    private let vpnLocationProvider: SubscriptionOnboardingVPNLocationProviding
    private let serverInfoObserver: ConnectionServerInfoObserver
    private weak var delegate: SubscriptionOnboardingSectionDelegate?
    private let locale: Locale

    private var hasReportedCompletion = false
    private var cancellables = Set<AnyCancellable>()

    init(connectionInfoService: SubscriptionOnboardingConnectionInfoService = DefaultSubscriptionOnboardingConnectionInfoService(),
         vpnController: SubscriptionOnboardingVPNControlling = DefaultSubscriptionOnboardingVPNController(),
         vpnLocationProvider: SubscriptionOnboardingVPNLocationProviding = DefaultSubscriptionOnboardingVPNLocationProvider(),
         serverInfoObserver: ConnectionServerInfoObserver = AppDependencyProvider.shared.serverInfoObserver,
         delegate: SubscriptionOnboardingSectionDelegate? = nil,
         locale: Locale = .current) {
        self.connectionInfoService = connectionInfoService
        self.vpnController = vpnController
        self.vpnLocationProvider = vpnLocationProvider
        self.serverInfoObserver = serverInfoObserver
        self.delegate = delegate
        self.locale = locale
        self.connectionState = vpnController.isConnected ? .on : .off

        observeConnection()
    }

    // MARK: - Display values

    var originalIPText: String { ipText(for: originalConnectionInfo) }
    var originalLocationText: String { locationText(for: originalConnectionInfo) }
    var vpnIPText: String { vpnServerInfo.serverAddress ?? Self.ipPlaceholder }

    var vpnLocationText: String {
        guard let attributes = vpnServerInfo.serverLocation else { return Self.locationPlaceholder }
        return SubscriptionOnboardingConnectionInfo.displayLocation(city: attributes.city,
                                                                    country: attributes.country,
                                                                    locale: locale)
    }

    /// The "(Nearest)" indicator the existing VPN status/location UI shows when the "nearest available"
    var vpnLocationNearestIndicator: String? {
        guard vpnServerInfo.serverLocation != nil, vpnLocationProvider.isNearestSelected else { return nil }
        return UserText.netPVPNLocationNearest
    }

    /// The IP text for a fetch state: the address once `.loaded`, otherwise the IP placeholder (loading,
    /// failed, or not yet started all read the same on this screen).
    private func ipText(for state: ConnectionInfoState) -> String {
        guard case .loaded(let info) = state else { return Self.ipPlaceholder }
        return info.ip
    }

    /// The location text for a fetch state, following the same placeholder rule as ``ipText(for:)``.
    private func locationText(for state: ConnectionInfoState) -> String {
        guard case .loaded(let info) = state else { return Self.locationPlaceholder }
        return info.displayLocation(locale: locale)
    }

    // MARK: - Actions

    /// Kicks off the appropriate fetch when the view appears, then returns immediately (fire-and-forget)
    func onAppear() {
        switch connectionState {
        case .off:
            fetchOriginalConnectionInfo()
        case .on:
            reportCompletionIfNeeded()
            vpnServerInfo = serverInfoObserver.recentValue
        }
    }

    /// Starts the VPN. Doesn't clear ``didDenyVPNPermission`` — the denied state must survive a retry and
    /// clears only on connect; a denial arrives via the configuration-denied signal (see ``observeConnection()``).
    @MainActor
    func turnOnVPN() async {
        await vpnController.start()
    }

    /// Whether a VPN configuration is already installed. When it isn't, starting shows the system permission prompt
    func isVPNConfigured() async -> Bool {
        await vpnController.isVPNConfigured()
    }

    /// Fetches the original (pre-VPN) IP into ``originalConnectionInfo``.
    private func fetchOriginalConnectionInfo() {
        guard originalConnectionInfo.shouldStartFetch else { return }
        originalConnectionInfo = .loading
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.originalConnectionInfo = .loaded(try await self.connectionInfoService.fetchConnectionInfo())
            } catch {
                self.originalConnectionInfo = .failed
            }
        }
    }

    // MARK: - Connection observing

    private func observeConnection() {
        vpnController.isConnectedPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.handleConnectionChange(isConnected: isConnected)
            }
            .store(in: &cancellables)

        vpnController.configurationDeniedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.didDenyVPNPermission = true
            }
            .store(in: &cancellables)

        serverInfoObserver.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serverInfo in
                self?.vpnServerInfo = serverInfo
            }
            .store(in: &cancellables)
    }

    /// Runs on the main queue (the publisher is delivered there), so the `@Published` mutations are safe.
    private func handleConnectionChange(isConnected: Bool) {
        let newState: ConnectionState = isConnected ? .on : .off
        guard newState != connectionState else { return }

        connectionState = newState
        if isConnected {
            didDenyVPNPermission = false
            reportCompletionIfNeeded()
        }
    }

    private func reportCompletionIfNeeded() {
        guard !hasReportedCompletion else { return }
        hasReportedCompletion = true
        delegate?.sectionDidComplete(.vpn)
    }
}

// MARK: - VPN controller seam

/// The view model's window onto the VPN tunnel: whether it is connected, a stream of that value, and a
/// way to start it. A protocol so previews and tests can drive the off→on transition without the tunnel.
protocol SubscriptionOnboardingVPNControlling {
    var isConnected: Bool { get }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }
    /// Fires when the customer declines the system VPN-configuration prompt.
    var configurationDeniedPublisher: AnyPublisher<Void, Never> { get }
    func start() async
    /// Whether a VPN configuration is already installed. If not, starting triggers the system permission
    /// prompt — used to decide whether to show the "Tap allow" hint.
    func isVPNConfigured() async -> Bool
}

/// The live controller, wrapping the app's existing VPN plumbing: it starts the tunnel through
/// `NetworkProtectionTunnelController` and reports connection state from the shared `ConnectionStatusObserver`.
final class DefaultSubscriptionOnboardingVPNController: SubscriptionOnboardingVPNControlling {
    private let tunnelController: NetworkProtectionTunnelController
    private let connectionObserver: ConnectionStatusObserver

    init(tunnelController: NetworkProtectionTunnelController = AppDependencyProvider.shared.networkProtectionTunnelController,
         connectionObserver: ConnectionStatusObserver = AppDependencyProvider.shared.connectionObserver) {
        self.tunnelController = tunnelController
        self.connectionObserver = connectionObserver
    }

    var isConnected: Bool {
        connectionObserver.recentValue.isConnected
    }

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        connectionObserver.publisher
            .map(\.isConnected)
            .eraseToAnyPublisher()
    }

    var configurationDeniedPublisher: AnyPublisher<Void, Never> {
        tunnelController.configurationDeniedPublisher
    }

    func start() async {
        await tunnelController.start()
    }

    func isVPNConfigured() async -> Bool {
        await tunnelController.isInstalled
    }
}

private extension ConnectionStatus {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - VPN location seam

/// The view model's window onto the selected VPN location: whether the "nearest available" (automatic)
/// location is selected.
protocol SubscriptionOnboardingVPNLocationProviding {
    var isNearestSelected: Bool { get }
}

/// The live provider, reading the shared `VPNSettings` the rest of the VPN UI reads from.
final class DefaultSubscriptionOnboardingVPNLocationProvider: SubscriptionOnboardingVPNLocationProviding {
    private let settings: VPNSettings

    init(settings: VPNSettings = AppDependencyProvider.shared.vpnSettings) {
        self.settings = settings
    }

    var isNearestSelected: Bool {
        settings.selectedLocation == .nearest
    }
}

#if DEBUG

/// A no-tunnel controller for previews: reports a fixed connection state and starts nothing.
struct PreviewSubscriptionOnboardingVPNController: SubscriptionOnboardingVPNControlling {
    let isConnected: Bool

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        Just(isConnected).eraseToAnyPublisher()
    }

    var configurationDeniedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    func start() async {}

    func isVPNConfigured() async -> Bool { false }
}

/// A preview controller that starts disconnected and flips to connected when `start()` is called, so the
/// off→on reveal (and its slide-in) can be exercised in a preview — by the harness that turns the VPN on,
/// or by tapping "Turn On VPN" in a Live Preview.
struct RevealPreviewSubscriptionOnboardingVPNController: SubscriptionOnboardingVPNControlling {
    private let subject = CurrentValueSubject<Bool, Never>(false)

    var isConnected: Bool { subject.value }

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    var configurationDeniedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    func start() async {
        subject.send(true)
    }

    func isVPNConfigured() async -> Bool { false }
}

/// A no-network connection-info service for previews: never resolves, so seeded values stand.
struct PreviewSubscriptionOnboardingConnectionInfoService: SubscriptionOnboardingConnectionInfoService {
    func fetchConnectionInfo() async throws -> SubscriptionOnboardingConnectionInfo {
        throw CancellationError()
    }
}

/// A fixed location provider for previews: reports whether the "nearest available" location is selected.
struct PreviewSubscriptionOnboardingVPNLocationProvider: SubscriptionOnboardingVPNLocationProviding {
    let isNearestSelected: Bool
}

/// A fixed server-info observer for previews: reports a single seeded value, so the egress card renders it
/// through the same path production uses (rather than a live tunnel).
struct PreviewConnectionServerInfoObserver: ConnectionServerInfoObserver {
    let serverInfo: NetworkProtectionStatusServerInfo

    init(_ serverInfo: NetworkProtectionStatusServerInfo = .unknown) {
        self.serverInfo = serverInfo
    }

    var publisher: AnyPublisher<NetworkProtectionStatusServerInfo, Never> { Just(serverInfo).eraseToAnyPublisher() }
    var recentValue: NetworkProtectionStatusServerInfo { serverInfo }
}

private extension NetworkProtectionStatusServerInfo {
    /// Builds egress server info from an onboarding connection-info fixture for previews (``ServerAttributes``
    /// has no public initializer, so city/country are round-tripped through JSON).
    static func previewServerInfo(_ info: SubscriptionOnboardingConnectionInfo?) -> NetworkProtectionStatusServerInfo {
        guard let info else { return .unknown }
        let json = "{\"city\":\"\(info.city)\",\"country\":\"\(info.country)\",\"state\":\"\"}"
        let attributes = try? JSONDecoder().decode(NetworkProtectionServerInfo.ServerAttributes.self, from: Data(json.utf8))
        return NetworkProtectionStatusServerInfo(serverLocation: attributes, serverAddress: info.ip)
    }
}

extension SubscriptionOnboardingVPNActivationViewModel {
    /// A view model seeded with fixed connection info for previews — no network, no tunnel. Pass `nil`
    /// connection info to preview the loading state (the info cards render the placeholders).
    static func preview(state: ConnectionState,
                        originalConnectionInfo: SubscriptionOnboardingConnectionInfo?,
                        vpnConnectionInfo: SubscriptionOnboardingConnectionInfo? = nil,
                        isNearestSelected: Bool = false,
                        didDenyVPNPermission: Bool = false) -> SubscriptionOnboardingVPNActivationViewModel {
        let serverInfo = NetworkProtectionStatusServerInfo.previewServerInfo(vpnConnectionInfo)
        let viewModel = SubscriptionOnboardingVPNActivationViewModel(
            connectionInfoService: PreviewSubscriptionOnboardingConnectionInfoService(),
            vpnController: PreviewSubscriptionOnboardingVPNController(isConnected: state == .on),
            vpnLocationProvider: PreviewSubscriptionOnboardingVPNLocationProvider(isNearestSelected: isNearestSelected),
            serverInfoObserver: PreviewConnectionServerInfoObserver(serverInfo),
            locale: Locale(identifier: "en_US"))
        viewModel.originalConnectionInfo = originalConnectionInfo.map(ConnectionInfoState.loaded) ?? .loading
        viewModel.vpnServerInfo = serverInfo
        viewModel.didDenyVPNPermission = didDenyVPNPermission
        return viewModel
    }

    /// A view model that starts off and transitions to on when the VPN is turned on, for previewing the
    /// off→on reveal. The egress info is seeded so the on-state cards show a value once revealed.
    static func previewReveal(original: SubscriptionOnboardingConnectionInfo?,
                              vpn: SubscriptionOnboardingConnectionInfo?,
                              isNearestSelected: Bool = false) -> SubscriptionOnboardingVPNActivationViewModel {
        let serverInfo = NetworkProtectionStatusServerInfo.previewServerInfo(vpn)
        let viewModel = SubscriptionOnboardingVPNActivationViewModel(
            connectionInfoService: PreviewSubscriptionOnboardingConnectionInfoService(),
            vpnController: RevealPreviewSubscriptionOnboardingVPNController(),
            vpnLocationProvider: PreviewSubscriptionOnboardingVPNLocationProvider(isNearestSelected: isNearestSelected),
            serverInfoObserver: PreviewConnectionServerInfoObserver(serverInfo),
            locale: Locale(identifier: "en_US"))
        viewModel.originalConnectionInfo = original.map(ConnectionInfoState.loaded) ?? .loading
        viewModel.vpnServerInfo = serverInfo
        return viewModel
    }
}

#endif
