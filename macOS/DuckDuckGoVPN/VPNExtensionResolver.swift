//
//  VPNExtensionResolver.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import FeatureFlags
import Foundation
import NetworkProtectionUI
import VPNAppState
import VPNExtensionManagement

final class VPNExtensionResolver {

    public enum AvailableExtensions {
        case both(appexBundleID: String, sysexBundleID: String)
        case sysex(sysexBundleID: String)
    }

    private let availableExtensions: AvailableExtensions
    private let featureFlagger: FeatureFlagger
    private let vpnAppState: VPNAppState
    private let isConfigurationInstalled: (_ extensionBundleID: String) async -> Bool

    init(availableExtensions: AvailableExtensions,
         featureFlagger: FeatureFlagger,
         vpnAppState: VPNAppState = VPNAppState(defaults: .netP),
         isConfigurationInstalled: @escaping (_ extensionBundleID: String) async -> Bool) {

        self.availableExtensions = availableExtensions
        self.featureFlagger = featureFlagger
        self.vpnAppState = vpnAppState
        self.isConfigurationInstalled = isConfigurationInstalled
    }

    /// Whether the controller is using a System Extension or an App Extension.
    ///
    var isUsingSystemExtension: Bool {
        get async {
            switch availableExtensions {
            case .both(let appexBundleID, _):
                guard featureFlagger.isFeatureOn(.networkProtectionAppStoreSysex) else {
                    vpnAppState.isUsingSystemExtension = false
                    return false
                }

                let result = await !isConfigurationInstalled(appexBundleID)
                vpnAppState.isUsingSystemExtension = result
                return result
            case .sysex:
                vpnAppState.isUsingSystemExtension = true
                return true
            }
        }
    }
}

extension VPNExtensionResolver: VPNExtensionResolving {

    var activeExtensionBundleID: String {
        get async {
            switch availableExtensions {
            case .both(let appexBundleID, let sysexBundleID):
                guard featureFlagger.isFeatureOn(.networkProtectionAppStoreSysex),
                      await !isConfigurationInstalled(appexBundleID) else {

                    return appexBundleID
                }

                return sysexBundleID
            case .sysex(let sysexBundleID):
                return sysexBundleID
            }
        }
    }
}
