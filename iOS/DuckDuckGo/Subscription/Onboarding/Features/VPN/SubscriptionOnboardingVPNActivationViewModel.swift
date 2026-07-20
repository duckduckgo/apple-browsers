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

/// Drives the VPN activation screen (the same screen in two states: off and on). It fetches the real
/// connection info while off (caching it as the "hidden" card once on), starts the VPN through the
/// injected controller, and — when the tunnel reaches connected — re-reads the connection to describe the
/// new (egress) IP and reports completion up to the flow via ``SubscriptionOnboardingSectionDelegate``.
final class SubscriptionOnboardingVPNActivationViewModel: ObservableObject {

    /// The two states of the single activation screen.
    enum ConnectionState: Equatable {
        case off
        case on
    }

    /// Shown in the info cards until the corresponding fetch resolves.
    static let placeholder = "-"

    @Published private(set) var connectionState: ConnectionState

    /// The actual (pre-VPN) connection, fetched while off and cached; `nil` until the fetch resolves.
    @Published private(set) var actualConnectionInfo: SubscriptionOnboardingConnectionInfo?
    /// The VPN egress connection, fetched once connected; `nil` until then.
    @Published private(set) var vpnConnectionInfo: SubscriptionOnboardingConnectionInfo?

    /// Whether the customer most likely declined the system VPN permission prompt. Inferred, not observed:
    /// ``turnOnVPN()`` calls the tunnel controller's non-throwing `start()`, which swallows
    /// `StartError.configSystemPermissionsDenied` (returns early with no thrown error and no error-publisher
    /// signal), so the denial can't be detected directly. We infer it from "the tunnel is still off once
    /// `start()` resolves", and clear it when the connection observer reports connected. Drives the
    /// off-state retry/skip buttons.
    @Published private(set) var didDenyVPNPermission = false

    private let connectionInfoService: SubscriptionOnboardingConnectionInfoService
    private let vpnController: SubscriptionOnboardingVPNControlling
    private let vpnLocationProvider: SubscriptionOnboardingVPNLocationProviding
    private weak var delegate: SubscriptionOnboardingSectionDelegate?
    private let locale: Locale

    private var hasReportedCompletion = false
    private var isFetchingVPNConnectionInfo = false
    private var cancellables = Set<AnyCancellable>()

    init(connectionInfoService: SubscriptionOnboardingConnectionInfoService = DefaultSubscriptionOnboardingConnectionInfoService(),
         vpnController: SubscriptionOnboardingVPNControlling = DefaultSubscriptionOnboardingVPNController(),
         vpnLocationProvider: SubscriptionOnboardingVPNLocationProviding = DefaultSubscriptionOnboardingVPNLocationProvider(),
         delegate: SubscriptionOnboardingSectionDelegate? = nil,
         locale: Locale = .current) {
        self.connectionInfoService = connectionInfoService
        self.vpnController = vpnController
        self.vpnLocationProvider = vpnLocationProvider
        self.delegate = delegate
        self.locale = locale
        self.connectionState = vpnController.isConnected ? .on : .off

        observeConnection()
    }

    // MARK: - Display values

    var realIPText: String { actualConnectionInfo?.ip ?? Self.placeholder }
    var realLocationText: String { actualConnectionInfo?.displayLocation(locale: locale) ?? Self.placeholder }
    var vpnIPText: String { vpnConnectionInfo?.ip ?? Self.placeholder }

    var vpnLocationText: String { vpnConnectionInfo?.displayLocation(locale: locale) ?? Self.placeholder }

    /// The "(Nearest)" indicator the existing VPN status/location UI shows when the "nearest available"
    /// (automatic) location is selected (see ``NetworkProtectionStatusView`` and
    /// ``UserText/netPVPNLocationNearest``); `nil` for a specific location or before the egress info
    /// resolves. Rendered as a separate, `.textSecondary`-tinted run alongside ``vpnLocationText``.
    var vpnLocationNearestIndicator: String? {
        guard vpnConnectionInfo != nil, vpnLocationProvider.isNearestSelected else { return nil }
        return UserText.netPVPNLocationNearest
    }

    // MARK: - Actions

    /// Fetches when the view appears. While off, the real (pre-VPN) IP is fetched and then retained, so the
    /// real-IP row keeps showing it after the VPN comes on. If the tunnel is already on we only fetch the VPN
    /// (egress) IP — the pre-VPN IP can no longer be observed — and report completion. Awaitable so it can be
    /// driven from the view's `.task` (auto-cancelled on disappear) and unit-tested directly. Each value is
    /// fetched at most once; a failure leaves the "-" placeholders in place rather than surfacing an error.
    @MainActor
    func onAppear() async {
        if connectionState == .off, actualConnectionInfo == nil {
            actualConnectionInfo = try? await connectionInfoService.fetchConnectionInfo()
        }
        if connectionState == .on {
            reportCompletionIfNeeded()
            await fetchVPNConnectionInfo()
        }
    }

    /// Starts the VPN. The off→on transition is driven by the connection observer, not this call, so the
    /// screen reflects the real tunnel state rather than an optimistic guess. Once `start()` resolves (which
    /// includes the system permission prompt), a still-off tunnel is taken as an inferred permission denial
    /// — see ``didDenyVPNPermission``.
    @MainActor
    func turnOnVPN() async {
        await vpnController.start()
        didDenyVPNPermission = connectionState == .off
    }

    /// Whether a VPN configuration is already installed. When it isn't, starting shows the system permission
    /// prompt — the view uses this to decide whether to show the "Tap allow" hint.
    func isVPNConfigured() async -> Bool {
        await vpnController.isVPNConfigured()
    }

    /// Fetches the VPN (egress) IP once. Called by ``onAppear()`` if already on, and by the connection
    /// observer when the tunnel transitions to connected. The in-flight guard is set synchronously before
    /// the `await`, so two overlapping callers can't both start a fetch.
    @MainActor
    private func fetchVPNConnectionInfo() async {
        guard vpnConnectionInfo == nil, !isFetchingVPNConnectionInfo else { return }
        isFetchingVPNConnectionInfo = true
        defer { isFetchingVPNConnectionInfo = false }
        vpnConnectionInfo = try? await connectionInfoService.fetchConnectionInfo()
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
    }

    /// Runs on the main queue (the publisher is delivered there), so the `@Published` mutations are safe.
    private func handleConnectionChange(isConnected: Bool) {
        let newState: ConnectionState = isConnected ? .on : .off
        guard newState != connectionState else { return }

        connectionState = newState
        if isConnected {
            didDenyVPNPermission = false
            reportCompletionIfNeeded()
            Task { @MainActor [weak self] in await self?.fetchVPNConnectionInfo() }
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
/// location is selected. Reads the same source-of-truth as the existing VPN status/location UI
/// (`VPNSettings.selectedLocation`, see ``NetworkProtectionLocationStatusModel`` and
/// ``NetworkProtectionVPNLocationViewModel``), so the onboarding egress location can show the same
/// "(Nearest)" indicator. A protocol so previews and tests can drive it without touching `VPNSettings`.
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

extension SubscriptionOnboardingVPNActivationViewModel {
    /// A view model seeded with fixed connection info for previews — no network, no tunnel. Pass `nil`
    /// connection info to preview the loading state (the info cards render the `-` placeholder).
    static func preview(state: ConnectionState,
                        realConnectionInfo: SubscriptionOnboardingConnectionInfo?,
                        vpnConnectionInfo: SubscriptionOnboardingConnectionInfo? = nil,
                        isNearestSelected: Bool = false) -> SubscriptionOnboardingVPNActivationViewModel {
        let viewModel = SubscriptionOnboardingVPNActivationViewModel(
            connectionInfoService: PreviewSubscriptionOnboardingConnectionInfoService(),
            vpnController: PreviewSubscriptionOnboardingVPNController(isConnected: state == .on),
            vpnLocationProvider: PreviewSubscriptionOnboardingVPNLocationProvider(isNearestSelected: isNearestSelected),
            locale: Locale(identifier: "en_US"))
        viewModel.actualConnectionInfo = realConnectionInfo
        viewModel.vpnConnectionInfo = vpnConnectionInfo
        return viewModel
    }

    /// A view model that starts off and transitions to on when the VPN is turned on, for previewing the
    /// off→on reveal. The egress info is seeded so the on-state cards show a value once revealed.
    static func previewReveal(real: SubscriptionOnboardingConnectionInfo?,
                              vpn: SubscriptionOnboardingConnectionInfo?,
                              isNearestSelected: Bool = false) -> SubscriptionOnboardingVPNActivationViewModel {
        let viewModel = SubscriptionOnboardingVPNActivationViewModel(
            connectionInfoService: PreviewSubscriptionOnboardingConnectionInfoService(),
            vpnController: RevealPreviewSubscriptionOnboardingVPNController(),
            vpnLocationProvider: PreviewSubscriptionOnboardingVPNLocationProvider(isNearestSelected: isNearestSelected),
            locale: Locale(identifier: "en_US"))
        viewModel.actualConnectionInfo = real
        viewModel.vpnConnectionInfo = vpn
        return viewModel
    }
}

#endif
