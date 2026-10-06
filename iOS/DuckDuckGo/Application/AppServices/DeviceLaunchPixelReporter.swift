//
//  DeviceLaunchPixelReporter.swift
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

import Darwin
import FeatureFlags_iOS
import Foundation
import PixelKit
import PrivacyConfig

struct DeviceLaunchPixelReporter {
    private let featureFlagger: FeatureFlagger
    private let machineIdentifier: () -> String?
    private let pixelFiring: PixelFiring?

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         machineIdentifier: @escaping () -> String? = { Self.hardwareMachine() },
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.featureFlagger = featureFlagger
        self.machineIdentifier = machineIdentifier
        self.pixelFiring = pixelFiring
    }

    static func hardwareMachine() -> String? {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBufferPointer {
            sysctlbyname("hw.machine", $0.baseAddress, &size, nil, 0)
        }
        guard result == 0, let terminator = buffer.firstIndex(of: 0), terminator > 0 else { return nil }
        return String(bytes: buffer[..<terminator].map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }

    func reportLaunch() {
        guard featureFlagger.isFeatureOn(.iPhoneDuoLaunchReporting),
              machineIdentifier() == "iPhone19,4" else { return }
        pixelFiring?.fire(DeviceLaunchPixel.iPhoneDuoLaunched, frequency: .daily)
    }
}
