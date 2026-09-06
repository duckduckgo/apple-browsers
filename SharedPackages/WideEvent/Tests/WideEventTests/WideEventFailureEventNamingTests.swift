//
//  PixelKitPlatformSuffixPolicyTests.swift
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

import XCTest
import PixelKit
import WideEvent

// MARK: - The one deliberate rename

/// `WideEventFailureEvent` is the single pixel family this change fixes rather than freezes, so
/// pin its resulting names.
final class WideEventFailureEventNamingTests: XCTestCase {

    private func firedNames(source: PixelKit.Source) -> [String] {
        let userDefaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var names: [String] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: source.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, _, _, _, _, _ in
            names.append(firedPixelName)
        }
        pixelKit.fire(WideEventFailureEvent.saveFailed(pixelName: "subscription_purchase",
                                                       error: NSError(domain: "test", code: 1)),
                      frequency: .dailyAndCount)
        return names
    }

    /// `WideEventFailureEvent.namePrefix` is a compile-time `#if`, so a macOS test bundle always
    /// sees `m_mac_` regardless of the `source` passed in. Only the suffix half is reproducible
    /// across platforms, and the suffix half is what this change alters.
#if os(macOS)
    private let prefix = "m_mac_"
#else
    private let prefix = "m_"
#endif

    func testFailureNamesMatchTheDeclaredSuffixOrderOnIOS() {
        XCTAssertEqual(firedNames(source: .iOS),
                       ["\(prefix)wide_pixel_save_failed_daily_ios_phone",
                        "\(prefix)wide_pixel_save_failed_count_ios_phone"])
    }

    func testFailureNamesAreUnchangedOnMacOS() {
        XCTAssertEqual(firedNames(source: .macDMG),
                       ["\(prefix)wide_pixel_save_failed_daily",
                        "\(prefix)wide_pixel_save_failed_count"])
    }
}

