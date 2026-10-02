//
//  WebExtensionPopupPresenterTests.swift
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

import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class WebExtensionPopupPresenterTests: XCTestCase {

    func testThatSameTabInstanceIsTheSameTab() {
        let tab = Tab(content: .none)

        XCTAssertTrue(WebExtensionPopupPresenter.isSameTab(tab, as: tab))
    }

    func testThatAnotherTabInstanceIsNotTheSameTab() {
        XCTAssertFalse(WebExtensionPopupPresenter.isSameTab(Tab(content: .none), as: Tab(content: .none)))
    }

    func testThatNoTabIsNotTheSameAsATab() {
        XCTAssertFalse(WebExtensionPopupPresenter.isSameTab(nil, as: Tab(content: .none)))
        XCTAssertFalse(WebExtensionPopupPresenter.isSameTab(Tab(content: .none), as: nil))
    }
}
