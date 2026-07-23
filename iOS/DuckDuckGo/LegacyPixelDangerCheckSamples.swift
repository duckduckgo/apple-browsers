//
//  LegacyPixelDangerCheckSamples.swift
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
import Core
import PixelKit

/// TEMPORARY scaffold to verify the `legacyPixelUsage` Danger check fires in CI.
/// Each line below is intended to trip one of the check's failure cases.
/// Delete before merging.
enum LegacyPixelDangerCheckSamples {

    static func run() {
        // Case: bare `Pixel.fire`
        Pixel.fire(pixel: .appLaunch)

        // Case: `Pixel.Event` type reference
        let event: Pixel.Event = .appLaunch
        Pixel.fire(pixel: event)

        // Case: DailyPixel
        DailyPixel.fire(pixel: .appLaunch)

        // Case: UniquePixel
        UniquePixel.fire(pixel: .appLaunch)

        // Case: TimedPixel
        let timed = TimedPixel(.appLaunch)
        timed.fire()

        // Case: PersistentPixel
        let persistent: PersistentPixelFiring = PersistentPixel()
        persistent.fire(pixel: .appLaunch,
                        error: nil,
                        includedParameters: [.appVersion],
                        withAdditionalParameters: [:],
                        onComplete: { _ in })

        // Case (should NOT fail): a use of the modern PixelKit system.
        PixelKit.fire(SamplePixelKitEvent(), frequency: .daily)

        // Case (should NOT fail): identifiers that merely contain "pixel" but
        // do not refer to the legacy pixel system.
        let pixelWidth = 10
        let pixelHeight = 20
        let devicePixelRatio = 2.0
        let totalPixels = pixelWidth * pixelHeight
        let dimensions = PixelGridDimensions(width: pixelWidth, height: pixelHeight)
        _ = (devicePixelRatio, totalPixels, dimensions)
    }
}

/// A minimal modern-PixelKit event — present only to show that PixelKit usage
/// does not trip the check.
private struct SamplePixelKitEvent: PixelKitEvent {
    var name: String { "sample_pixelkit_event" }
    var standardParameters: [PixelKitStandardParameter]? { nil }
    var parameters: [String: String]? { nil }
}

/// A type whose name merely contains "Pixel"; unrelated to the legacy pixel system.
private struct PixelGridDimensions {
    let width: Int
    let height: Int
}
