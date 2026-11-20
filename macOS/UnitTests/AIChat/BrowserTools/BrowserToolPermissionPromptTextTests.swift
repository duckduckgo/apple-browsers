//
//  BrowserToolPermissionPromptTextTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class BrowserToolPermissionPromptTextTests: XCTestCase {

    func testWhenReadingOrSearchingAnotherTabThenThePromptSaysAnotherTab() {
        XCTAssertEqual(BrowserToolPermissionPromptText.title(toolName: "readTabContent", targetsOtherTab: false),
                       "Allow Duck.ai to read the content of this tab?")
        XCTAssertEqual(BrowserToolPermissionPromptText.title(toolName: "readTabContent", targetsOtherTab: true),
                       "Allow Duck.ai to read the content of another tab?")
        XCTAssertEqual(BrowserToolPermissionPromptText.title(toolName: "findInPage", targetsOtherTab: true),
                       "Allow Duck.ai to use Find in Page on another tab?")
        XCTAssertEqual(BrowserToolPermissionPromptText.detail(toolName: "findInPage", targetsOtherTab: true),
                       "It will see that tab's title, address and short snippets around each match.")
    }

    func testWhenAToolHasNoOtherTabWordingThenItsOwnIsUsed() {
        XCTAssertEqual(BrowserToolPermissionPromptText.title(toolName: "listOpenTabs", targetsOtherTab: true),
                       "Allow Duck.ai to see your open tabs?")
    }

    func testWhenTheToolIsUnknownThenThePromptIsGeneric() {
        XCTAssertEqual(BrowserToolPermissionPromptText.title(toolName: "future", targetsOtherTab: false),
                       "Allow Duck.ai to use a browser tool?")
        XCTAssertNil(BrowserToolPermissionPromptText.detail(toolName: "future", targetsOtherTab: false))
    }
}
