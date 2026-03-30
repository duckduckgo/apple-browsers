//
//  WebViewHandlerTests.swift
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
@testable import DataBrokerProtectionCore
import BrowserServicesKit
import DataBrokerProtectionCoreTestsUtils
import WebKit

final class WebViewHandlerTests: XCTestCase {

    @MainActor
    func testWhenWaitingForWebViewLoadAndTaskIsCancelled_thenThrowsCancelled() async throws {
        // Given
        let sut = try makeWebViewHandler()
        let loadTask = Task { @MainActor in
            try await sut.waitForWebViewLoad()
        }

        // When
        try await Task.sleep(interval: 0.01)
        loadTask.cancel()

        let result = await loadTask.result

        // Then
        switch result {
        case .success:
            XCTFail("Expected cancellation error")
        case .failure(let error):
            XCTAssertEqual(error as? DataBrokerProtectionError, .cancelled)
        }
    }

    @MainActor
    func testWhenWebContentProcessTerminatesWhileWaitingForWebViewLoad_thenThrowsExplicitError() async throws {
        // Given
        let sut = try makeWebViewHandler()
        let loadTask = Task { @MainActor in
            try await sut.waitForWebViewLoad()
        }

        // When
        try await Task.sleep(interval: 0.01)
        sut.webViewWebContentProcessDidTerminate(WKWebView())

        let result = await loadTask.result

        // Then
        switch result {
        case .success:
            XCTFail("Expected web content termination error")
        case .failure(let error):
            XCTAssertEqual(error as? DataBrokerProtectionError, .webContentProcessTerminated)
        }
    }

    @MainActor
    private func makeWebViewHandler() throws -> DataBrokerProtectionWebViewHandler {
        try DataBrokerProtectionWebViewHandler(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: .mock,
            delegate: MockWebViewCommunicationDelegate(),
            executionConfig: BrokerJobExecutionConfig(),
            shouldContinueActionHandler: { true },
            applicationNameForUserAgent: nil
        )
    }
}

private final class MockWebViewCommunicationDelegate: CCFCommunicationDelegate {

    func loadURL(url: URL) {
    }

    func extractedProfiles(profiles: [ExtractedProfile], meta: [String: Any]?) async {
    }

    func captchaInformation(captchaInfo: GetCaptchaInfoResponse) {
    }

    func solveCaptcha(with response: SolveCaptchaResponse) async {
    }

    func success(actionId: String, actionType: ActionType) {
    }

    func conditionSuccess(actions: [Action]) async {
    }

    func onError(error: Error) {
    }
}
