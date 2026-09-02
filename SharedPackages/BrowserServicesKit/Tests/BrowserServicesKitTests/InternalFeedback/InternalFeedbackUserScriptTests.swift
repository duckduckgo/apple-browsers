//
//  InternalFeedbackUserScriptTests.swift
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

import BrowserServicesKitTestsUtils
import WebKit
import XCTest
@testable import BrowserServicesKit

@MainActor
final class InternalFeedbackUserScriptTests: XCTestCase {

    func testConfigurationAllowsOnlyConfiguredHostname() {
        let script = InternalFeedbackUserScript(deviceInfoProvider: MockDeviceInfoProvider())

        XCTAssertEqual(script.featureName, "internalFeedback")
        XCTAssertTrue(script.messageOriginPolicy.isAllowed("internalapps.duckduckgo.com"))
        XCTAssertFalse(script.messageOriginPolicy.isAllowed("subdomain.internalapps.duckduckgo.com"))
        XCTAssertFalse(script.messageOriginPolicy.isAllowed("example.com"))
    }

    func testHandlerIsAvailableOnlyForGetDeviceInfo() {
        let script = InternalFeedbackUserScript(deviceInfoProvider: MockDeviceInfoProvider())

        XCTAssertNotNil(script.handler(forMethodNamed: "getDeviceInfo"))
        XCTAssertNil(script.handler(forMethodNamed: "unknownMethod"))
    }

    func testGetDeviceInfoReturnsProviderValue() async throws {
        let provider = MockDeviceInfoProvider()
        let script = InternalFeedbackUserScript(deviceInfoProvider: provider)
        let handler = try XCTUnwrap(script.handler(forMethodNamed: "getDeviceInfo"))

        let result = try await handler([:], WKScriptMessage.mock()) as? InternalFeedbackDeviceInfo

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(result?.platform, "macos")
        XCTAssertEqual(result?.appVersion, "1.2.3")
        XCTAssertEqual(result?.diagnostics, ["Tabs": "4"])
    }
}

private final class MockDeviceInfoProvider: InternalFeedbackDeviceInfoProviding {

    private(set) var callCount = 0

    func deviceInfo() -> InternalFeedbackDeviceInfo {
        callCount += 1
        return InternalFeedbackDeviceInfo(
            platform: "macos",
            appVersion: "1.2.3",
            osName: "macOS",
            osVersion: "15.0",
            diagnostics: ["Tabs": "4"]
        )
    }
}
