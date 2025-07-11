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
enum CrashPixelAppIdentifier: String {
    case dbp, vpnAgent = "vpnagent", vpnExtension = "vpnextension"

    init?(_ bundleID: String?) {
        guard let bundleID, let mainBundleID = Bundle.main.bundleIdentifier, bundleID != mainBundleID else {
            return nil
        }
        if bundleID.hasSuffix("vpn") {
            self = .vpnAgent
        } else if bundleID.hasSuffix("vpn.network-extension") {
            self = .vpnExtension
        } else if bundleID.hasSuffix("DBP.backgroundAgent") {
            self = .dbp
        } else {
            return nil
        }
    }
}
