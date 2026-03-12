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

import Common
import PrivacyConfig

/// This class provides unified interface for app version and prerelease labels.
///
/// It can be used whenever the app version and prerelease information
/// needs to be displayed.
final class AppVersionModel {

    let appVersion: AppVersion

    /// Internal user decider is only used in `shouldDisplayPrereleaseLabel`.
    /// If this class only needs to provide the app version, it can be `nil`.
    private let internalUserDecider: InternalUserDecider?

    private let buildType: ApplicationBuildType

    init(appVersion: AppVersion = AppVersion(), internalUserDecider: InternalUserDecider? = nil, buildType: ApplicationBuildType = StandardApplicationBuildType()) {
        self.internalUserDecider = internalUserDecider
        self.appVersion = appVersion
        self.buildType = buildType
    }

    var shouldDisplayPrereleaseLabel: Bool {
        if buildType.isAlphaBuild {
            return true
        }
        return internalUserDecider?.isInternalUser == true
    }

    var prereleaseLabel: String {
        buildType.isAlphaBuild ? "ALPHA" : "BETA"
    }

    var versionLabel: String {
        var versionText = UserText.versionLabel(version: appVersion.versionNumber, build: appVersion.buildNumber)
        if buildType.isAlphaBuild {
            let commitSHA = appVersion.commitSHAShort
            if !commitSHA.isEmpty {
                versionText.append(" [\(commitSHA)]")
            }
        }
        return versionText
    }

    var versionLabelShort: String {
        var label = "\(appVersion.versionNumber).\(appVersion.buildNumber)"
        if buildType.isAlphaBuild {
            let commitSHA = appVersion.commitSHAShort
            if !commitSHA.isEmpty {
                label.append("_\(commitSHA)")
            }
        }
        return label
    }
}
