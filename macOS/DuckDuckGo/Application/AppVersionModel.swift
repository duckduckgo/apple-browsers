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
    let internalUserDecider: InternalUserDecider

    init(internalUserDecider: InternalUserDecider, appVersion: AppVersion) {
        self.internalUserDecider = internalUserDecider
        self.appVersion = appVersion
    }

#if ALPHA
    let shouldDisplayPrereleaseLabel: Bool = true
    let prereleaseLabel: String = "ALPHA"
    var versionLabel: String {
        let versionText = UserText.versionLabel(version: appVersion.versionNumber, build: appVersion.buildNumber)
        let commitSHA = appVersion.commitSHAShort
        guard !commitSHA.isEmpty else {
            return versionText
        }
        return "\(versionText) [\(commitSHA)]"
    }
#else
    var shouldDisplayPrereleaseLabel: Bool {
        internalUserDecider.isInternalUser
    }
    let prereleaseLabel: String = "BETA"
    var versionLabel: String {
        UserText.versionLabel(version: appVersion.versionNumber, build: appVersion.buildNumber)
    }
#endif
}
