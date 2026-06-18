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
        case setExcludeCGNAT(_ excludeCGNAT: Bool)
        case setExcludeAPNs(_ excludeAPNs: Bool)
        case setExcludeCellularServices(_ excludeCellularServices: Bool)
        case setExcludeDeviceCommunication(_ excludeDeviceCommunication: Bool)
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

        public var stringValue: String {
            switch self {
            case .nearest: return "nearest"
            case .location: return "custom"
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

        let excludeCGNATPublisher = excludeCGNATPublisher
            .dropFirst()
            .removeDuplicates()
            .map { excludeCGNAT in
                Change.setExcludeCGNAT(excludeCGNAT)
            }.eraseToAnyPublisher()

        let excludeAPNsPublisher = excludeAPNsPublisher
            .dropFirst()
            .removeDuplicates()
            .map { excludeAPNs in
                Change.setExcludeAPNs(excludeAPNs)
            }.eraseToAnyPublisher()

        let excludeCellularServicesPublisher = excludeCellularServicesPublisher
            .dropFirst()
            .removeDuplicates()
            .map { excludeCellularServices in
                Change.setExcludeCellularServices(excludeCellularServices)
            }.eraseToAnyPublisher()

        let excludeDeviceCommunicationPublisher = excludeDeviceCommunicationPublisher
            .dropFirst()
            .removeDuplicates()
            .map { excludeDeviceCommunication in
                Change.setExcludeDeviceCommunication(excludeDeviceCommunication)
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
            excludeCGNATPublisher,
            excludeAPNsPublisher,
            excludeCellularServicesPublisher,
            excludeDeviceCommunicationPublisher,
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
        defaults.resetNetworkProtectionSettingExcludeLocalNetworks()
        defaults.resetNetworkProtectionSettingExcludeCGNAT()
        defaults.resetNetworkProtectionSettingExcludeAPNs()
        defaults.resetNetworkProtectionSettingExcludeCellularServices()
        defaults.resetNetworkProtectionSettingExcludeDeviceCommunication()
        defaults.resetNetworkProtectionSettingIncludeAllNetworks()
        defaults.resetNetworkProtectionSettingNotifyStatusChanges()
        defaults.resetNetworkProtectionSettingRegistrationKeyValidity()
        defaults.resetNetworkProtectionSettingSelectedServer()
        defaults.resetDNSSettings()
        defaults.resetNetworkProtectionSettingShowInMenuBar()
        defaults.resetVPNSettingEnforceRoutes()
    }

    public func resetTunnelFlagsToDefaults() {
        defaults.resetNetworkProtectionSettingIncludeAllNetworks()
        defaults.resetNetworkProtectionSettingExcludeLocalNetworks()
        defaults.resetNetworkProtectionSettingExcludeCGNAT()
        defaults.resetNetworkProtectionSettingExcludeAPNs()
        defaults.resetNetworkProtectionSettingExcludeCellularServices()
        defaults.resetNetworkProtectionSettingExcludeDeviceCommunication()
        defaults.resetVPNSettingEnforceRoutes()
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
        case .setExcludeCGNAT(let excludeCGNAT):
            self.excludeCGNAT = excludeCGNAT
        case .setExcludeAPNs(let excludeAPNs):
            self.excludeAPNs = excludeAPNs
        case .setExcludeCellularServices(let excludeCellularServices):
            self.excludeCellularServices = excludeCellularServices
        case .setExcludeDeviceCommunication(let excludeDeviceCommunication):
            self.excludeDeviceCommunication = excludeDeviceCommunication
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
        defaults.vpnSettingEnforceRoutesPublisher
    }

    public var enforceRoutes: Bool {
        get {
            defaults.vpnSettingEnforceRoutes
        }

        set {
            defaults.vpnSettingEnforceRoutes = newValue
        }
    }

    /// Forces `enforceRoutes` back to its safe default when Strict routing isn't available to this
    /// user, so a value relaxed while the feature was available can't persist after it's withdrawn.
    ///
    /// Callers pass the resolved availability (not a feature flagger) so this stays free of the
    /// app-side flag system — keeping it usable from contexts that can't evaluate flags.
    public func resetEnforceRoutesIfUnavailable(strictRoutingAvailable: Bool) {
        guard strictRoutingAvailable else {
            defaults.resetVPNSettingEnforceRoutes()
            return
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

    // MARK: - Exclude CGNAT

    public var excludeCGNATPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingExcludeCGNATPublisher
    }

    public var excludeCGNAT: Bool {
        get {
            defaults.networkProtectionSettingExcludeCGNAT
        }

        set {
            defaults.networkProtectionSettingExcludeCGNAT = newValue
        }
    }

    /// Syncs `excludeCGNAT` against the feature-flag state. When the flag is off, the
    /// value is forced to `false`. When on, the stored value is left alone (the storage
    /// default produces the experimental on-by-default for users with the flag).
    /// Call at app launch, tunnel start, and when the VPN settings screen appears so
    /// readers of the raw value (tunnel, metadata) always see the effective value.
    public func updateExcludeCGNAT(isFeatureEnabled: Bool) {
        let effective = isFeatureEnabled ? excludeCGNAT : false
        guard excludeCGNAT != effective else { return }
        excludeCGNAT = effective
    }

    // MARK: - Orphan Proxy Detection

    /// When `false`, the tunnel stops writing its heartbeat (see `TunnelHeartbeatStore`), which in turn
    /// disables the transparent proxy's orphan detection. Resolved from a remote kill switch by the app
    /// and delivered to the tunnel via the startup options snapshot. Defaults to `true`.
    public var isOrphanProxyDetectionEnabled: Bool {
        get {
            defaults.networkProtectionSettingOrphanProxyDetectionEnabled
        }

        set {
            defaults.networkProtectionSettingOrphanProxyDetectionEnabled = newValue
        }
    }

    // MARK: - Exclude APNs

    public var excludeAPNsPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingExcludeAPNsPublisher
    }

    public var excludeAPNs: Bool {
        get {
            defaults.networkProtectionSettingExcludeAPNs
        }

        set {
            defaults.networkProtectionSettingExcludeAPNs = newValue
        }
    }

    // MARK: - Exclude Cellular Services

    public var excludeCellularServicesPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingExcludeCellularServicesPublisher
    }

    public var excludeCellularServices: Bool {
        get {
            defaults.networkProtectionSettingExcludeCellularServices
        }

        set {
            defaults.networkProtectionSettingExcludeCellularServices = newValue
        }
    }

    // MARK: - Exclude Device Communication

    public var excludeDeviceCommunicationPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingExcludeDeviceCommunicationPublisher
    }

    public var excludeDeviceCommunication: Bool {
        get {
            defaults.networkProtectionSettingExcludeDeviceCommunication
        }

        set {
            defaults.networkProtectionSettingExcludeDeviceCommunication = newValue
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

    public var dnsSettings: NetworkProtectionDNSSettings {
        get {
            return defaults.dnsSettings
        }
        set {
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

    // MARK: - Show Debug VPN Event Notifications

    public var showDebugVPNEventNotificationsPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingShowDebugVPNEventNotificationsPublisher
    }

    public var showDebugVPNEventNotifications: Bool {
        get {
            defaults.networkProtectionSettingShowDebugVPNEventNotifications
        }

        set {
            defaults.networkProtectionSettingShowDebugVPNEventNotifications = newValue
        }
    }

}
