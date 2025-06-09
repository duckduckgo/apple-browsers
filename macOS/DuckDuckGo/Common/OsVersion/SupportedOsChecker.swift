//
//  SupportedOsChecker.swift
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
import FeatureFlags

protocol SupportedOSChecking {
    /// Whether the current OS version is receiving updates
    ///
    var isCurrentOSReceivingUpdates: Bool { get }

    /// The user-facing version string for the current OS version
    ///
    var currentOSVersionString: String { get }

    /// The user-facing version string for the minimum supported OS version
    ///
    var minSupportedOSVersionString: String { get }
}

final class SupportedOSChecker: SupportedOSChecking {
    static let ddgMinBigSurVersion = OperatingSystemVersion(majorVersion: 11,
                                                            minorVersion: 4,
                                                            patchVersion: 0)
    static let ddgMinMonterreyVersion = OperatingSystemVersion(majorVersion: 12,
                                                               minorVersion: 3,
                                                               patchVersion: 0)
    private let currentOSVersion: OperatingSystemVersion

    private let featureFlagger: FeatureFlagger

    var supportedOSVersion: OperatingSystemVersion {
        guard featureFlagger.isFeatureOn(.minimumSupportedVersionIsMonterrey) else {
            return Self.ddgMinBigSurVersion
        }

        return Self.ddgMinMonterreyVersion
    }

    init(featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         currentOSVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) {

        self.currentOSVersion = currentOSVersion
        self.featureFlagger = featureFlagger
    }

    // Check if the current macOS version is at least the supported version
    var isCurrentOSReceivingUpdates: Bool {
        if currentOSVersion.majorVersion > supportedOSVersion.majorVersion {
            return true
        }
        if currentOSVersion.majorVersion == supportedOSVersion.majorVersion {
            if currentOSVersion.minorVersion > supportedOSVersion.minorVersion {
                return true
            }
            if currentOSVersion.minorVersion == supportedOSVersion.minorVersion && currentOSVersion.patchVersion >= supportedOSVersion.patchVersion {
                return true
            }
        }
        return false
    }

    var currentOSVersionString: String {
        "\(ProcessInfo.processInfo.operatingSystemVersion)"
    }

    var minSupportedOSVersionString: String {
        "\(supportedOSVersion.majorVersion).\(supportedOSVersion.minorVersion)"
    }
}
