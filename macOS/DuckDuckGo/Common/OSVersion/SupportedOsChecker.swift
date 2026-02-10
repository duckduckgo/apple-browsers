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

enum OSUpgradeCapability: String {
    case capable
    case incapable
    case unknown

    /// Converts capability to pixel-friendly value for the boolean-style "can_update" parameter
    var pixelValue: String {
        switch self {
        case .capable: return "yes"
        case .incapable: return "no"
        case .unknown: return "unknown"
        }
    }
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

    /// The hardware's capability to upgrade to a macOS version newer than the currently running one.
    ///
    /// Returns `.capable` when the hardware can upgrade, `.incapable` when it cannot, or `.unknown` when
    /// the capability cannot be determined (e.g., hardware model unavailable).
    ///
    /// For models not present in the hardcoded mapping, this returns `.capable`, assuming newer hardware.
    ///
    var osUpgradeCapability: OSUpgradeCapability { get }
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

    /// Lookup table mapping hardware model identifiers to the major component of the maximum macOS version they support.
    ///
    /// Data sourced from https://everymac.com/systems/by_capability/maximum-macos-supported.html
    ///
    static let maxSupportedMacOSVersionByModel: [String: Int] = [
        // Big Sur (11)
        "iMac14,4": 11,
        "iMac15,1": 11,
        "MacBook8,1": 11,
        "MacBookAir6,1": 11,
        "MacBookAir6,2": 11,
        "MacBookPro11,1": 11,
        "MacBookPro11,2": 11,
        "MacBookPro11,3": 11,
        // Monterey (12)
        "iMac16,1": 12,
        "iMac16,2": 12,
        "iMac17,1": 12,
        "MacBook9,1": 12,
        "MacBookAir7,1": 12,
        "MacBookAir7,2": 12,
        "MacBookPro11,4": 12,
        "MacBookPro11,5": 12,
        "MacBookPro12,1": 12,
        "MacBookPro13,1": 12,
        "MacBookPro13,2": 12,
        "MacBookPro13,3": 12,
        "Macmini7,1": 12,
        // Ventura (13)
        "iMac18,1": 13,
        "iMac18,2": 13,
        "iMac18,3": 13,
        "MacBookPro14,1": 13,
        "MacBookPro14,2": 13,
        "MacBookPro14,3": 13,
        // Sonoma (14)
        "MacBookAir8,1": 14,
        "MacBookAir8,2": 14,
        // Sequoia (15)
        "iMac19,1": 15,
        "iMac19,2": 15,
        "iMacPro1,1": 15,
        "MacBookAir9,1": 15,
        "MacBookPro15,1": 15,
        "MacBookPro15,2": 15,
        "MacBookPro15,3": 15,
        "MacBookPro15,4": 15,
        "MacBookPro16,3": 15,
        "Macmini8,1": 15,
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
    private let hardwareModel: String?
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

    private var maxSupportedVersionByModel: [String: Int] {
        maxSupportedVersionByModelOverride ?? Self.maxSupportedMacOSVersionByModel
    }

    init(featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
         currentOSVersionOverride: OperatingSystemVersion? = nil,
         minSupportedOSVersionOverride: OperatingSystemVersion? = nil,
         upcomingMinSupportedOSVersionOverride: OperatingSystemVersion? = nil,
         hardwareModel: String? = HardwareModel.model,
         maxSupportedVersionByModelOverride: [String: Int]? = nil) {

        self.currentOSVersionOverride = currentOSVersionOverride
        self.minSupportedOSVersionOverride = minSupportedOSVersionOverride
        self.upcomingMinSupportedOSVersionOverride = upcomingMinSupportedOSVersionOverride
        self.hardwareModel = hardwareModel
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

    var osUpgradeCapability: OSUpgradeCapability {
        guard let model = hardwareModel else {
            return .unknown
        }

        guard let maxSupportedOS = maxSupportedVersionByModel[model] else {
            // Given model is not on the list so we assume hardware supports newer OS versions
            return .capable
        }

        let maxVersion = maxSupportedOS
        let currentVersion = currentOSVersion.majorVersion
        return maxVersion > currentVersion ? .capable : .incapable
    }
}
