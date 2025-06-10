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

enum OSSupportWarning {
    case unsupported(_ minVersion: String)
    case willDropSupportSoon(_ upcomingMinVersion: String)
}

protocol SupportedOSChecking {

    /// Whether a OS-support warning should be shown to the user.
    ///
    var showsSupportWarning: Bool { get }

    /// The OS-support warning to show to the user.
    ///
    /// This can be either due to the user's macOS version becoming unsupported or
    /// to let the user know it will soon be.
    ///
    var supportWarning: OSSupportWarning? { get }
}

extension SupportedOSChecking {
    var showsSupportWarning: Bool {
        supportWarning != nil
    }
}

extension OperatingSystemVersion: @retroactive Comparable {
    public static func == (lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        lhs.majorVersion == rhs.majorVersion
        && lhs.minorVersion == rhs.minorVersion
    }

    public static func > (lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        lhs.majorVersion > rhs.majorVersion
        || (lhs.majorVersion == rhs.majorVersion
            && (lhs.minorVersion > rhs.minorVersion
                || lhs.minorVersion == rhs.minorVersion && lhs.patchVersion >= rhs.patchVersion))
    }

    public static func < (lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        !(lhs > rhs)
    }
}

final class SupportedOSChecker {
    static let ddgMinBigSurVersion = OperatingSystemVersion(majorVersion: 11,
                                                            minorVersion: 4,
                                                            patchVersion: 0)
    static let ddgMinMonterreyVersion = OperatingSystemVersion(majorVersion: 12,
                                                               minorVersion: 3,
                                                               patchVersion: 0)
    private var currentOSVersion: OperatingSystemVersion {
        if let currentOSVersionOverride {
            return currentOSVersionOverride
        }

        guard !featureFlagger.isFeatureOn(.osSupportPretendImOnBigSur) else {
            return Self.ddgMinBigSurVersion
        }

        return ProcessInfo.processInfo.operatingSystemVersion
    }
    private var currentOSVersionOverride: OperatingSystemVersion?
    private let featureFlagger: FeatureFlagger

    var minSupportedOSVersion: OperatingSystemVersion {
        Self.ddgMinBigSurVersion
    }

    var upcomingMinSupportedOSVersion: OperatingSystemVersion? {
        guard featureFlagger.isFeatureOn(.willSoonDropBigSurSupport) else {
            return nil
        }

        return Self.ddgMinMonterreyVersion
    }

    init(featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         currentOSVersionOverride: OperatingSystemVersion? = nil) {

        self.currentOSVersionOverride = currentOSVersionOverride
        self.featureFlagger = featureFlagger
    }

    var currentOSVersionString: String {
        "\(ProcessInfo.processInfo.operatingSystemVersion)"
    }

    private func osVersionAsString(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion)"
    }
}

extension SupportedOSChecker: SupportedOSChecking {

    var supportWarning: OSSupportWarning? {
        guard currentOSVersion > minSupportedOSVersion else {
            return .unsupported(osVersionAsString(minSupportedOSVersion))
        }

        if let upcomingMinSupportedOSVersion {
            guard currentOSVersion > upcomingMinSupportedOSVersion else {
                return .willDropSupportSoon(osVersionAsString(upcomingMinSupportedOSVersion))
            }
        }

        return nil
    }
}
