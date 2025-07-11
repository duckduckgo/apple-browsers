//
//  CrashPixelAppIdentifier.swift
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

import Foundation

/// Represents the identifier of the crashed bundle. It's used by `GeneralPixel.crash`
///
/// For crashes happening in main bundle it should remain `nil`, otherwise it can take one of the predefined values for known bundles.
enum CrashPixelAppIdentifier: String, CaseIterable {
    case dbp, vpnAgent = "vpnagent", vpnExtension = "vpnextension"

    init?(_ bundleID: String?, mainBundleID: String? = Bundle.main.bundleIdentifier) {
        guard let bundleID, let mainBundleID, bundleID != mainBundleID else {
            return nil
        }

        if let matchingBundleID = Self.allCases.first(where: { $0.bundleIDs.contains(bundleID) }) {
            self = matchingBundleID
        } else if let matchingSuffix = Self.allCases.first(where: { $0.bundleSuffixes.contains(where: { bundleID.hasSuffix($0) }) }) {
            self = matchingSuffix
        } else {
            return nil
        }
    }

    private var bundleSuffixes: Set<String> {
        switch self {
        case .dbp:
            return ["DBP.backgroundAgent"]
        case .vpnAgent:
            return ["vpn.agent"]
        case .vpnExtension:
            return [
                "vpn.agent.network-protection-extension",
                "vpn.agent.network-extension",
                "vpn.agent.proxy"
            ]
        }
    }

    private var bundleIDs: Set<String> {
        switch self {
        case .dbp:
            return []
        case .vpnAgent:
            return [
                "com.duckduckgo.macos.vpn",
                "com.duckduckgo.macos.vpn.debug",
                "com.duckduckgo.macos.vpn.review"
            ]
        case .vpnExtension:
            return [
                "com.duckduckgo.macos.vpn.network-extension",
                "com.duckduckgo.macos.vpn.network-extension.debug",
                "com.duckduckgo.macos.vpn.network-extension.review"
            ]
        }
    }
}
