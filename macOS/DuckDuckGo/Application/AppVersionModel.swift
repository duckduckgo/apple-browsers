//
//  AppVersionModel.swift
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
import Common

/// This class provides unified interface for app version and prerelease labels.
///
/// It can be used whenever the app version and prerelease information
/// needs to be displayed.
final class AppVersionModel {

    let appVersion: AppVersion

    /// Internal user decider is only used in `shouldDisplayPrereleaseLabel`.
    /// If this class only needs to provide the app version, it can be `nil`.
    private let internalUserDecider: InternalUserDecider?

    init(appVersion: AppVersion, internalUserDecider: InternalUserDecider?) {
        self.internalUserDecider = internalUserDecider
        self.appVersion = appVersion
    }

#if ALPHA
    let shouldDisplayPrereleaseLabel: Bool = true
    let prereleaseLabel: String = "ALPHA"
    var versionLabel: String {
        var versionText = UserText.versionLabel(version: appVersion.versionNumber, build: appVersion.buildNumber)
        let commitSHA = appVersion.commitSHAShort
        if !commitSHA.isEmpty {
            versionText.append(" [\(commitSHA)]")
        }
        return versionText
    }
    var versionLabelShort: String {
        var label = "\(appVersion.versionNumber).\(appVersion.buildNumber)"
        let commitSHA = appVersion.commitSHAShort
        if !commitSHA.isEmpty {
            label.append("_\(commitSHA)")
        }
        return label
    }
#else
    var shouldDisplayPrereleaseLabel: Bool {
        internalUserDecider?.isInternalUser == true
    }
    let prereleaseLabel: String = "BETA"
    var versionLabel: String {
        UserText.versionLabel(version: appVersion.versionNumber, build: appVersion.buildNumber)
    }
    var versionLabelShort: String {
        "\(appVersion.versionNumber).\(appVersion.buildNumber)"
    }
#endif
}
