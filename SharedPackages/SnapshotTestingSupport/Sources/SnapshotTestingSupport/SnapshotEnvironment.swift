//
//  SnapshotEnvironment.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

#if os(iOS)
import UIKit
#endif

public enum SnapshotPlatform: Equatable {
    case iOS
    case macOS

    var displayName: String {
        switch self {
        case .iOS:
            return "iOS"
        case .macOS:
            return "macOS"
        }
    }
}

public enum SnapshotComparisonMode: Equatable {
    case compare
    case skipComparison(reason: String)
    case unsupported(reason: String)
}

public enum SnapshotEnvironment {
    public static let expectedIOSVersion = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
    public static let ciMacOSVersion = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
    public static let expectedIOSDisplayScale = 3.0

    public static func currentComparisonMode() -> SnapshotComparisonMode {
        #if os(iOS)
        return comparisonMode(
            platform: .iOS,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion,
            displayScale: currentIOSDisplayScale()
        )
        #elseif os(macOS)
        return comparisonMode(
            platform: .macOS,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
        #else
        return .unsupported(reason: "UI snapshots are supported only on iOS and macOS.")
        #endif
    }

    public static func comparisonMode(
        platform: SnapshotPlatform,
        operatingSystemVersion: OperatingSystemVersion,
        displayScale: Double? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SnapshotComparisonMode {
        switch platform {
        case .iOS:
            guard operatingSystemVersion.majorVersion == expectedIOSVersion.majorVersion,
                  operatingSystemVersion.minorVersion == expectedIOSVersion.minorVersion else {
                return .unsupported(reason: "UI snapshots must run on iOS \(majorMinorString(expectedIOSVersion)). Current OS is \(versionString(operatingSystemVersion)).")
            }

            guard let displayScale else {
                return .unsupported(reason: "iOS UI snapshots must run at @\(Int(expectedIOSDisplayScale))x scale. Current scale is unknown.")
            }
            guard displayScale == expectedIOSDisplayScale else {
                return .unsupported(reason: "iOS UI snapshots must run at @\(Int(expectedIOSDisplayScale))x scale. Current scale is \(displayScale).")
            }
            return .compare

        case .macOS:
            guard operatingSystemVersion.majorVersion == ciMacOSVersion.majorVersion else {
                return .unsupported(reason: "UI snapshots must run on macOS \(ciMacOSVersion.majorVersion). Current OS is \(versionString(operatingSystemVersion)).")
            }
            if operatingSystemVersion.minorVersion == ciMacOSVersion.minorVersion {
                return .compare
            }
            if SnapshotRecordMode.requiresReferences(environment: environment) {
                return .unsupported(reason: "Snapshot references are verified on macOS \(majorMinorString(ciMacOSVersion)), the CI version. Current OS is \(versionString(operatingSystemVersion)).")
            }
            if SnapshotRecordMode.forcesComparison(environment: environment) {
                return .compare
            }
            return .skipComparison(reason: "macOS \(versionString(operatingSystemVersion)) isn't the CI version (\(majorMinorString(ciMacOSVersion))), so existing references aren't compared and CI verifies them instead. Missing references are still recorded. Set \(SnapshotRecordMode.compareEnvironmentVariableName)=1 to compare anyway.")
        }
    }

    public static func referenceEnvironmentSuffix(
        platform: SnapshotPlatform,
        operatingSystemVersion version: OperatingSystemVersion
    ) -> String? {
        switch platform {
        case .iOS:
            return "\(platform.displayName)-\(version.majorVersion)-\(version.minorVersion)"
        case .macOS:
            return nil
        }
    }

    static func currentReferenceEnvironmentSuffix() -> String? {
        #if os(iOS)
        return referenceEnvironmentSuffix(
            platform: .iOS,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
        #else
        return nil
        #endif
    }

    private static func versionString(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func majorMinorString(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion)"
    }

    #if os(iOS)
    private static func currentIOSDisplayScale() -> Double? {
        let scale = UITraitCollection.current.displayScale
        guard scale > 0 else {
            return nil
        }
        return Double(scale)
    }
    #endif
}
