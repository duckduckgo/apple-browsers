//
//  VPNMetadataCollector.swift
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

import Foundation
import BrowserServicesKit
import Core
import Common
import FoundationExtensions
import VPN
import NetworkExtension
import Network
import Subscription

struct VPNMetadata: Encodable {

    struct AppInfo: Encodable {
        let appVersion: String
        let lastExtensionVersionRun: String
        let isInternalUser: Bool
    }

    struct DeviceInfo: Encodable {
        let osVersion: String
        let lowPowerModeEnabled: Bool
    }

    struct NetworkInfo: Encodable {
        let currentPath: NetworkProtectionNetworkPathInfo?
        let lastPathChangeDate: String
        let lastPathChange: String
        let secondsSincePathChange: String
        let deviceAddressCategories: [NetworkProtectionIPAddressCategory]
        let routerAddressCategories: [NetworkProtectionIPAddressCategory]
    }

    struct VPNState: Encodable {
        let connectionState: String
        let lastDisconnectError: LastDisconnectError?
        let underlyingErrors: [LastDisconnectError]?
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
        let selectedServer: String
        let customDNS: Bool
        let dnsSettings: DNSSettingsState
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

    struct LastDisconnectError: Encodable {
        let domain: String
        let code: Int
        let description: String
    }

    let appInfo: AppInfo
    let deviceInfo: DeviceInfo
    let networkInfo: NetworkInfo
    let vpnState: VPNState
    let vpnSettingsState: VPNSettingsState
    let subscriptionInfo: SubscriptionInfo

    func toPrettyPrintedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let encodedMetadata = try? encoder.encode(self) else {
            assertionFailure("Failed to encode metadata")
            return nil
        }

        return String(data: encodedMetadata, encoding: .utf8)
    }
}

protocol VPNMetadataCollector {
    func collectVPNMetadata() async -> VPNMetadata
}

final class DefaultVPNMetadataCollector: VPNMetadataCollector {
    private let statusObserver: ConnectionStatusObserver
    private let serverInfoObserver: ConnectionServerInfoObserver
    private let subscriptionManager: any SubscriptionManager
    private let settings: VPNSettings
    private let defaults: UserDefaults
    private let tunnelSessionProvider: TunnelSessionProvider

    init(statusObserver: ConnectionStatusObserver,
         serverInfoObserver: ConnectionServerInfoObserver,
         tunnelSessionProvider: TunnelSessionProvider = VPNMetadataTunnelSessionProvider(),
         subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
         settings: VPNSettings = .init(defaults: .networkProtectionGroupDefaults),
         defaults: UserDefaults = .networkProtectionGroupDefaults) {
        self.statusObserver = statusObserver
        self.serverInfoObserver = serverInfoObserver
        self.tunnelSessionProvider = tunnelSessionProvider
        self.subscriptionManager = subscriptionManager
        self.settings = settings
        self.defaults = defaults
    }

    func collectVPNMetadata() async -> VPNMetadata {
        let appInfoMetadata = collectAppInfoMetadata()
        let deviceInfoMetadata = collectDeviceInfoMetadata()
        let networkInfoMetadata = await collectNetworkInformation()
        let vpnState = await collectVPNState()
        let vpnSettingsState = collectVPNSettingsState()
        let subscriptionInfo = await collectSubscriptionInfo()

        return VPNMetadata(
            appInfo: appInfoMetadata,
            deviceInfo: deviceInfoMetadata,
            networkInfo: networkInfoMetadata,
            vpnState: vpnState,
            vpnSettingsState: vpnSettingsState,
            subscriptionInfo: subscriptionInfo
        )
    }

    // MARK: - Metadata Collection

    private func collectAppInfoMetadata() -> VPNMetadata.AppInfo {
        let appVersion = AppVersion.shared.versionNumber
        let versionStore = NetworkProtectionLastVersionRunStore(userDefaults: .networkProtectionGroupDefaults)
        let isInternalUser = AppDependencyProvider.shared.internalUserDecider.isInternalUser

        return .init(
            appVersion: appVersion,
            lastExtensionVersionRun: versionStore.lastExtensionVersionRun ?? "Unknown",
            isInternalUser: isInternalUser
        )
    }

    private func collectDeviceInfoMetadata() -> VPNMetadata.DeviceInfo {
        .init(osVersion: AppVersion.shared.osVersionMajorMinorPatch, lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    func collectNetworkInformation() async -> VPNMetadata.NetworkInfo {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "VPNMetadataCollector.NWPathMonitor.paths"))

        let startTime = CFAbsoluteTimeGetCurrent()

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar.current
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let networkPathChange = defaults.networkPathChange

        let lastPathChange = String(describing: networkPathChange)
        var lastPathChangeDate = "unknown"
        var secondsSincePathChange = "unknown"

        if let changeDate = networkPathChange?.date {
            lastPathChangeDate = dateFormatter.string(from: changeDate)
            secondsSincePathChange = String(Date().timeIntervalSince(changeDate))
        }

        while true {
            if !monitor.currentPath.availableInterfaces.isEmpty {
                let path = monitor.currentPath
                monitor.cancel()

                return .init(currentPath: path.anonymousPathInfo,
                             lastPathChangeDate: lastPathChangeDate,
                             lastPathChange: lastPathChange,
                             secondsSincePathChange: secondsSincePathChange,
                             deviceAddressCategories: NetworkProtectionAddressMetadata.deviceAddressCategories(for: path),
                             routerAddressCategories: NetworkProtectionAddressMetadata.routerAddressCategories(for: path))
            }

            // Wait up to 3 seconds to fetch the path.
            let currentExecutionTime = CFAbsoluteTimeGetCurrent() - startTime
            if currentExecutionTime >= 3.0 {
                return .init(currentPath: nil,
                             lastPathChangeDate: lastPathChangeDate,
                             lastPathChange: lastPathChange,
                             secondsSincePathChange: secondsSincePathChange,
                             deviceAddressCategories: [.unknown],
                             routerAddressCategories: [.unknown])
            }
        }
    }

    @MainActor
    func collectVPNState() async -> VPNMetadata.VPNState {
        let status = statusObserver.recentValue
        let connectionState = String(describing: status)
        let connectedServer = serverInfoObserver.recentValue.serverLocation?.serverLocation ?? "none"
        let connectedServerIP = serverInfoObserver.recentValue.serverAddress ?? "none"
        let dataVolume = await collectDataVolumeIfAvailable(for: status)
        let lastDisconnectError = await lastDisconnectError()

        return .init(connectionState: connectionState,
                     lastDisconnectError: lastDisconnectError?.error,
                     underlyingErrors: lastDisconnectError?.underlyingErrors,
                     connectedServer: connectedServer,
                     connectedServerIP: connectedServerIP,
                     dataVolume: dataVolume)
    }

    private func collectDataVolumeIfAvailable(for status: ConnectionStatus) async -> NetworkProtectionDataVolumeBuckets? {
        guard status.canReportActiveDataVolume,
              let activeSession = await tunnelSessionProvider.activeSession(),
              let data: ExtensionMessageString = try? await activeSession.sendProviderMessage(.getDataVolume) else {
            return nil
        }

        let bytes = data.value.components(separatedBy: ",")
        guard let receivedString = bytes.first,
              let sentString = bytes.last,
              let received = Int64(receivedString),
              let sent = Int64(sentString) else {
            return nil
        }

        return NetworkProtectionDataVolumeBuckets(bytesSent: sent, bytesReceived: received)
    }

    public func lastDisconnectError() async -> (error: VPNMetadata.LastDisconnectError, underlyingErrors: [VPNMetadata.LastDisconnectError])? {
        if #available(iOS 16, *) {
            guard let tunnelManager = try? await NETunnelProviderManager.loadAllFromPreferences().first else {
                return nil
            }

            do {
                try await tunnelManager.connection.fetchLastDisconnectError()
                return nil
            } catch {
                return (error as NSError).toMetadataError()
            }
        }

        return nil
    }

    func collectVPNSettingsState() -> VPNMetadata.VPNSettingsState {
        .init(
            connectOnLoginEnabled: settings.connectOnLogin,
            includeAllNetworksEnabled: settings.includeAllNetworks,
            enforceRoutesEnabled: settings.enforceRoutes,
            excludeLocalNetworksEnabled: settings.excludeLocalNetworks,
            excludeCGNATEnabled: settings.excludeCGNAT,
            notifyStatusChangesEnabled: settings.notifyStatusChanges,
            selectedServer: settings.selectedServer.stringValue ?? "automatic",
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

private final class VPNMetadataTunnelSessionProvider: TunnelSessionProvider {
    func activeSession() async -> NETunnelProviderSession? {
        await AppDependencyProvider.shared.networkProtectionTunnelController.activeSession()
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

private extension NSError {

    @available(iOS 16.0, *)
    func toMetadataError() -> (error: VPNMetadata.LastDisconnectError, underlyingErrors: [VPNMetadata.LastDisconnectError]) {
        let metadataError = VPNMetadata.LastDisconnectError(domain: self.domain, code: self.code, description: self.localizedDescription)

        let underlyingErrors = self.underlyingErrors.compactMap { underlyingError in
            let underlyingNSError = underlyingError as NSError
            return VPNMetadata.LastDisconnectError(
                domain: underlyingNSError.domain,
                code: underlyingNSError.code,
                description: underlyingNSError.localizedDescription
            )
        }

        return (metadataError, underlyingErrors)
    }

}

// MARK: - Unified feedback form support

extension VPNMetadata: UnifiedFeedbackMetadata {}

extension DefaultVPNMetadataCollector: UnifiedMetadataCollector {
    convenience init() {
        self.init(
            statusObserver: AppDependencyProvider.shared.connectionObserver,
            serverInfoObserver: AppDependencyProvider.shared.serverInfoObserver
        )
    }

    func collectMetadata() async -> VPNMetadata? {
        await collectVPNMetadata()
    }
}
