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

@MainActor
final class SubscriptionOnboardingVPNActivationViewModel: ObservableObject {

    enum ConnectionState: Equatable {
        case off
        case on
    }

    typealias ConnectionInfoState = SubscriptionOnboardingPrefetcher.FetchState<SubscriptionOnboardingConnectionInfo>

    static let ipPlaceholder = "-.-.-"
    static let locationPlaceholder = "-,-"

    @Published private(set) var connectionState: ConnectionState

    @Published private(set) var originalConnectionInfo: ConnectionInfoState = .idle
    @Published private(set) var vpnServerInfo: NetworkProtectionStatusServerInfo = .unknown
    @Published private(set) var didDenyVPNPermission = false
    @Published private(set) var didFailToStartVPN = false

    private let prefetcher: SubscriptionOnboardingPrefetcher
    private let vpnController: SubscriptionOnboardingVPNControlling
    private let vpnLocationProvider: SubscriptionOnboardingVPNLocationProviding
    private let serverInfoObserver: ConnectionServerInfoObserver
    private let errorObserver: ConnectionErrorObserver
    private let onComplete: () -> Void
    private let onNext: () -> Void
    private let locale: Locale

    private var hasReportedCompletion = false
    private var hasAttemptedActivation = false
    private var cancellables = Set<AnyCancellable>()

    init(prefetcher: SubscriptionOnboardingPrefetcher,
         vpnController: SubscriptionOnboardingVPNControlling = DefaultSubscriptionOnboardingVPNController(),
         vpnLocationProvider: SubscriptionOnboardingVPNLocationProviding = DefaultSubscriptionOnboardingVPNLocationProvider(),
         serverInfoObserver: ConnectionServerInfoObserver = AppDependencyProvider.shared.serverInfoObserver,
         errorObserver: ConnectionErrorObserver = AppDependencyProvider.shared.connectionErrorObserver,
         onComplete: @escaping () -> Void = {},
         onNext: @escaping () -> Void = {},
         locale: Locale = .current) {
        self.prefetcher = prefetcher
        self.vpnController = vpnController
        self.vpnLocationProvider = vpnLocationProvider
        self.serverInfoObserver = serverInfoObserver
        self.errorObserver = errorObserver
        self.onComplete = onComplete
        self.onNext = onNext
        self.locale = locale
        self.connectionState = vpnController.isConnected ? .on : .off
    }

    // MARK: - Display values

    var didFailActivation: Bool { didDenyVPNPermission || didFailToStartVPN }

    var originalIPText: String { ipText(for: originalConnectionInfo) }
    var originalLocationText: String { locationText(for: originalConnectionInfo) }
    var vpnIPText: String { vpnServerInfo.serverAddress ?? Self.ipPlaceholder }

    var vpnLocationText: String {
        guard let attributes = vpnServerInfo.serverLocation else { return Self.locationPlaceholder }
        return SubscriptionOnboardingConnectionInfo.displayLocation(city: attributes.city,
                                                                    country: attributes.country,
                                                                    locale: locale)
    }

    var vpnLocationNearestIndicator: String? {
        guard vpnServerInfo.serverLocation != nil, vpnLocationProvider.isNearestSelected else { return nil }
        return UserText.netPVPNLocationNearest
    }

    private func ipText(for state: ConnectionInfoState) -> String {
        guard case .loaded(let info) = state else { return Self.ipPlaceholder }
        return info.ip
    }

    private func locationText(for state: ConnectionInfoState) -> String {
        guard case .loaded(let info) = state else { return Self.locationPlaceholder }
        return info.displayLocation(locale: locale)
    }

    // MARK: - Actions

    func onAppear() {
        observeConnection()
        switch connectionState {
        case .off:
            prefetcher.fetchConnectionInfoIfNeeded()
        case .on:
            reportCompletionIfNeeded()
        }
    }

    func onDisappear() {
        cancellables.removeAll()
    }

    func advance() {
        onNext()
    }

    func turnOnVPN() async {
        hasAttemptedActivation = true
        await vpnController.start()
    }

    /// Whether a VPN configuration is already installed. When it isn't, starting shows the system permission prompt
    func isVPNConfigured() async -> Bool {
        await vpnController.isVPNConfigured()
    }

    // MARK: - Connection observing

    private func observeConnection() {
        guard cancellables.isEmpty else { return }
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
                self?.didFailToStartVPN = false
            }
            .store(in: &cancellables)

        // Both sources replay their current value on subscription, so each drops its own
        Publishers.Merge(vpnController.controllerErrorPublisher.dropFirst(),
                         errorObserver.publisher.dropFirst())
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.hasAttemptedActivation == true else { return }
                self?.didFailToStartVPN = true
                self?.didDenyVPNPermission = false
            }
            .store(in: &cancellables)

        serverInfoObserver.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serverInfo in
                self?.vpnServerInfo = serverInfo
            }
            .store(in: &cancellables)

        prefetcher.$connectionInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.originalConnectionInfo = state
            }
            .store(in: &cancellables)
    }

    private func handleConnectionChange(isConnected: Bool) {
        let newState: ConnectionState = isConnected ? .on : .off
        guard newState != connectionState else { return }

        connectionState = newState
        if isConnected {
            didDenyVPNPermission = false
            didFailToStartVPN = false
            reportCompletionIfNeeded()
        }
    }

    private func reportCompletionIfNeeded() {
        guard !hasReportedCompletion else { return }
        hasReportedCompletion = true
        onComplete()
    }
}

// MARK: - VPN controller seam

protocol SubscriptionOnboardingVPNControlling {
    var isConnected: Bool { get }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }
    var configurationDeniedPublisher: AnyPublisher<Void, Never> { get }
    var controllerErrorPublisher: AnyPublisher<String?, Never> { get }
    func start() async
    func isVPNConfigured() async -> Bool
}

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

    var controllerErrorPublisher: AnyPublisher<String?, Never> {
        tunnelController.controllerErrorPublisher
    }

    func start() async {
        await tunnelController.start()
    }

    func isVPNConfigured() async -> Bool {
        await tunnelController.isConfigurationInstalled
    }
}

private extension ConnectionStatus {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - VPN location seam

protocol SubscriptionOnboardingVPNLocationProviding {
    var isNearestSelected: Bool { get }
}

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

struct PreviewSubscriptionOnboardingVPNController: SubscriptionOnboardingVPNControlling {
    let isConnected: Bool

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        Just(isConnected).eraseToAnyPublisher()
    }

    var configurationDeniedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    var controllerErrorPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }

    func start() async {}

    func isVPNConfigured() async -> Bool { false }
}

struct RevealPreviewSubscriptionOnboardingVPNController: SubscriptionOnboardingVPNControlling {
    private let subject = CurrentValueSubject<Bool, Never>(false)

    var isConnected: Bool { subject.value }

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    var configurationDeniedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    var controllerErrorPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }

    func start() async {
        subject.send(true)
    }

    func isVPNConfigured() async -> Bool { false }
}

struct PreviewSubscriptionOnboardingConnectionInfoService: SubscriptionOnboardingConnectionInfoService {
    func fetchConnectionInfo() async throws -> SubscriptionOnboardingConnectionInfo {
        throw CancellationError()
    }
}

struct PreviewConnectionErrorObserver: ConnectionErrorObserver {
    var publisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var recentValue: String? { nil }
}

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
    static func preview(state: ConnectionState,
                        originalConnectionInfo: SubscriptionOnboardingConnectionInfo?,
                        vpnConnectionInfo: SubscriptionOnboardingConnectionInfo? = nil,
                        isNearestSelected: Bool = false,
                        didDenyVPNPermission: Bool = false,
                        didFailToStartVPN: Bool = false) -> SubscriptionOnboardingVPNActivationViewModel {
        let serverInfo = NetworkProtectionStatusServerInfo.previewServerInfo(vpnConnectionInfo)
        let viewModel = SubscriptionOnboardingVPNActivationViewModel(
            prefetcher: .preview(connectionInfo: originalConnectionInfo.map(ConnectionInfoState.loaded) ?? .loading),
            vpnController: PreviewSubscriptionOnboardingVPNController(isConnected: state == .on),
            vpnLocationProvider: PreviewSubscriptionOnboardingVPNLocationProvider(isNearestSelected: isNearestSelected),
            serverInfoObserver: PreviewConnectionServerInfoObserver(serverInfo),
            errorObserver: PreviewConnectionErrorObserver(),
            locale: Locale(identifier: "en_US"))
        viewModel.originalConnectionInfo = originalConnectionInfo.map(ConnectionInfoState.loaded) ?? .loading
        viewModel.vpnServerInfo = serverInfo
        viewModel.didDenyVPNPermission = didDenyVPNPermission
        viewModel.didFailToStartVPN = didFailToStartVPN
        return viewModel
    }

    static func previewReveal(original: SubscriptionOnboardingConnectionInfo?,
                              vpn: SubscriptionOnboardingConnectionInfo?,
                              isNearestSelected: Bool = false) -> SubscriptionOnboardingVPNActivationViewModel {
        let serverInfo = NetworkProtectionStatusServerInfo.previewServerInfo(vpn)
        let viewModel = SubscriptionOnboardingVPNActivationViewModel(
            prefetcher: .preview(connectionInfo: original.map(ConnectionInfoState.loaded) ?? .loading),
            vpnController: RevealPreviewSubscriptionOnboardingVPNController(),
            vpnLocationProvider: PreviewSubscriptionOnboardingVPNLocationProvider(isNearestSelected: isNearestSelected),
            serverInfoObserver: PreviewConnectionServerInfoObserver(serverInfo),
            errorObserver: PreviewConnectionErrorObserver(),
            locale: Locale(identifier: "en_US"))
        viewModel.originalConnectionInfo = original.map(ConnectionInfoState.loaded) ?? .loading
        viewModel.vpnServerInfo = serverInfo
        return viewModel
    }
}

#endif
