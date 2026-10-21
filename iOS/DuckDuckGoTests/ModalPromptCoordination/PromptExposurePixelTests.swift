//
//  PromptExposurePixelTests.swift
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
import PixelKit
import Testing
@testable import DuckDuckGo

@Suite("Prompt Exposure Pixels")
struct PromptExposurePixelTests {
    @available(iOS 16, macOS 13, *)
    @Test("Install age bucket boundaries match the wire contract", .timeLimit(.minutes(1)), arguments: [
        (0, "d0_6"), (6, "d0_6"), (7, "d7_13"), (13, "d7_13"), (14, "d14_20"),
        (20, "d14_20"), (21, "d21_27"), (27, "d21_27"), (28, "d28_plus"), (365, "d28_plus")
    ])
    func installAgeBuckets(days: Int, expected: String) {
        #expect(PromptExposureBuckets.daysSinceInstall(days) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Exposure ordinal bucket boundaries match the wire contract", .timeLimit(.minutes(1)), arguments: [
        (1, "1"), (2, "2"), (3, "3"), (4, "4"), (5, "5"), (6, "6"), (7, "7"), (8, "8"), (9, "9"), (10, "10"),
        (11, "11_15"), (15, "11_15"), (16, "16_20"), (20, "16_20"), (21, "21_plus"), (500, "21_plus")
    ])
    func ordinalBuckets(nth: Int, expected: String) {
        #expect(PromptExposureBuckets.nthInWeek(nth) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Gap bucket boundaries match the wire contract", .timeLimit(.minutes(1)), arguments: [
        (0.0, "lt_1m"), (59, "lt_1m"), (60, "1_5m"), (299, "1_5m"), (300, "5_10m"), (599, "5_10m"),
        (600, "10_30m"), (1799, "10_30m"), (1800, "30_60m"), (3599, "30_60m"), (3600, "1_4h"), (14399, "1_4h"),
        (14400, "4_12h"), (43199, "4_12h"), (43200, "12_24h"), (86399, "12_24h"), (86400, "24_48h"),
        (172799, "24_48h"), (172800, "gt_48h")
    ])
    func gapBuckets(seconds: TimeInterval, expected: String) {
        #expect(PromptExposureBuckets.gap(seconds) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Missing and negative gaps are distinct", .timeLimit(.minutes(1)))
    func missingAndNegativeGaps() {
        #expect(PromptExposureBuckets.gap(nil) == "first")
        #expect(PromptExposureBuckets.gap(-1) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Pixel names and parameter maps match the wire contract", .timeLimit(.minutes(1)))
    func pixelContract() {
        let cases: [(PromptExposurePixel, String, [String: String])] = [
            (.exposure(daysSinceInstall: "d0_6", nthInWeek: "1"), "prompt_exposure",
             ["days_since_install": "d0_6", "nth_in_week": "1", "version": "1", "petal": "randomize"]),
            (.shown(daysSinceInstall: "d7_13", promptID: .appRatingPrompt), "prompt_shown",
             ["days_since_install": "d7_13", "prompt_id": "app_rating_prompt", "version": "1", "petal": "randomize"]),
            (.userWeek(daysSinceInstall: "d14_20"), "prompt_user_week",
             ["days_since_install": "d14_20", "version": "1"]),
            (.gap(daysSinceInstall: "d21_27", gapBucket: "first", promptType: .modal), "prompt_gap",
             ["days_since_install": "d21_27", "gap_bucket": "first", "prompt_type": "MODAL", "version": "1", "petal": "randomize"]),
            (.gap(daysSinceInstall: "d21_27", gapBucket: "1_5m", promptType: .ntpCard), "prompt_gap",
             ["days_since_install": "d21_27", "gap_bucket": "1_5m", "prompt_type": "NTP_CARD", "version": "1", "petal": "randomize"]),
            (.session(daysSinceInstall: "d28_plus", promptShown: true), "prompt_session",
             ["days_since_install": "d28_plus", "prompt_shown": "true", "version": "1", "petal": "randomize"]),
            (.session(daysSinceInstall: "d28_plus", promptShown: false), "prompt_session",
             ["days_since_install": "d28_plus", "prompt_shown": "false", "version": "1", "petal": "randomize"])
        ]
        for (event, name, parameters) in cases {
            #expect(event.name == name)
            #expect(event.namePrefix == .custom("m_"))
            #expect(event.platformSuffixPolicy == .standard)
            #expect(event.parameters == parameters)
            #expect(event.standardParameters == nil)
        }
    }
}
