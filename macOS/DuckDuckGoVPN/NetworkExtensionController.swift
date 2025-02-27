//
//  NetworkExtensionController.swift
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

import BrowserServicesKit
import Foundation
import NetworkExtension
import NetworkProtection
import NetworkProtectionUI
import SystemExtensionManager
import SystemExtensions

/// The VPN's network extension session object.
///
/// Through this class the app that owns the VPN can interact with the network extension.
///
final class NetworkExtensionController {

    enum AvailableExtensions {
        case both(appexBundleID: String, sysexBundleID: String)
        case sysex(sysexBundleID: String)
    }

    private let availableExtensions: AvailableExtensions
    private let featureFlagger: FeatureFlagger
    private let systemExtensionManager: SystemExtensionManager
    private let defaults: UserDefaults

    init(availableExtensions: AvailableExtensions, featureFlagger: FeatureFlagger, defaults: UserDefaults = .netP) {

        self.availableExtensions = availableExtensions
        self.defaults = defaults
        self.featureFlagger = featureFlagger

        switch availableExtensions {
            case .both(_, sysexBundleID: let sysexBundleID):
                systemExtensionManager = SystemExtensionManager(extensionBundleID: sysexBundleID)
            case .sysex(sysexBundleID: let sysexBundleID):
                systemExtensionManager = SystemExtensionManager(extensionBundleID: sysexBundleID)
        }
    }
}

extension NetworkExtensionController {

    /// Whether the controller is using a System Extension or an App Extension.
    ///
    var isUsingSystemExtension: Bool {
        get async {
            switch availableExtensions {
            case .both(let appexBundleID, _):
                guard featureFlagger.isFeatureOn(.networkProtectionAppStoreSysex) else {
                    return false
                }

                return await !isConfigurationInstalled(extensionBundleID: appexBundleID)
            case .sysex:
                return true
            }
        }
    }

    private func isConfigurationInstalled(extensionBundleID: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let manager = NEVPNManager.shared()

            manager.loadFromPreferences { error in
                guard error == nil else {
                    continuation.resume(returning: false)
                    return
                }

                if let protocolConfigs = manager.protocolConfiguration as? NETunnelProviderProtocol,
                   protocolConfigs.providerBundleIdentifier == extensionBundleID {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func activateSystemExtension(waitingForUserApproval: @escaping () -> Void) async throws {
        guard await isUsingSystemExtension else {
            return
        }

        if let extensionVersion = try await systemExtensionManager.activate(waitingForUserApproval: waitingForUserApproval) {

            NetworkProtectionLastVersionRunStore(userDefaults: defaults).lastExtensionVersionRun = extensionVersion
        }

        try await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
    }

    func deactivateSystemExtension() async throws {
        guard await isUsingSystemExtension else {
            return
        }

        do {
            try await systemExtensionManager.deactivate()
        } catch OSSystemExtensionError.extensionNotFound {
            // This is an intentional no-op to silence this type of error
            // since on deactivation this is ok.
        } catch {
            throw error
        }
    }

}
