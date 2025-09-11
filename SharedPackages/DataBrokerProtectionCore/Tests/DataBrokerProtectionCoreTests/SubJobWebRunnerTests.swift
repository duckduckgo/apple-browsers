//
//  SubJobWebRunnerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Foundation
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class DataBrokerJobTests: XCTestCase {

    func testWhenScanJobEncounters404_thenNextActionIsExecuted() async throws {
        // Given
        let sut = scanJob
        let mockActionsHandler = MockActionsHandler()
        sut.actionsHandler = mockActionsHandler
        let mockWebHandler = WebViewHandlerMock()
        mockWebHandler.errorStatusCodeToThrow = 404
        try await sut.initialize(handler: mockWebHandler, showWebView: false)

        // When
        await sut.loadURL(url: URL(string: "www.duckduckgo.com")!)

        // Then
        XCTAssertTrue(mockActionsHandler.didCallNextAction)
    }

    func testWhenScanJobEncounters403_thenNextActionIsNotExecuted() async throws {
        // Given
        let sut = scanJob
        let mockActionsHandler = MockActionsHandler()
        sut.actionsHandler = mockActionsHandler
        let mockWebHandler = WebViewHandlerMock()
        mockWebHandler.errorStatusCodeToThrow = 403
        try await sut.initialize(handler: mockWebHandler, showWebView: false)

        // When
        await sut.loadURL(url: URL(string: "www.duckduckgo.com")!)

        // Then
        XCTAssertFalse(mockActionsHandler.didCallNextAction)
    }

    func testWhenOptOutEncounters404_thenNextActionIsNotExecuted() async throws {
        // Given
        let sut = optOutJob
        let mockActionsHandler = MockActionsHandler()
        sut.actionsHandler = mockActionsHandler
        let mockWebHandler = WebViewHandlerMock()
        mockWebHandler.errorStatusCodeToThrow = 404
        try await sut.initialize(handler: mockWebHandler, showWebView: false)

        // When
        await sut.loadURL(url: URL(string: "www.duckduckgo.com")!)

        // Then
        XCTAssertFalse(mockActionsHandler.didCallNextAction)
    }
}

private extension DataBrokerJobTests {

    var scanJob: BrokerProfileScanSubJobWebRunner {
        BrokerProfileScanSubJobWebRunner(privacyConfig: PrivacyConfigurationManagingMock(),
                                         prefs: .mock,
                                         context: BrokerProfileQueryData.mock(with: [Step(type: .scan, actions: [])]),
                                         emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
                                         captchaService: CaptchaServiceMock(),
                                         featureFlagger: MockDBPFeatureFlagger(),
                                         stageDurationCalculator: MockStageDurationCalculator(),
                                         pixelHandler: MockPixelHandler(),
                                         executionConfig: BrokerJobExecutionConfig(),
                                         shouldRunNextStep: { true })
    }

    var optOutJob: BrokerProfileOptOutSubJobWebRunner {
        BrokerProfileOptOutSubJobWebRunner(privacyConfig: PrivacyConfigurationManagingMock(),
                                           prefs: .mock,
                                           context: BrokerProfileQueryData.mock(with: [Step(type: .optOut, actions: [])]),
                                           emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
                                           captchaService: CaptchaServiceMock(),
                                           featureFlagger: MockDBPFeatureFlagger(),
                                           stageCalculator: MockStageDurationCalculator(),
                                           pixelHandler: MockPixelHandler(),
                                           executionConfig: BrokerJobExecutionConfig(),
                                           actionsHandlerMode: .optOut,
                                           shouldRunNextStep: { true })
    }

}
