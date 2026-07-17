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

    /// The real (pre-VPN) connection, fetched while off and cached; `nil` until the fetch resolves.
    @Published private(set) var realConnectionInfo: SubscriptionOnboardingConnectionInfo?
    /// The VPN egress connection, fetched once connected; `nil` until then.
    @Published private(set) var vpnConnectionInfo: SubscriptionOnboardingConnectionInfo?

    private let connectionInfoService: SubscriptionOnboardingConnectionInfoService
    private let vpnController: SubscriptionOnboardingVPNControlling
    private weak var delegate: SubscriptionOnboardingSectionDelegate?
    private let locale: Locale

    private var hasReportedCompletion = false
    private var cancellables = Set<AnyCancellable>()

    init(connectionInfoService: SubscriptionOnboardingConnectionInfoService = DefaultSubscriptionOnboardingConnectionInfoService(),
         vpnController: SubscriptionOnboardingVPNControlling = DefaultSubscriptionOnboardingVPNController(),
         delegate: SubscriptionOnboardingSectionDelegate? = nil,
         locale: Locale = .current) {
        self.connectionInfoService = connectionInfoService
        self.vpnController = vpnController
        self.delegate = delegate
        self.locale = locale
        self.connectionState = vpnController.isConnected ? .on : .off

        observeConnection()
    }

    // MARK: - Display values

    var realIPText: String { realConnectionInfo?.ip ?? Self.placeholder }
    var realLocationText: String { realConnectionInfo?.displayLocation(locale: locale) ?? Self.placeholder }
    var vpnIPText: String { vpnConnectionInfo?.ip ?? Self.placeholder }
    var vpnLocationText: String { vpnConnectionInfo?.displayLocation(locale: locale) ?? Self.placeholder }

    // MARK: - Actions

    /// Fetches the real connection info once, while off. Called from the view's `.task`; a failure leaves
    /// the placeholders in place rather than surfacing an error on this screen.
    @MainActor
    func onAppear() async {
        guard realConnectionInfo == nil else { return }
        realConnectionInfo = try? await connectionInfoService.fetchConnectionInfo()
    }

    /// Starts the VPN. The off→on transition is driven by the connection observer, not this call, so the
    /// screen reflects the real tunnel state rather than an optimistic guess.
    @MainActor
    func turnOnVPN() async {
        await vpnController.start()
    }

    /// Fetches the VPN (egress) connection info once. Driven by the view when the screen enters the on
    /// state; a failure leaves the placeholder in place rather than surfacing an error on this screen.
    @MainActor
    func refreshVPNConnectionInfo() async {
        guard vpnConnectionInfo == nil else { return }
        vpnConnectionInfo = try? await connectionInfoService.fetchConnectionInfo()
    }

    // MARK: - Connection observing

    private func observeConnection() {
        vpnController.isConnectedPublisher
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
    func start() async
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
}

private extension ConnectionStatus {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
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
}

/// A no-network connection-info service for previews: never resolves, so seeded values stand.
struct PreviewSubscriptionOnboardingConnectionInfoService: SubscriptionOnboardingConnectionInfoService {
    func fetchConnectionInfo() async throws -> SubscriptionOnboardingConnectionInfo {
        throw CancellationError()
    }
}

extension SubscriptionOnboardingVPNActivationViewModel {
    /// A view model seeded with fixed connection info for previews — no network, no tunnel. Pass `nil`
    /// connection info to preview the loading state (the info cards render the `-` placeholder).
    static func preview(state: ConnectionState,
                        realConnectionInfo: SubscriptionOnboardingConnectionInfo?,
                        vpnConnectionInfo: SubscriptionOnboardingConnectionInfo? = nil) -> SubscriptionOnboardingVPNActivationViewModel {
        let viewModel = SubscriptionOnboardingVPNActivationViewModel(
            connectionInfoService: PreviewSubscriptionOnboardingConnectionInfoService(),
            vpnController: PreviewSubscriptionOnboardingVPNController(isConnected: state == .on),
            locale: Locale(identifier: "en_US"))
        viewModel.realConnectionInfo = realConnectionInfo
        viewModel.vpnConnectionInfo = vpnConnectionInfo
        return viewModel
    }
}

#endif
