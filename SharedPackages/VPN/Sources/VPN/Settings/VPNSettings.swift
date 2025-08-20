//
//  VPNSettings.swift
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
import Foundation
import Networking

/// Persists and publishes changes to tunnel settings.
///
/// It's strongly recommended to use shared `UserDefaults` to initialize this class, as `VPNSettings`
/// can then detect settings changes using KVO even if they're applied by a different process or even by the user through
/// the command line.
///
public final class VPNSettings {

    public enum Change: Codable {
        case setConnectOnLogin(_ connectOnLogin: Bool)
        case setIncludeAllNetworks(_ includeAllNetworks: Bool)
        case setEnforceRoutes(_ enforceRoutes: Bool)
        case setExcludeLocalNetworks(_ excludeLocalNetworks: Bool)
        case setNotifyStatusChanges(_ notifyStatusChanges: Bool)
        case setRegistrationKeyValidity(_ validity: RegistrationKeyValidity)
        case setSelectedServer(_ selectedServer: SelectedServer)
        case setSelectedLocation(_ selectedLocation: SelectedLocation)
        case setSelectedEnvironment(_ selectedEnvironment: SelectedEnvironment)
        case setDNSSettings(_ dnsSettings: NetworkProtectionDNSSettings)
        case setShowInMenuBar(_ showInMenuBar: Bool)
        case setDisableRekeying(_ disableRekeying: Bool)
    }

    public enum RegistrationKeyValidity: Codable, Equatable {
        case automatic
        case custom(_ timeInterval: TimeInterval)
    }

    public enum SelectedServer: Codable, Equatable {
        case automatic
        case endpoint(String)

        public var stringValue: String? {
            switch self {
            case .automatic: return nil
            case .endpoint(let endpoint): return endpoint
            }
        }
    }

    public enum SelectedLocation: Codable, Equatable {
        case nearest
        case location(NetworkProtectionSelectedLocation)

        public var location: NetworkProtectionSelectedLocation? {
            switch self {
            case .nearest: return nil
            case .location(let location): return location
            }
        }
    }

    public enum SelectedEnvironment: String, Codable {
        case production
        case staging

        public static var `default`: SelectedEnvironment = .production

        public var endpointURL: URL {
            switch self {
            case .production:
                return URL(string: "https://controller.netp.duckduckgo.com")!
            case .staging:
                return URL(string: "https://staging1.netp.duckduckgo.com")!
            }
        }
    }

    private let defaults: UserDefaults

    private(set) public lazy var changePublisher: AnyPublisher<Change, Never> = {

        let connectOnLoginPublisher = connectOnLoginPublisher
            .dropFirst()
            .removeDuplicates()
            .map { connectOnLogin in
                Change.setConnectOnLogin(connectOnLogin)
            }.eraseToAnyPublisher()

        let includeAllNetworksPublisher = includeAllNetworksPublisher
            .dropFirst()
            .removeDuplicates()
            .map { includeAllNetworks in
                Change.setIncludeAllNetworks(includeAllNetworks)
            }.eraseToAnyPublisher()

        let enforceRoutesPublisher = enforceRoutesPublisher
            .dropFirst()
            .removeDuplicates()
            .map { enforceRoutes in
                Change.setEnforceRoutes(enforceRoutes)
            }.eraseToAnyPublisher()

        let excludeLocalNetworksPublisher = excludeLocalNetworksPublisher
            .dropFirst()
            .removeDuplicates()
            .map { excludeLocalNetworks in
                Change.setExcludeLocalNetworks(excludeLocalNetworks)
            }.eraseToAnyPublisher()

        let notifyStatusChangesPublisher = notifyStatusChangesPublisher
            .dropFirst()
            .removeDuplicates()
            .map { notifyStatusChanges in
                Change.setNotifyStatusChanges(notifyStatusChanges)
            }.eraseToAnyPublisher()

        let registrationKeyValidityPublisher = registrationKeyValidityPublisher
            .dropFirst()
            .removeDuplicates()
            .map { validity in
                Change.setRegistrationKeyValidity(validity)
            }.eraseToAnyPublisher()

        let serverChangePublisher = selectedServerPublisher
            .dropFirst()
            .removeDuplicates()
            .map { server in
                Change.setSelectedServer(server)
            }.eraseToAnyPublisher()

        let locationChangePublisher = selectedLocationPublisher
            .dropFirst()
            .removeDuplicates()
            .map { location in
                Change.setSelectedLocation(location)
            }.eraseToAnyPublisher()

        let environmentChangePublisher = selectedEnvironmentPublisher
            .dropFirst()
            .removeDuplicates()
            .map { environment in
                Change.setSelectedEnvironment(environment)
            }.eraseToAnyPublisher()

        let dnsSettingsChangePublisher = dnsSettingsPublisher
            .dropFirst()
            .removeDuplicates()
            .map { settings in
                Change.setDNSSettings(settings)
            }.eraseToAnyPublisher()

        let showInMenuBarPublisher = showInMenuBarPublisher
            .dropFirst()
            .removeDuplicates()
            .map { showInMenuBar in
                Change.setShowInMenuBar(showInMenuBar)
            }.eraseToAnyPublisher()

        let disableRekeyingPublisher = disableRekeyingPublisher
            .dropFirst()
            .removeDuplicates()
            .map { disableRekeying in
                Change.setDisableRekeying(disableRekeying)
            }.eraseToAnyPublisher()

        return Publishers.MergeMany(
            connectOnLoginPublisher,
            includeAllNetworksPublisher,
            enforceRoutesPublisher,
            excludeLocalNetworksPublisher,
            notifyStatusChangesPublisher,
            serverChangePublisher,
            locationChangePublisher,
            environmentChangePublisher,
            dnsSettingsChangePublisher,
            showInMenuBarPublisher,
            disableRekeyingPublisher).eraseToAnyPublisher()
    }()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Resetting to Defaults

    public func resetToDefaults() {
        defaults.resetNetworkProtectionSettingConnectOnLogin()
        defaults.resetNetworkProtectionSettingEnforceRoutes()
        defaults.resetNetworkProtectionSettingExcludeLocalNetworks()
        defaults.resetNetworkProtectionSettingIncludeAllNetworks()
        defaults.resetNetworkProtectionSettingNotifyStatusChanges()
        defaults.resetNetworkProtectionSettingRegistrationKeyValidity()
        defaults.resetNetworkProtectionSettingSelectedServer()
        defaults.resetDNSSettings()
        defaults.resetNetworkProtectionSettingShowInMenuBar()
    }

    // MARK: - Applying Changes

    public func apply(change: Change) {
        switch change {
        case .setConnectOnLogin(let connectOnLogin):
            self.connectOnLogin = connectOnLogin
        case .setEnforceRoutes(let enforceRoutes):
            self.enforceRoutes = enforceRoutes
        case .setExcludeLocalNetworks(let excludeLocalNetworks):
            self.excludeLocalNetworks = excludeLocalNetworks
        case .setIncludeAllNetworks(let includeAllNetworks):
            self.includeAllNetworks = includeAllNetworks
        case .setNotifyStatusChanges(let notifyStatusChanges):
            self.notifyStatusChanges = notifyStatusChanges
        case .setRegistrationKeyValidity(let registrationKeyValidity):
            self.registrationKeyValidity = registrationKeyValidity
        case .setSelectedServer(let selectedServer):
            self.selectedServer = selectedServer
        case .setSelectedLocation(let selectedLocation):
            self.selectedLocation = selectedLocation
        case .setSelectedEnvironment(let selectedEnvironment):
            self.selectedEnvironment = selectedEnvironment
        case .setDNSSettings(let dnsSettings):
            self.dnsSettings = dnsSettings
        case .setShowInMenuBar(let showInMenuBar):
            self.showInMenuBar = showInMenuBar
        case .setDisableRekeying(let disableRekeying):
            self.disableRekeying = disableRekeying
        }
    }

    // MARK: - Connect on Login

    public var connectOnLoginPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingConnectOnLoginPublisher
    }

    public var connectOnLogin: Bool {
        get {
            defaults.networkProtectionSettingConnectOnLogin
        }

        set {
            defaults.networkProtectionSettingConnectOnLogin = newValue
        }
    }

    // MARK: - Enforce Routes

    public var includeAllNetworksPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingIncludeAllNetworksPublisher
    }

    public var includeAllNetworks: Bool {
        get {
            defaults.networkProtectionSettingIncludeAllNetworks
        }

        set {
            defaults.networkProtectionSettingIncludeAllNetworks = newValue
        }
    }

    // MARK: - Enforce Routes

    public var enforceRoutesPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingEnforceRoutesPublisher
    }

    public var enforceRoutes: Bool {
        get {
            defaults.networkProtectionSettingEnforceRoutes
        }

        set {
            defaults.networkProtectionSettingEnforceRoutes = newValue
        }
    }

    // MARK: - Exclude Local Routes

    public var excludeLocalNetworksPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingExcludeLocalNetworksPublisher
    }

    public var excludeLocalNetworks: Bool {
        get {
            defaults.networkProtectionSettingExcludeLocalNetworks
        }

        set {
            defaults.networkProtectionSettingExcludeLocalNetworks = newValue
        }
    }

    // MARK: - Registration Key Validity

    public var registrationKeyValidityPublisher: AnyPublisher<RegistrationKeyValidity, Never> {
        defaults.networkProtectionSettingRegistrationKeyValidityPublisher
    }

    public var registrationKeyValidity: RegistrationKeyValidity {
        get {
            defaults.networkProtectionSettingRegistrationKeyValidity
        }

        set {
            defaults.networkProtectionSettingRegistrationKeyValidity = newValue
        }
    }

    private var networkProtectionSettingRegistrationKeyValidityDefault: TimeInterval {
        .days(2)
    }

    // MARK: - Server Selection

    public var selectedServerPublisher: AnyPublisher<SelectedServer, Never> {
        defaults.networkProtectionSettingSelectedServerPublisher
    }

    public var selectedServer: SelectedServer {
        get {
            defaults.networkProtectionSettingSelectedServer
        }

        set {
            defaults.networkProtectionSettingSelectedServer = newValue
        }
    }

    // MARK: - Location Selection

    public var selectedLocationPublisher: AnyPublisher<SelectedLocation, Never> {
        defaults.networkProtectionSettingSelectedLocationPublisher
    }

    public var selectedLocation: SelectedLocation {
        get {
            defaults.networkProtectionSettingSelectedLocation
        }

        set {
            defaults.networkProtectionSettingSelectedLocation = newValue
        }
    }

    // MARK: - Environment

    public var selectedEnvironmentPublisher: AnyPublisher<SelectedEnvironment, Never> {
        defaults.networkProtectionSettingSelectedEnvironmentPublisher
    }

    public var selectedEnvironment: SelectedEnvironment {
        get {
            defaults.networkProtectionSettingSelectedEnvironment
        }

        set {
            defaults.networkProtectionSettingSelectedEnvironment = newValue
        }
    }

#if os(iOS)
    public var isAuthV2Enabled: Bool {
        get {
            defaults.networkProtectionSettingIsAuthV2Enabled
        }
        set {
            defaults.networkProtectionSettingIsAuthV2Enabled = newValue
        }
    }
#endif

    // MARK: - DNS Settings

    public var dnsSettingsPublisher: AnyPublisher<NetworkProtectionDNSSettings, Never> {
        defaults.dnsSettingsPublisher
    }

    public var isBlockRiskyDomainsOn: Bool {
        defaults.isBlockRiskyDomainsOn
    }

    public var customDnsServers: [String] {
        defaults.customDnsServers
    }

    public var didBlockRiskyDomainsDefaultToTrue: Bool {
        get {
            defaults.didBlockRiskyDomainsDefaultToTrue
        }
        set {
            defaults.didBlockRiskyDomainsDefaultToTrue = newValue
        }
    }

    public var dnsSettings: NetworkProtectionDNSSettings {
        get {
            return defaults.dnsSettings
        }
        set {
            // If dnsSettings is already ddg(true), mark that we've defaulted.
            if case .ddg(true) = defaults.dnsSettings {
                didBlockRiskyDomainsDefaultToTrue = true
            }
            defaults.dnsSettings = newValue
        }
    }

    // MARK: - Show in Menu Bar

    public var showInMenuBarPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingShowInMenuBarPublisher
    }

    public var showInMenuBar: Bool {
        get {
            defaults.networkProtectionSettingShowInMenuBar
        }

        set {
            defaults.networkProtectionSettingShowInMenuBar = newValue
        }
    }

    // MARK: - Notify Status Changes

    public var notifyStatusChangesPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionNotifyStatusChangesPublisher
    }

    public var notifyStatusChanges: Bool {
        get {
            defaults.networkProtectionNotifyStatusChanges
        }

        set {
            defaults.networkProtectionNotifyStatusChanges = newValue
        }
    }

    // MARK: - Disable Rekeying

    public var disableRekeyingPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingDisableRekeyingPublisher
    }

    public var disableRekeying: Bool {
        get {
            defaults.networkProtectionSettingDisableRekeying
        }

        set {
            defaults.networkProtectionSettingDisableRekeying = newValue
        }
    }
}
