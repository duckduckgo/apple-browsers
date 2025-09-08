//
//  InternalUserCommandsTests.swift
//  DuckDuckGo
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
import BrowserServicesKit
@testable import Core
@testable import DuckDuckGo

// MARK: - Mocks

private class MockPresenter: ActionMessagePresenting {
    static var onPresent: (String) -> Void  = { _ in }
    static func present(message: String,
                        actionTitle: String?,
                        presentationLocation: ActionMessageView.PresentationLocation,
                        duration: TimeInterval,
                        onAction: @escaping () -> Void,
                        onDidDismiss: @escaping () -> Void) {
        onPresent(message)
    }

    static func reset() {
        onPresent = { _ in }
    }
}

class MockAppConfigurationFetching: AppConfigurationFetching {

    func start(isBackgroundFetch: Bool,
               isDebug: Bool,
               forceRefresh: Bool,
               completion: AppConfigurationFetchCompletion?) {
        completion?(.noData)
    }
}

// MARK: - Tests

class InternalUserCommandsTests: XCTestCase {
    var decider: MockInternalUserDecider!
    private var presenter: MockPresenter.Type!
    var configFetch: MockAppConfigurationFetching!
    var commands: InternalUserCommands!

    override func setUp() {
        super.setUp()
        decider = MockInternalUserDecider()
        presenter = MockPresenter.self
        configFetch = MockAppConfigurationFetching()
        MockPresenter.reset()
        commands = InternalUserCommands(internalUserDecider: decider, presenter: presenter, configFetching: configFetch)
    }

    override func tearDown() {
        MockPresenter.reset()
        super.tearDown()
    }

    func testHandleUrl_withInternalUserAndValidCommand_triggersConfigReload() {
        decider.isInternalUser = true
        let url = URL(string: "ddg-internal://reloadConfig")!

        let exp = expectation(description: "Alert presented")
        MockPresenter.onPresent = { msg in
            XCTAssertEqual(msg, "No new data")
            exp.fulfill()
        }

        let result = commands.handle(url: url)
        XCTAssertTrue(result)
        waitForExpectations(timeout: 2)
    }

    func testHandleUrl_withInternalUserAndInvalidCommand_presentsUnknownCommand() {
        decider.isInternalUser = true
        let url = URL(string: "ddg-internal://invalidCommand")!

        let exp = expectation(description: "Alert presented")
        MockPresenter.onPresent = { msg in
            XCTAssertEqual(msg, "Unknown command")
            exp.fulfill()
        }

        XCTAssertTrue(commands.handle(url: url))
        waitForExpectations(timeout: 2)
    }

    func testHandleUrl_withNonInternalUser_returnsFalse() {
        decider.isInternalUser = false
        let url = URL(string: "ddg-internal://reloadConfig")!

        MockPresenter.onPresent = { _ in
            XCTFail("No alert is expected")
        }

        XCTAssertFalse(commands.handle(url: url))
    }

    func testHandleUrl_withHttpScheme_returnsFalse() {
        decider.isInternalUser = true

        MockPresenter.onPresent = { _ in
            XCTFail("No alert is expected")
        }

        XCTAssertFalse(commands.handle(url: URL(string: "http://reloadConfig")!))
        XCTAssertFalse(commands.handle(url: URL(string: "https://reloadConfig")!))
        XCTAssertFalse(commands.handle(url: URL(string: "192.168.0.1")!))

    }
}
