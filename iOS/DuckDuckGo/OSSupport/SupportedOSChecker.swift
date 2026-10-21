//
//  SupportedOSChecker.swift
//  DuckDuckGo
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

enum OSUpgradeCapability: String {
    case capable
    case incapable
    case unknown

    /// Whether the OS can be upgraded.
    var canUpgradeOS: Bool {
        switch self {
        case .capable, .unknown: return true
        case .incapable: return false
        }
    }
}

protocol SupportedOSChecking {

    /// The hardware's capability to upgrade to an iOS version newer than the currently running one.
    ///
    /// Returns `.capable` when the hardware can upgrade, `.incapable` when it cannot, or `.unknown` when
    /// the hardware model cannot be determined.
    ///
    /// For models not present in the hardcoded mapping, this returns `.capable`, assuming newer hardware.
    ///
    var osUpgradeCapability: OSUpgradeCapability { get }
}

struct SupportedOSChecker: SupportedOSChecking {

    /// Lookup table mapping hardware model identifiers to the major component of the maximum iOS version they support.
    ///
    /// Data sourced from https://everymac.com/systems/by_capability/maximum-ios-supported-by-all-iphone.html
    /// and https://everymac.com/systems/by_capability/maximum-ipados-supported-by-all-ipad.html
    ///
    static let maxSupportedIOSVersionByModel: [String: Int] = [
        // iOS 15
        "iPhone8,1": 15, // iPhone 6s
        "iPhone8,2": 15, // iPhone 6s Plus
        "iPhone8,4": 15, // iPhone SE (1st gen)
        "iPhone9,1": 15, // iPhone 7
        "iPhone9,3": 15, // iPhone 7
        "iPhone9,2": 15, // iPhone 7 Plus
        "iPhone9,4": 15, // iPhone 7 Plus
        "iPod9,1": 15, // iPod touch (7th gen)
        "iPad5,1": 15, // iPad mini 4
        "iPad5,2": 15, // iPad mini 4
        "iPad5,3": 15, // iPad Air 2
        "iPad5,4": 15, // iPad Air 2
        // iOS 16
        "iPhone10,1": 16, // iPhone 8
        "iPhone10,4": 16, // iPhone 8
        "iPhone10,2": 16, // iPhone 8 Plus
        "iPhone10,5": 16, // iPhone 8 Plus
        "iPhone10,3": 16, // iPhone X
        "iPhone10,6": 16, // iPhone X
        "iPad6,11": 16, // iPad (5th gen)
        "iPad6,12": 16, // iPad (5th gen)
        "iPad6,3": 16, // iPad Pro 9.7" (1st gen)
        "iPad6,4": 16, // iPad Pro 9.7" (1st gen)
        "iPad6,7": 16, // iPad Pro 12.9" (1st gen)
        "iPad6,8": 16, // iPad Pro 12.9" (1st gen)
    ]

    private let currentOSMajorVersion: Int
    private let hardwareModel: String?
    private let maxSupportedVersionByModel: [String: Int]

    init(currentOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
         hardwareModel: String? = HardwareModel.model,
         maxSupportedVersionByModel: [String: Int] = Self.maxSupportedIOSVersionByModel) {
        self.currentOSMajorVersion = currentOSMajorVersion
        self.hardwareModel = hardwareModel
        self.maxSupportedVersionByModel = maxSupportedVersionByModel
    }

    var osUpgradeCapability: OSUpgradeCapability {
        guard let model = hardwareModel else {
            return .unknown
        }

        guard let maxSupportedOS = maxSupportedVersionByModel[model] else {
            // Given model is not on the list so we assume hardware supports newer OS versions
            return .capable
        }

        return maxSupportedOS > currentOSMajorVersion ? .capable : .incapable
    }
}

enum HardwareModel {

    /// The hardware model identifier, e.g. `iPhone9,1`.
    static var model: String? {
        #if targetEnvironment(simulator)
        // `uname` reports the host architecture on the simulator.
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
        }
        guard let model, !model.isEmpty else {
            return nil
        }
        return model
        #endif
    }
}
