//
//  VPNPreferencesModel.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine
import CombineExtensions
import Common
import ConcurrencyExtensions
import Foundation
import FoundationExtensions
import NetworkProtectionIPC
import NetworkProtectionProxy
import NetworkProtectionUI
import PixelKit
import PrivacyConfig
import VPN
import VPNAppState

final class VPNPreferencesModel: ObservableObject {

    @Published var locationItem: VPNLocationPreferenceItemModel

    @Published var alwaysON = true

    @Published var connectOnLogin: Bool {
        didSet {
            guard settings.connectOnLogin != connectOnLogin else {
                return
            }

            settings.connectOnLogin = connectOnLogin
        }
    }

    @Published var excludeLocalNetworks: Bool {
        didSet {
            guard settings.excludeLocalNetworks != excludeLocalNetworks else {
                return
            }
            settings.excludeLocalNetworks = excludeLocalNetworks
            reloadVPN()
        }
    }

    @Published var enforceRoutes: Bool {
        didSet {
            guard settings.enforceRoutes != enforceRoutes else {
                return
            }
            settings.enforceRoutes = enforceRoutes
        }
    }

    @Published private(set) var isStrictRoutingAvailable: Bool

    @Published var excludeCGNAT: Bool {
        didSet {
            guard settings.excludeCGNAT != excludeCGNAT else {
                return
            }
            settings.excludeCGNAT = excludeCGNAT
            reloadVPN()
        }
    }

    var isExcludeCGNATAvailable: Bool {
        featureFlagger.isFeatureOn(.vpnExcludeCGNATToggle)
    }

    @Published var showInMenuBar: Bool {
        didSet {
            settings.showInMenuBar = showInMenuBar
        }
    }

    @Published var showInBrowserToolbar: Bool {
        didSet {
            if showInBrowserToolbar {
                pinningManager.pin(.networkProtection)
            } else {
                pinningManager.unpin(.networkProtection)
            }
        }
    }

    /// Whether new app exclusions should be shown
    ///
    var showExclusionsFeature: Bool {
        AppVersion.isAppStoreBuild ? vpnAppState.isUsingSystemExtension : true
    }

    @Published
    private(set) var excludedDomainsCount: Int

    @Published
    private(set) var excludedAppsCount: Int

    @Published var notifyStatusChanges: Bool {
        didSet {
            settings.notifyStatusChanges = notifyStatusChanges
        }
    }

    @Published var showUninstallVPN: Bool

    enum CopySupportInfoState: Equatable {
        case idle
        case copying
        case copied
        case failed
    }

    @Published private(set) var copySupportInfoState: CopySupportInfoState = .idle

    var showsCopyDiagnosticsButton: Bool {
        featureFlagger.isFeatureOn(.vpnShowCopyDiagnosticsButton)
    }

    private var onboardingStatus: OnboardingStatus {
        didSet {
            showUninstallVPN = DefaultVPNFeatureGatekeeper(vpnUninstaller: VPNUninstaller(pinningManager: pinningManager), subscriptionManager: Application.appDelegate.subscriptionManager).isInstalled
        }
    }

    @Published public var dnsSettings: NetworkProtectionDNSSettings
    @Published public var isCustomDNSSelected: Bool {
        didSet {
            if oldValue != isCustomDNSSelected {
                updateDNSSettings()
            }
        }
    }
    @Published public var customDNSServers: String? {
        didSet {
            if oldValue != customDNSServers {
                updateDNSSettings()
            }
        }
    }
    @Published var isBlockRiskyDomainsOn: Bool {
        didSet {
            if oldValue != isBlockRiskyDomainsOn {
                updateDNSSettings()
            }
        }
    }

    private let vpnXPCClient: VPNControllerXPCClient
    private let vpnAppState: VPNAppState
    private let defaults: UserDefaults
    private let settings: VPNSettings
    private let proxySettings: TransparentProxySettings
    private let pinningManager: PinningManager
    private let featureFlagger: FeatureFlagger
    private var cancellables = Set<AnyCancellable>()

    init(vpnXPCClient: VPNControllerXPCClient = .shared,
         settings: VPNSettings = NSApp.delegateTyped.vpnSettings,
         proxySettings: TransparentProxySettings = .init(defaults: .netP),
         pinningManager: PinningManager,
         defaults: UserDefaults = .netP,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {

        self.vpnAppState = .init(defaults: defaults)
        self.defaults = defaults
        self.vpnXPCClient = vpnXPCClient
        self.settings = settings
        self.proxySettings = proxySettings
        self.pinningManager = pinningManager
        self.featureFlagger = featureFlagger

        connectOnLogin = settings.connectOnLogin
        excludedAppsCount = proxySettings.excludedAppsMinusDBPAgent.count
        excludedDomainsCount = proxySettings.excludedDomains.count
        excludeLocalNetworks = settings.excludeLocalNetworks
        enforceRoutes = settings.enforceRoutes
        isStrictRoutingAvailable = featureFlagger.isFeatureOn(.vpnStrictRoutingToggle)
        excludeCGNAT = settings.excludeCGNAT
        notifyStatusChanges = settings.notifyStatusChanges
        showInMenuBar = settings.showInMenuBar
        showInBrowserToolbar = pinningManager.isPinned(.networkProtection)
        showUninstallVPN = defaults.networkProtectionOnboardingStatus != .default
        onboardingStatus = defaults.networkProtectionOnboardingStatus
        locationItem = VPNLocationPreferenceItemModel(selectedLocation: settings.selectedLocation)
        isBlockRiskyDomainsOn = settings.isBlockRiskyDomainsOn
        customDNSServers = settings.customDnsServers.joined(separator: ", ")
        dnsSettings = settings.dnsSettings
        isCustomDNSSelected = settings.dnsSettings.usesCustomDNS

        subscribeToAppRoutingRulesChanges()
        subscribeToOnboardingStatusChanges(defaults: defaults)
        subscribeToConnectOnLoginSettingChanges()
        subscribeToExcludedDomainsCountChanges()
        subscribeToExcludeLocalNetworksSettingChanges()
        subscribeToEnforceRoutesSettingChanges()
        subscribeToStrictRoutingAvailabilityChanges()
        subscribeToExcludeCGNATSettingChanges()
        subscribeToShowInMenuBarSettingChanges()
        subscribeToShowInBrowserToolbarSettingsChanges()
        subscribeToLocationSettingChanges()
        subscribeToDNSSettingsChanges()
    }

    deinit {
        cancellables.removeAll()
    }

    private func subscribeToAppRoutingRulesChanges() {
        proxySettings.appRoutingRulesPublisher
            .map { rules in
                rules.filter { (bundleId, rule) in
                    rule == .exclude && !bundleId.isDBPBackgroundAgentBundleId
                }.count
            }
            .assign(to: \.excludedAppsCount, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToOnboardingStatusChanges(defaults: UserDefaults) {
        defaults.networkProtectionOnboardingStatusPublisher
            .assign(to: \.onboardingStatus, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToConnectOnLoginSettingChanges() {
        settings.connectOnLoginPublisher
            .assign(to: \.connectOnLogin, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToExcludedDomainsCountChanges() {
        proxySettings.excludedDomainsPublisher
            .map { $0.count }
            .assign(to: \.excludedDomainsCount, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToExcludeLocalNetworksSettingChanges() {
        settings.excludeLocalNetworksPublisher
            .assign(to: \.excludeLocalNetworks, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToEnforceRoutesSettingChanges() {
        settings.enforceRoutesPublisher
            .assign(to: \.enforceRoutes, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToStrictRoutingAvailabilityChanges() {
        // Keep the toggle's availability in sync as the feature flag changes at runtime
        // (remote config update or a local override), so the row appears/disappears live.
        featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.isStrictRoutingAvailable = self.featureFlagger.isFeatureOn(.vpnStrictRoutingToggle)
            }
            .store(in: &cancellables)
    }

    private func subscribeToExcludeCGNATSettingChanges() {
        settings.excludeCGNATPublisher
            .assign(to: \.excludeCGNAT, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToShowInMenuBarSettingChanges() {
        settings.showInMenuBarPublisher
            .removeDuplicates()
            .assign(to: \.showInMenuBar, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToShowInBrowserToolbarSettingsChanges() {
        NotificationCenter.default.publisher(for: .PinnedViewsChanged).sink { [weak self] notification in
            guard let self = self else {
                return
            }

            if let userInfo = notification.userInfo as? [String: Any],
               let viewType = userInfo[LocalPinningManager.pinnedViewChangedNotificationViewTypeKey] as? String,
               let view = PinnableView(rawValue: viewType) {
                switch view {
                case .networkProtection: self.showInBrowserToolbar = self.pinningManager.isPinned(.networkProtection)
                default: break
                }
            }
        }
        .store(in: &cancellables)
    }

    private func subscribeToLocationSettingChanges() {
        settings.selectedLocationPublisher
            .map(VPNLocationPreferenceItemModel.init(selectedLocation:))
            .assign(to: \.locationItem, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToDNSSettingsChanges() {
        settings.dnsSettingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDNSSettings in
                guard let self = self else { return }
                self.dnsSettings = newDNSSettings
                if self.isCustomDNSSelected != newDNSSettings.usesCustomDNS {
                    self.isCustomDNSSelected = newDNSSettings.usesCustomDNS
                }
                if self.customDNSServers != self.settings.customDnsServers.joined(separator: ", ") {
                    self.customDNSServers = self.settings.customDnsServers.joined(separator: ", ")
                }
                if case .ddg(let blockRiskyDomains) = newDNSSettings,
                   self.isBlockRiskyDomainsOn != blockRiskyDomains {
                    self.isBlockRiskyDomainsOn = blockRiskyDomains
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func onViewAppeared() {
        settings.updateExcludeCGNAT(isFeatureEnabled: featureFlagger.isFeatureOn(.vpnExcludeCGNATToggle))
    }

    func reloadVPN() {
        Task {
            // Allow some time for the change to propagate
            try await Task.sleep(interval: 0.1)
            try await vpnXPCClient.command(.restartAdapter)
        }
    }

    func resetDNSSettings() {
        settings.dnsSettings = .ddg(blockRiskyDomains: settings.isBlockRiskyDomainsOn)
        reloadVPN()
    }

    @MainActor
    func uninstallVPN() async {
        let response = await uninstallVPNConfirmationAlert().runModal()

        switch response {
        case .OK:
            try? await VPNUninstaller(pinningManager: pinningManager).uninstall(
                removeSystemExtension: true,
                showNotification: true)
        default:
            // intentional no-op
            break
        }
    }

    @MainActor
    func uninstallVPNConfirmationAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = UserText.uninstallVPNAlertTitle
        alert.informativeText = UserText.uninstallVPNInformativeText
        let uninstallButton = alert.addButton(withTitle: UserText.uninstall)
        uninstallButton.tag = NSApplication.ModalResponse.OK.rawValue
        uninstallButton.keyEquivalent = ""

        let cancelButton = alert.addButton(withTitle: UserText.cancel)
        cancelButton.tag = NSApplication.ModalResponse.cancel.rawValue
        cancelButton.keyEquivalent = "\r"

        return alert
    }

    // MARK: - Actions

    @MainActor
    func openVPNViewInMainWindow() {
        PixelKit.fire(SubscriptionPixel.subscriptionVPNSettings)
        NotificationCenter.default.post(name: .ToggleNetworkProtectionInMainWindow, object: nil)
    }

    @MainActor
    func copySupportInfo() async {
        guard copySupportInfoState == .idle else { return }
        copySupportInfoState = .copying
        let succeeded = await VPNURLEventHandler().copySupportInfo()
        showCopySupportInfoConfirmation(succeeded ? .copied : .failed)
    }

    @MainActor
    private func showCopySupportInfoConfirmation(_ state: CopySupportInfoState) {
        copySupportInfoState = state

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            guard copySupportInfoState == state else {
                return
            }

            copySupportInfoState = .idle
        }
    }

    @MainActor
    func manageExcludedApps() {
        Application.appDelegate.windowControllersManager.showVPNAppExclusions()
    }

    @MainActor
    func manageExcludedSites() {
        Application.appDelegate.windowControllersManager.showVPNDomainExclusions()
    }

    @MainActor
    func openNewTab(with url: URL) {
        Application.appDelegate.windowControllersManager.show(url: url, source: .ui, newTab: true)
    }

    private func updateDNSSettings() {
        // Fire the corresponding pixel events.
        if settings.dnsSettings != self.dnsSettings {
            if settings.dnsSettings.usesCustomDNS {
                PixelKit.fire(NetworkProtectionPixelEvent.networkProtectionDNSUpdateCustom,
                              frequency: .legacyDailyAndCount)
            } else {
                PixelKit.fire(NetworkProtectionPixelEvent.networkProtectionDNSUpdateDefault,
                              frequency: .legacyDailyAndCount)
            }
        }

        if isCustomDNSSelected {
            guard let serversText = customDNSServers, !serversText.isEmpty else {
                return
            }
            let servers = serversText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            settings.dnsSettings = .custom(servers)
        } else {
            settings.dnsSettings = .ddg(blockRiskyDomains: isBlockRiskyDomainsOn)
        }
        reloadVPN()
    }
}

extension NetworkProtectionDNSSettings {
    var dnsServersText: String? {
        switch self {
        case .ddg: return ""
        case .custom(let servers): return servers.joined(separator: ", ")
        }
    }
}

extension TransparentProxySettings {
    var excludedAppsMinusDBPAgent: [String] {
        excludedApps.filter { !$0.isDBPBackgroundAgentBundleId }
    }
}

extension String {
    fileprivate var isDBPBackgroundAgentBundleId: Bool {
        self == Bundle.main.dbpBackgroundAgentBundleId
    }
}
