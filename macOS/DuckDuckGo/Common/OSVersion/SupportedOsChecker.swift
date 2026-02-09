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

import AppKit
import Foundation
import FeatureFlags
import PrivacyConfig

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

    /// Whether the hardware supports a macOS version newer than the currently running one.
    ///
    var hardwareSupportsNewerOS: Bool { get }
}

extension SupportedOSChecking {
    var showsSupportWarning: Bool {
        supportWarning != nil
    }
    var hardwareSupportsNewerOS: Bool {
        false
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

    /// Lookup table mapping hardware model identifiers to the major component of the maximum macOS version they support.
    ///
    static let maxSupportedMacOSVersionByModel: [String: Int] = [
        "iMac14,4": 11,
        "iMac15,1": 11,
        "MacBook8,1": 11,
        "MacBookAir6,1": 11,
        "MacBookAir6,2": 11,
        "MacBookPro11,1": 11,
        "MacBookPro11,2": 11,
        "MacBookPro11,3": 11
    ]

    private var currentOSVersion: OperatingSystemVersion {
        if let currentOSVersionOverride {
            return currentOSVersionOverride
        }

        return ProcessInfo.processInfo.operatingSystemVersion
    }
    private var currentOSVersionOverride: OperatingSystemVersion?
    private var minSupportedOSVersionOverride: OperatingSystemVersion?
    private var upcomingMinSupportedOSVersionOverride: OperatingSystemVersion?
    private var hardwareModelOverride: String?
    private var maxSupportedVersionByModelOverride: [String: Int]?
    private let featureFlagger: FeatureFlagger

    var minSupportedOSVersion: OperatingSystemVersion {
        if let minSupportedOSVersionOverride {
            return minSupportedOSVersionOverride
        }

        return Self.ddgMinBigSurVersion
    }

    var upcomingMinSupportedOSVersion: OperatingSystemVersion? {
        if let upcomingMinSupportedOSVersionOverride {
            return upcomingMinSupportedOSVersionOverride
        }

        guard featureFlagger.isFeatureOn(.willSoonDropBigSurSupport) else {
            return nil
        }

        return Self.ddgMinMonterreyVersion
    }

    private var hardwareModel: String? {
        hardwareModelOverride ?? HardwareModel.model
    }

    private var maxSupportedVersionByModel: [String: Int] {
        maxSupportedVersionByModelOverride ?? Self.maxSupportedMacOSVersionByModel
    }

    init(featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         currentOSVersionOverride: OperatingSystemVersion? = nil,
         minSupportedOSVersionOverride: OperatingSystemVersion? = nil,
         upcomingMinSupportedOSVersionOverride: OperatingSystemVersion? = nil,
         hardwareModelOverride: String? = nil,
         maxSupportedVersionByModelOverride: [String: Int]? = nil) {

        self.currentOSVersionOverride = currentOSVersionOverride
        self.minSupportedOSVersionOverride = minSupportedOSVersionOverride
        self.upcomingMinSupportedOSVersionOverride = upcomingMinSupportedOSVersionOverride
        self.hardwareModelOverride = hardwareModelOverride
        self.maxSupportedVersionByModelOverride = maxSupportedVersionByModelOverride
        self.featureFlagger = featureFlagger
    }

    private func osVersionAsString(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion)"
    }
}

extension SupportedOSChecker: SupportedOSChecking {

    var supportWarning: OSSupportWarning? {

        // It's best to check feature flags first on their own, since they act as a master
        // override for any other check
        guard !featureFlagger.isFeatureOn(.osSupportForceUnsupportedMessage) else {
            return .unsupported(osVersionAsString(minSupportedOSVersion))
        }

        if let upcomingMinSupportedOSVersion {
            guard !featureFlagger.isFeatureOn(.osSupportForceWillSoonDropSupportMessage) else {
                return .willDropSupportSoon(osVersionAsString(upcomingMinSupportedOSVersion))
            }
        }

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

    var hardwareSupportsNewerOS: Bool {
        guard let model = hardwareModel else {
            return false
        }

        guard let maxSupportedOS = maxSupportedVersionByModel[model] else {
            return false
        }

        let maxVersion = maxSupportedOS
        let currentVersion = currentOSVersion.majorVersion
        return maxVersion > currentVersion
    }
}
