//
//  VPNMetadataCollector.swift
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

import Foundation
import AppKit
import Common
import FoundationExtensions
import LoginItems
import Network
import NetworkProtectionIPC
import NetworkProtectionUI
import Subscription
import VPN

struct VPNMetadata: Encodable {

    struct AppInfo: Encodable {
        let appVersion: String
        let lastAgentVersionRun: String
        let lastExtensionVersionRun: String
        let isInternalUser: Bool
        let isInApplicationsDirectory: Bool
    }

    struct DeviceInfo: Encodable {
        let osVersion: String
        let buildFlavor: String
        let lowPowerModeEnabled: Bool
        let cpuArchitecture: String
    }

    struct NetworkInfo: Encodable {
        let currentPath: NetworkProtectionNetworkPathInfo?
        let deviceAddressCategories: [NetworkProtectionIPAddressCategory]
        let routerAddressCategories: [NetworkProtectionIPAddressCategory]
    }

    struct VPNState: Encodable {
        let onboardingState: String
        let connectionState: String
        let lastStartErrorDescription: String
        let lastTunnelErrorDescription: String
        let lastKnownFailureDescription: String
        let connectedServer: String
        let connectedServerIP: String
        let dataVolume: NetworkProtectionDataVolumeBuckets?
    }

    struct DNSSettingsState: Encodable {
        enum Selection: String, Encodable {
            case duckDuckGo
            case custom
        }

        let selection: Selection
        let blockRiskyDomainsEnabled: Bool?
        let customDNSServerAddressCategory: NetworkProtectionIPAddressCategory?
    }

    struct VPNSettingsState: Encodable {
        let connectOnLoginEnabled: Bool
        let includeAllNetworksEnabled: Bool
        let enforceRoutesEnabled: Bool
        let excludeLocalNetworksEnabled: Bool
        let excludeCGNATEnabled: Bool
        let notifyStatusChangesEnabled: Bool
        let showInMenuBarEnabled: Bool
        let selectedServer: String
        let selectedEnvironment: String
        let customDNS: Bool
        let dnsSettings: DNSSettingsState
    }

    struct LoginItemState: Encodable {
        let vpnMenuState: String
        let vpnMenuIsRunning: Bool
    }

    struct SubscriptionInfo: Encodable {
        /// Whether the app has authenticated subscription account state.
        let isSubscriptionAuthenticated: Bool

        /// Whether the user's subscription plan/SKU includes VPN, based on cached plan feature data. `nil` means the lookup failed.
        let subscriptionPlanIncludesVPN: Bool?

        /// Whether the subscription account's current access token grants VPN access. This does not guarantee VPN can start on this device.
        /// `nil` means the token entitlement lookup failed.
        let accountCanUseVPN: Bool?
    }

    let appInfo: AppInfo
    let deviceInfo: DeviceInfo
    let networkInfo: NetworkInfo
    let vpnState: VPNState
    let vpnSettingsState: VPNSettingsState
    let loginItemState: LoginItemState
    let subscriptionInfo: SubscriptionInfo

    func toPrettyPrintedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        guard let encodedMetadata = try? encoder.encode(self) else {
            assertionFailure("Failed to encode metadata")
            return nil
        }

        return String(data: encodedMetadata, encoding: .utf8)
    }

    func toBase64() -> String {
        let encoder = JSONEncoder()

        do {
            let encodedMetadata = try encoder.encode(self)
            return encodedMetadata.base64EncodedString()
        } catch {
            return "Failed to encode metadata to JSON, error message: \(error.localizedDescription)"
        }
    }

}

protocol VPNMetadataCollector {
    func collectVPNMetadata() async -> VPNMetadata
}

final class DefaultVPNMetadataCollector: VPNMetadataCollector {

    private let statusReporter: NetworkProtectionStatusReporter
    private let ipcClient: VPNControllerXPCClient
    private let defaults: UserDefaults
    private let subscriptionManager: any SubscriptionManager
    private let settings: VPNSettings

    init(defaults: UserDefaults = .netP,
         subscriptionManager: any SubscriptionManager) {

        let ipcClient = VPNControllerXPCClient.shared
        ipcClient.register { _ in }

        self.subscriptionManager = subscriptionManager
        self.ipcClient = ipcClient
        self.defaults = defaults

        self.statusReporter = DefaultNetworkProtectionStatusReporter(
            vpnEnabledObserver: ipcClient.vpnEnabledObserver,
            statusObserver: ipcClient.connectionStatusObserver,
            serverInfoObserver: ipcClient.serverInfoObserver,
            connectionErrorObserver: ipcClient.connectionErrorObserver,
            connectivityIssuesObserver: ConnectivityIssueObserverThroughDistributedNotifications(),
            controllerErrorMessageObserver: ControllerErrorMesssageObserverThroughDistributedNotifications(),
            dataVolumeObserver: ipcClient.dataVolumeObserver,
            knownFailureObserver: KnownFailureObserverThroughDistributedNotifications()
        )

        self.settings = VPNSettings(defaults: defaults)
        updateSettings()
    }

    func updateSettings() {
        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
        let subscriptionEnvironment = DefaultSubscriptionManager.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)
        settings.alignTo(subscriptionEnvironment: subscriptionEnvironment)
    }

    @MainActor
    func collectVPNMetadata() async -> VPNMetadata {
        let appInfoMetadata = collectAppInfoMetadata()
        let deviceInfoMetadata = collectDeviceInfoMetadata()
        let networkInfoMetadata = await collectNetworkInformation()
        let vpnState = await collectVPNState()
        let vpnSettingsState = collectVPNSettingsState()
        let loginItemState = collectLoginItemState()
        let subscriptionInfo = await collectSubscriptionInfo()

        return VPNMetadata(
            appInfo: appInfoMetadata,
            deviceInfo: deviceInfoMetadata,
            networkInfo: networkInfoMetadata,
            vpnState: vpnState,
            vpnSettingsState: vpnSettingsState,
            loginItemState: loginItemState,
            subscriptionInfo: subscriptionInfo
        )
    }

    // MARK: - Metadata Collection

    private func collectAppInfoMetadata() -> VPNMetadata.AppInfo {
        let appVersion = AppVersion.shared.versionAndBuildNumber
        let versionStore = NetworkProtectionLastVersionRunStore(userDefaults: defaults)
        let isInternalUser = NSApp.delegateTyped.internalUserDecider.isInternalUser
        let isInApplicationsDirectory = Bundle.main.isInApplicationsDirectory

        return .init(
            appVersion: appVersion,
            lastAgentVersionRun: versionStore.lastAgentVersionRun ?? "none",
            lastExtensionVersionRun: versionStore.lastExtensionVersionRun ?? "none",
            isInternalUser: isInternalUser,
            isInApplicationsDirectory: isInApplicationsDirectory
        )
    }

    private func collectDeviceInfoMetadata() -> VPNMetadata.DeviceInfo {
        let buildFlavor = AppVersion.isAppStoreBuild ? "appstore" : "dmg"
        let osVersion = AppVersion.shared.osVersionMajorMinorPatch
        let lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

        let architecture = getMachineArchitecture()

        return .init(osVersion: osVersion, buildFlavor: buildFlavor, lowPowerModeEnabled: lowPowerModeEnabled, cpuArchitecture: architecture)
    }

    private func getMachineArchitecture() -> String {
#if arch(arm)
        return "arm"
#elseif arch(arm64)
        return "arm64"
#elseif arch(i386)
        return "i386"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }

    func collectNetworkInformation() async -> VPNMetadata.NetworkInfo {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "VPNMetadataCollector.NWPathMonitor.paths"))

        let startTime = CFAbsoluteTimeGetCurrent()

        while true {
            if !monitor.currentPath.availableInterfaces.isEmpty {
                let path = monitor.currentPath
                monitor.cancel()

                return .init(
                    currentPath: path.anonymousPathInfo,
                    deviceAddressCategories: NetworkProtectionAddressMetadata.deviceAddressCategories(for: path),
                    routerAddressCategories: NetworkProtectionAddressMetadata.routerAddressCategories(for: path)
                )
            }

            // Wait up to 3 seconds to fetch the path.
            let currentExecutionTime = CFAbsoluteTimeGetCurrent() - startTime
            if currentExecutionTime >= 3.0 {
                return .init(
                    currentPath: nil,
                    deviceAddressCategories: [.unknown],
                    routerAddressCategories: [.unknown]
                )
            }
        }
    }

    @MainActor
    func collectVPNState() async -> VPNMetadata.VPNState {
        let onboardingState: String

        switch defaults.networkProtectionOnboardingStatus {
        case .completed:
            onboardingState = "complete"
        case .isOnboarding(let step):
            switch step {
            case .userNeedsToAllowExtension:
                onboardingState = "pending-extension-approval"
            case .userNeedsToAllowVPNConfiguration:
                onboardingState = "pending-vpn-approval"
            }
        }

        let errorHistory = VPNOperationErrorHistory(ipcClient: ipcClient, defaults: defaults)

        let status = statusReporter.statusObserver.recentValue
        let connectionState = String(describing: status)
        let lastTunnelErrorDescription = await errorHistory.lastTunnelErrorDescription
        let lastKnownFailureDescription = Self.knownFailureDescription(NetworkProtectionKnownFailureStore().lastKnownFailure)
        let connectedServer = statusReporter.serverInfoObserver.recentValue.serverLocation?.serverLocation ?? "none"
        let connectedServerIP = statusReporter.serverInfoObserver.recentValue.serverAddress ?? "none"
        let dataVolume = status.canReportActiveDataVolume
            ? NetworkProtectionDataVolumeBuckets(dataVolume: statusReporter.dataVolumeObserver.recentValue)
            : nil

        return .init(onboardingState: onboardingState,
                     connectionState: connectionState,
                     lastStartErrorDescription: errorHistory.lastStartErrorDescription,
                     lastTunnelErrorDescription: lastTunnelErrorDescription,
                     lastKnownFailureDescription: lastKnownFailureDescription,
                     connectedServer: connectedServer,
                     connectedServerIP: connectedServerIP,
                     dataVolume: dataVolume)
    }

    private static func knownFailureDescription(_ knownFailure: KnownFailure?) -> String {
        guard let knownFailure else {
            return "none"
        }

        if let silentError = KnownFailure.SilentError(rawValue: knownFailure.error) {
            return "KnownFailure error=\(silentError) code=\(knownFailure.error)"
        }

        return "KnownFailure code=\(knownFailure.error)"
    }

    func collectLoginItemState() -> VPNMetadata.LoginItemState {
        let vpnMenuState = String(describing: LoginItem.vpnMenu.status)
        let vpnMenuIsRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: LoginItem.vpnMenu.agentBundleID).isEmpty

        return .init(
            vpnMenuState: vpnMenuState,
            vpnMenuIsRunning: vpnMenuIsRunning)
    }

    func collectVPNSettingsState() -> VPNMetadata.VPNSettingsState {
        return .init(
            connectOnLoginEnabled: settings.connectOnLogin,
            includeAllNetworksEnabled: settings.includeAllNetworks,
            enforceRoutesEnabled: settings.enforceRoutes,
            excludeLocalNetworksEnabled: settings.excludeLocalNetworks,
            excludeCGNATEnabled: settings.excludeCGNAT,
            notifyStatusChangesEnabled: settings.notifyStatusChanges,
            showInMenuBarEnabled: settings.showInMenuBar,
            selectedServer: settings.selectedServer.stringValue ?? "automatic",
            selectedEnvironment: settings.selectedEnvironment.rawValue,
            customDNS: settings.dnsSettings.usesCustomDNS,
            dnsSettings: collectDNSSettingsState()
        )
    }

    func collectDNSSettingsState() -> VPNMetadata.DNSSettingsState {
        switch settings.dnsSettings {
        case .ddg(let blockRiskyDomains):
            return .init(
                selection: .duckDuckGo,
                blockRiskyDomainsEnabled: blockRiskyDomains,
                customDNSServerAddressCategory: nil
            )
        case .custom(let servers):
            return .init(
                selection: .custom,
                blockRiskyDomainsEnabled: nil,
                customDNSServerAddressCategory: servers.first.map(NetworkProtectionIPAddressClassifier.classify)
            )
        }
    }

    func collectSubscriptionInfo() async -> VPNMetadata.SubscriptionInfo {
        let subscriptionPlanIncludesVPN = try? await subscriptionManager.isFeatureIncludedInSubscription(.networkProtection)
        let accountCanUseVPN = try? await subscriptionManager.isFeatureEnabled(.networkProtection)

        return .init(
            isSubscriptionAuthenticated: subscriptionManager.isUserAuthenticated,
            subscriptionPlanIncludesVPN: subscriptionPlanIncludesVPN,
            accountCanUseVPN: accountCanUseVPN)
    }

}

// MARK: - Unified feedback form support

extension VPNMetadata: UnifiedFeedbackMetadata {}

extension DefaultVPNMetadataCollector: UnifiedMetadataCollector {
    func collectMetadata() async -> VPNMetadata {
        await collectVPNMetadata()
    }
}

private extension ConnectionStatus {
    var canReportActiveDataVolume: Bool {
        switch self {
        case .connected, .reasserting:
            return true
        case .notConfigured, .disconnected, .disconnecting, .connecting, .snoozing:
            return false
        }
    }
}
