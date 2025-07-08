//
//  NewTabPageOmnibarClientTests.swift
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
@testable import NewTabPage

final class NewTabPageOmnibarClientTests: XCTestCase {

    private var model: NewTabPageOmnibarModel!
    private var client: NewTabPageOmnibarClient!
    private var userScript: NewTabPageUserScript!
    private var messageHelper: MessageHelper<NewTabPageOmnibarClient.MessageName>!

    override func setUp() async throws {
        try await super.setUp()

        model = NewTabPageOmnibarModel()
        client = NewTabPageOmnibarClient(model: model)

        userScript = NewTabPageUserScript()
        messageHelper = .init(userScript: userScript)

        client.registerMessageHandlers(for: userScript)
    }

    // MARK: - getConfig

    func testGetConfigReturnsSearchMode() async throws {
        let config: NewTabPageDataModel.OmnibarConfig = try await messageHelper.handleMessage(named: .getConfig)
        XCTAssertEqual(config.mode, .search)
    }
}
