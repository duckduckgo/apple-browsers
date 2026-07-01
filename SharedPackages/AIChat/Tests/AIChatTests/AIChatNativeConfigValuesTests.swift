//
//  AIChatNativeConfigValuesTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import AIChat

final class AIChatNativeConfigValuesTests: XCTestCase {

    private let referenceNow = Date(timeIntervalSince1970: 1_700_000_000) // fixed "now"

    private func date(daysBeforeNow days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: referenceNow)!
    }

    // MARK: - installAgeBucket

    func testWhenInstallDateIsNilThenBucketIsZero() {
        XCTAssertEqual(AIChatNativeConfigValues.installAgeBucket(installDate: nil, now: referenceNow), 0)
    }

    func testInstallAgeBucketBoundaries() {
        let expectations: [(daysAgo: Int, bucket: Int)] = [
            (0, 0),   // same day
            (1, 1), (7, 1),    // 1–7
            (8, 2), (14, 2),   // 8–14
            (15, 3), (21, 3),  // 15–21
            (22, 4), (28, 4),  // 22–28
            (29, 5), (400, 5)  // after day 28
        ]

        for expectation in expectations {
            let bucket = AIChatNativeConfigValues.installAgeBucket(installDate: date(daysBeforeNow: expectation.daysAgo), now: referenceNow)
            XCTAssertEqual(bucket, expectation.bucket, "Expected bucket \(expectation.bucket) for install \(expectation.daysAgo) days ago, got \(bucket)")
        }
    }

    func testWhenInstallDateIsInTheFutureThenBucketIsZero() {
        let future = Calendar.current.date(byAdding: .day, value: 5, to: referenceNow)!
        XCTAssertEqual(AIChatNativeConfigValues.installAgeBucket(installDate: future, now: referenceNow), 0)
    }

    func testSameCalendarDayLaterTimeIsBucketZero() {
        // Installed earlier the same calendar day -> still "same day" (0), not 1.
        let installed = Calendar.current.startOfDay(for: referenceNow)
        XCTAssertEqual(AIChatNativeConfigValues.installAgeBucket(installDate: installed, now: referenceNow), 0)
    }

    // MARK: - Wire format

    func testInstallTypeEncodesToExpectedStrings() throws {
        XCTAssertEqual(try encodedRawValue(.new), "new")
        XCTAssertEqual(try encodedRawValue(.returning), "returning")
        XCTAssertEqual(try encodedRawValue(.unknown), "unknown")
    }

    func testConfigValuesEncodeInstallTypeAndInstallAge() throws {
        let config = AIChatNativeConfigValues.defaultValues
        let data = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["installType"])
        XCTAssertNotNil(json["installAge"])
    }

    func testConfigValuesEncodeSupportsSuggestions() throws {
        let json = try jsonObject(makeConfig(supportsSuggestions: true))
        XCTAssertEqual(json["supportsSuggestions"] as? Bool, true)
    }

    func testSupportsSuggestionsDefaultsToFalse() throws {
        // defaultValues does not pass supportsSuggestions, so it must encode as false.
        let json = try jsonObject(AIChatNativeConfigValues.defaultValues)
        XCTAssertEqual(json["supportsSuggestions"] as? Bool, false)
    }

    private func jsonObject(_ config: AIChatNativeConfigValues) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeConfig(supportsSuggestions: Bool) -> AIChatNativeConfigValues {
        AIChatNativeConfigValues(
            isAIChatHandoffEnabled: false,
            supportsClosingAIChat: true,
            supportsOpeningSettings: true,
            supportsNativePrompt: true,
            supportsStandaloneMigration: false,
            supportsNativeChatInput: false,
            supportsURLChatIDRestoration: false,
            supportsFullChatRestoration: false,
            supportsPageContext: true,
            supportsAIChatFullMode: false,
            supportsAIChatContextualMode: false,
            appVersion: "1.0.0",
            supportsAIChatSync: false,
            supportsSuggestions: supportsSuggestions
        )
    }

    private func encodedRawValue(_ type: AIChatInstallType) throws -> String {
        let data = try JSONEncoder().encode(type)
        return try XCTUnwrap(String(data: data, encoding: .utf8)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
