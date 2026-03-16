//
//  DataClearingPixelsReporter.swift
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
import QuartzCore
import PixelKit

final class DataClearingPixelsReporter {

    var timeProvider: () -> CFTimeInterval
    private let pixelFiring: PixelFiring?

    @MainActor
    private var lastFireTime: CFTimeInterval?
    private let retriggerWindow: TimeInterval = 20.0

    init(pixelFiring: PixelFiring? = PixelKit.shared, timeProvider: @escaping () -> CFTimeInterval = { CACurrentMediaTime() }) {
        self.pixelFiring = pixelFiring
        self.timeProvider = timeProvider
    }

    @MainActor
    func fireRetriggerPixelIfNeeded() {
        let now = timeProvider()
        if let lastFire = lastFireTime, (now - lastFire) <= retriggerWindow {
            pixelFiring?.fire(DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        }
        lastFireTime = now
    }
}
