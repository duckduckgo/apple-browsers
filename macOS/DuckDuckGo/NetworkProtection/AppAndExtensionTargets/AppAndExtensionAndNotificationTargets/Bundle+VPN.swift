//
//  Bundle+VPN.swift
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
import NetworkProtection
import Common

extension Bundle {

    private enum VPNInfoKey: String {
        case tunnelAppexBundleID = "TUNNEL_APPEX_BUNDLE_ID"
        case tunnelSysexBundleID = "TUNNEL_SYSEX_BUNDLE_ID"
        case proxyAppexBundleID = "PROXY_APPEX_BUNDLE_ID"
        case proxySysexBundleID = "PROXY_SYSEX_BUNDLE_ID"
    }

    static var tunnelAppexBundleID: String {
        string(for: .tunnelAppexBundleID)
    }

    static var tunnelSysexBundleID: String {
        string(for: .tunnelSysexBundleID)
    }

    static var proxyAppexBundleID: String {
        string(for: .proxyAppexBundleID)
    }

    static var proxySysexBundleID: String {
        string(for: .proxySysexBundleID)
    }

    private static func string(for key: VPNInfoKey) -> String {
        guard let bundleID = Bundle.main.object(forInfoDictionaryKey: key.rawValue) as? String else {
            fatalError("Info.plist is missing \(key)")
        }

        return bundleID
    }

#if !NETWORK_EXTENSION
    // for the Main or Launcher Agent app
    static func mainAppBundle() -> Bundle {
        return Bundle.main
    }
#elseif NETP_SYSTEM_EXTENSION
    // for the System Extension (Developer ID)
    static func mainAppBundle() -> Bundle {
        return Bundle(url: .mainAppBundleURL)!
    }
    // AppEx (App Store) can‘t access Main App Bundle
#endif

    static let keychainType: KeychainType = {
#if NETP_SYSTEM_EXTENSION
        .system
#else
        .dataProtection(.named(Bundle.main.appGroup(bundle: .netP)))
#endif
    }()
}
