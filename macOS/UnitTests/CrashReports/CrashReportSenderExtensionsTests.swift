//
//  CrashReportSenderExtensionsTests.swift
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

import Crashes
import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class CrashReportSenderExtensionsTests: XCTestCase {

    private var firedPixelNames: [String] = []

    override func setUpWithError() throws {
        firedPixelNames = []
        PixelKit.setUp(dryRun: false,
                       appVersion: "1.0.0",
                       session: "test",
                       defaultHeaders: [:],
                       defaults: UserDefaults(suiteName: "test_\(UUID().uuidString)")!) { [weak self] firedPixelName, _, _, _, _, onComplete in
            self?.firedPixelNames.append(firedPixelName)
            onComplete(true, nil)
        }
    }

    override func tearDownWithError() throws {
        firedPixelNames = []
        PixelKit.tearDown()
    }

    func testCrashReportSentPixelHasExpectedName() {
        XCTAssertEqual(GeneralPixel.crashReportSent.name, "m_mac_crash-report_sent")
    }

    func testWhenSubmissionSucceededIsFiredThenCountAndDailyPixelsAreSent() {
        CrashReportSender.pixelEvents.fire(.submissionSucceeded)

        // .dailyAndStandard fires the count variant under the bare name and the daily variant with a `_daily` suffix on first call of the day.
        XCTAssertTrue(firedPixelNames.contains("m_mac_crash-report_sent"))
        XCTAssertTrue(firedPixelNames.contains("m_mac_crash-report_sent_daily"))
    }

    func testWhenSubmissionFailedIsFiredThenSuccessPixelIsNotSent() {
        CrashReportSender.pixelEvents.fire(.failure(.submissionFailed(nil)))

        XCTAssertFalse(firedPixelNames.contains("m_mac_crash-report_sent"))
        XCTAssertFalse(firedPixelNames.contains("m_mac_crash-report_sent_daily"))
    }
}
