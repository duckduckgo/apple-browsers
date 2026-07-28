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

public enum SnapshotEnvironment {
    public static let expectedIOSVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
    public static let expectedMacOSVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 2)
    public static let expectedIOSDisplayScale = 3.0

    public static func currentValidationMessage() -> String? {
        #if os(iOS)
        return validationMessage(
            platform: .iOS,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion,
            displayScale: currentIOSDisplayScale()
        )
        #elseif os(macOS)
        return validationMessage(
            platform: .macOS,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
        #else
        return "UI snapshots are supported only on iOS and macOS."
        #endif
    }

    public static func validationMessage(
        platform: SnapshotPlatform,
        operatingSystemVersion: OperatingSystemVersion,
        displayScale: Double? = nil
    ) -> String? {
        switch platform {
        case .iOS:
            guard operatingSystemVersion.majorVersion == expectedIOSVersion.majorVersion,
                  operatingSystemVersion.minorVersion == expectedIOSVersion.minorVersion else {
                return "UI snapshots must run on iOS \(expectedVersionString(for: .iOS)). Current OS is \(versionString(operatingSystemVersion))."
            }

            guard let displayScale else {
                return "iOS UI snapshots must run at @\(Int(expectedIOSDisplayScale))x scale. Current scale is unknown."
            }
            guard displayScale == expectedIOSDisplayScale else {
                return "iOS UI snapshots must run at @\(Int(expectedIOSDisplayScale))x scale. Current scale is \(displayScale)."
            }
            return nil

        case .macOS:
            guard operatingSystemVersion.majorVersion == expectedMacOSVersion.majorVersion,
                  operatingSystemVersion.minorVersion == expectedMacOSVersion.minorVersion,
                  operatingSystemVersion.patchVersion == expectedMacOSVersion.patchVersion else {
                return "UI snapshots must run on macOS \(expectedVersionString(for: .macOS)). Current OS is \(versionString(operatingSystemVersion))."
            }
            return nil
        }
    }

    public static func referenceEnvironmentSuffix(
        platform: SnapshotPlatform,
        operatingSystemVersion version: OperatingSystemVersion
    ) -> String {
        switch platform {
        case .iOS:
            return "\(platform.displayName)-\(version.majorVersion)-\(version.minorVersion)"
        case .macOS:
            return "\(platform.displayName)-\(version.majorVersion)-\(version.minorVersion)-\(version.patchVersion)"
        }
    }

    static func currentReferenceEnvironmentSuffix() -> String? {
        #if os(iOS)
        return referenceEnvironmentSuffix(
            platform: .iOS,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
        #elseif os(macOS)
        return referenceEnvironmentSuffix(
            platform: .macOS,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
        #else
        return nil
        #endif
    }

    private static func versionString(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func expectedVersionString(for platform: SnapshotPlatform) -> String {
        switch platform {
        case .iOS:
            return "\(expectedIOSVersion.majorVersion).\(expectedIOSVersion.minorVersion)"
        case .macOS:
            return "\(expectedMacOSVersion.majorVersion).\(expectedMacOSVersion.minorVersion).\(expectedMacOSVersion.patchVersion)"
        }
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
