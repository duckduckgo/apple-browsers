//
//  WebViewAIChatJSDataCleanerTests.swift
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

import PrivacyConfig
import PrivacyConfigTestsUtils
import WebKit
import XCTest
@testable import AIChat

@MainActor
final class WebViewAIChatJSDataCleanerTests: XCTestCase {

    /// A timeout of zero is scheduled on the next main queue turn, which always precedes any
    /// navigation callback for a load started in the same turn. That stands in for the real
    /// failure: a web content process killed mid-load, where WebKit reports neither a failure
    /// nor a termination for the page.
    private func makeSUT() -> WebViewAIChatJSDataCleaner {
        WebViewAIChatJSDataCleaner(featureFlagger: MockFeatureFlagger(),
                                   privacyConfig: MockPrivacyConfigurationManager(),
                                   websiteDataStore: .nonPersistent(),
                                   navigationTimeout: 0)
    }

    /// Without the timeout the continuation is never resumed, so the enclosing burn never returns,
    /// `FireExecutor.burnInProgress` is never reset by its `defer`, and every later Fire press is
    /// dropped at the re-entrancy guard until the app is relaunched. If this regresses the test
    /// hangs rather than fails.
    func testWhenNavigationNeverCompletesThenClearFailsInsteadOfHanging() async {
        let result = await makeSUT().clearJSData(chatID: "test-chat-id")

        guard case .failure(let error) = result else {
            return XCTFail("Expected the clear to fail rather than hang")
        }
        guard let cleanerError = error as? WebViewAIChatJSDataCleaner.CleanerError,
              case .navigationTimedOut = cleanerError else {
            return XCTFail("Expected navigationTimedOut, got \(error)")
        }
    }

}
