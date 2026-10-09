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

import FeatureFlags_iOS
import Foundation
import PixelKit
import PrivacyConfig

/// Measure daily Duo use to guide app improvements while obscuring launch timing.
struct DeviceLaunchPixelReporter {
    private static let iPhoneDuoModelIdentifier = "iPhone19,4"

    private let featureFlagger: FeatureFlagger
    private let machineIdentifier: () -> String?
    private let pixelFiring: PixelFiring?
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(featureFlagger: FeatureFlagger,
         machineIdentifier: @escaping () -> String? = { HardwareModel.model },
         pixelFiring: PixelFiring?,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        self.featureFlagger = featureFlagger
        self.machineIdentifier = machineIdentifier
        self.pixelFiring = pixelFiring
        self.schedule = schedule
    }

    func reportLaunch() {
        guard featureFlagger.isFeatureOn(.iPhoneDuoLaunchReporting),
              machineIdentifier() == Self.iPhoneDuoModelIdentifier else { return }
        // Delay sending to reduce correlation with the user’s launch time.
        schedule(TimeInterval.random(in: 1...30)) {
            guard featureFlagger.isFeatureOn(.iPhoneDuoLaunchReporting) else { return }
            pixelFiring?.fire(DeviceLaunchPixel.iPhoneDuoLaunched, frequency: .daily, options: .withoutAppVersion)
        }
    }
}
