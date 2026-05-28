//
//  NetworkProtectionVPNSettingsViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import CombineExtensions
import ConcurrencyExtensions
import Foundation
import UserNotifications
import VPN
import BrowserServicesKit
import Core

enum NetworkProtectionNotificationsViewKind: Equatable {
    case loading
    case unauthorized
    case authorized
}

final class NetworkProtectionVPNSettingsViewModel: ObservableObject {
    private let controller: TunnelController
    private let settings: VPNSettings
    private let featureFlagger: FeatureFlagger
    private var cancellables: Set<AnyCancellable> = []

    var isStrictRoutingAvailable: Bool {
        featureFlagger.isFeatureOn(.vpnStrictRouting)
    }

    private var notificationsAuthorization: NotificationsAuthorizationControlling
    @Published var viewKind: NetworkProtectionNotificationsViewKind = .loading

    var alertsEnabled: Bool {
        self.settings.notifyStatusChanges
    }

    @Published public var excludeLocalNetworks: Bool {
        didSet {
            guard oldValue != excludeLocalNetworks else {
                return
            }

            settings.excludeLocalNetworks = excludeLocalNetworks

            Task {
                // We need to allow some time for the setting to propagate
                // But ultimately this should actually be a user choice
                try await Task.sleep(interval: 0.1)
                try await controller.command(.restartAdapter)
            }
        }
    }

    @Published public var enforceRoutes: Bool {
        didSet {
            guard oldValue != enforceRoutes else {
                return
            }

            settings.enforceRoutes = enforceRoutes

            Task {
                try await Task.sleep(interval: 0.1)
                try await controller.command(.restartAdapter)
            }
        }
    }

    @Published public var usesCustomDNS = false
    @Published public var dnsServers: String = UserText.vpnSettingDNSServerDefaultValue

    init(notificationsAuthorization: NotificationsAuthorizationControlling,
         controller: TunnelController,
         settings: VPNSettings,
         featureFlagger: FeatureFlagger) {

        self.controller = controller
        self.featureFlagger = featureFlagger

        // If the feature flag is off, force the stored value back to its default so the
        // tunnel never honors a value set while the flag was on for this user.
        if !featureFlagger.isFeatureOn(.vpnStrictRouting), settings.enforceRoutes != UserDefaults.enforceRoutesDefaultValue {
            settings.enforceRoutes = UserDefaults.enforceRoutesDefaultValue
        }

        self.excludeLocalNetworks = settings.excludeLocalNetworks
        self.enforceRoutes = settings.enforceRoutes
        self.settings = settings
        self.notificationsAuthorization = notificationsAuthorization

        settings.excludeLocalNetworksPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.excludeLocalNetworks, onWeaklyHeld: self)
            .store(in: &cancellables)
        settings.enforceRoutesPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.enforceRoutes, onWeaklyHeld: self)
            .store(in: &cancellables)
        settings.dnsSettingsPublisher
            .receive(on: DispatchQueue.main)
            .map { $0.usesCustomDNS }
            .assign(to: \.usesCustomDNS, onWeaklyHeld: self)
            .store(in: &cancellables)
        settings.dnsSettingsPublisher
            .receive(on: DispatchQueue.main)
            .map { String(describing: $0) }
            .assign(to: \.dnsServers, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    @MainActor
    func onViewAppeared() async {
        let status = await notificationsAuthorization.authorizationStatus
        updateViewKind(for: status)
    }

    func turnOnNotifications() {
        notificationsAuthorization.requestAlertAuthorization()
    }

    func didToggleAlerts(to enabled: Bool) {
        settings.notifyStatusChanges = enabled
    }

    private static func localizedString(forRegionCode: String) -> String {
        Locale.current.localizedString(forRegionCode: forRegionCode) ?? forRegionCode.capitalized
    }

    private func updateViewKind(for authorizationStatus: UNAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined, .denied:
            viewKind = .unauthorized
        case .authorized, .ephemeral, .provisional:
            viewKind = .authorized
        @unknown default:
            assertionFailure("Unhandled enum case")
        }
    }
}

extension NetworkProtectionVPNSettingsViewModel: NotificationsPermissionsControllerDelegate {
    func authorizationStateDidChange(toStatus status: UNAuthorizationStatus) {
        updateViewKind(for: status)
    }
}
