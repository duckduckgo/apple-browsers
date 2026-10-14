//
//  PasskeyUsagePixelReporterTests.swift
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

@_spi(Testing) import PixelKit
import PrivacyConfig
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PasskeyUsagePixelReporterTests: XCTestCase {

    private var pixelFiring: PixelKitMock!
    private var reporter: PasskeyUsagePixelReporter!

    override func setUp() {
        super.setUp()
        pixelFiring = PixelKitMock()
        reporter = PasskeyUsagePixelReporter(pixelFiring: pixelFiring)
    }

    override func tearDown() {
        reporter = nil
        pixelFiring = nil
        super.tearDown()
    }

    func testWhenPasskeyIsUsed_ThenUseSuccessIsFired() {
        reporter.report(.passkeyUsed, params: ["type": "get"])

        XCTAssertEqual(pixelFiring.actualFireCalls, [ExpectedFireCall(pixel: PasskeyUsagePixel.useSuccess, frequency: .dailyAndCount)])
    }

    func testWhenPasskeyIsCreated_ThenCreateSuccessIsFired() {
        reporter.report(.passkeyUsed, params: ["type": "create"])

        XCTAssertEqual(pixelFiring.actualFireCalls, [ExpectedFireCall(pixel: PasskeyUsagePixel.createSuccess, frequency: .dailyAndCount)])
    }

    func testWhenPasskeyUseFails_ThenUseFailureIsFiredWithError() {
        reporter.report(.passkeyFailed, params: ["type": "get", "error": "NotAllowedError"])

        XCTAssertEqual(pixelFiring.actualFireCalls, [ExpectedFireCall(pixel: PasskeyUsagePixel.useFailure(error: "NotAllowedError"), frequency: .dailyAndCount)])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters, ["error": "NotAllowedError"])
    }

    func testWhenPasskeyCreationFails_ThenCreateFailureIsFiredWithError() {
        reporter.report(.passkeyFailed, params: ["type": "create", "error": "InvalidStateError"])

        XCTAssertEqual(pixelFiring.actualFireCalls, [ExpectedFireCall(pixel: PasskeyUsagePixel.createFailure(error: "InvalidStateError"), frequency: .dailyAndCount)])
    }

    func testWhenErrorIsUnrecognized_ThenItIsReportedAsOther() {
        reporter.report(.passkeyFailed, params: ["type": "get", "error": "https://example.com/leak"])
        reporter.report(.passkeyFailed, params: ["type": "get"])

        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.parameters), [["error": "Other"], ["error": "Other"]])
    }

    func testWhenTypeIsMissingOrUnknown_ThenUnknownEventIsFired() {
        reporter.report(.passkeyUsed, params: ["type": "update"])
        reporter.report(.passkeyFailed, params: "not a dictionary")

        XCTAssertEqual(pixelFiring.actualFireCalls, [
            ExpectedFireCall(pixel: PasskeyUsagePixel.unknownEvent, frequency: .dailyAndCount),
            ExpectedFireCall(pixel: PasskeyUsagePixel.unknownEvent, frequency: .dailyAndCount)
        ])
    }

    func testThatOnlyPasskeyMessagesGetAHandler() {
        XCTAssertNotNil(reporter.handler(forMethodNamed: "passkeyUsed"))
        XCTAssertNotNil(reporter.handler(forMethodNamed: "passkeyFailed"))
        XCTAssertNil(reporter.handler(forMethodNamed: "showNotification"))
    }

    func testThatWebNotificationsHandlerRoutesPasskeyMessagesToTheReporter() async throws {
        let handler = WebNotificationsHandler(tabUUID: "tab",
                                              notificationService: MockWebNotificationService(),
                                              featureFlagger: MockFeatureFlagger(),
                                              passkeyUsagePixelReporter: reporter)

        let passkeyHandler = try XCTUnwrap(handler.handler(forMethodNamed: "passkeyUsed"))
        _ = try await passkeyHandler(["type": "get"], WKScriptMessage())

        XCTAssertEqual(pixelFiring.actualFireCalls, [ExpectedFireCall(pixel: PasskeyUsagePixel.useSuccess, frequency: .dailyAndCount)])
    }

    func testThatPasskeyUsageSubfeatureOwnsWebCompatMessages() async throws {
        let subfeature = PasskeyUsageSubfeature(reporter: reporter)

        XCTAssertEqual(subfeature.featureName, "webCompat")
        let passkeyHandler = try XCTUnwrap(subfeature.handler(forMethodNamed: "passkeyFailed"))
        _ = try await passkeyHandler(["type": "create", "error": "AbortError"], WKScriptMessage())

        XCTAssertEqual(pixelFiring.actualFireCalls, [ExpectedFireCall(pixel: PasskeyUsagePixel.createFailure(error: "AbortError"), frequency: .dailyAndCount)])
    }
}
