//
//  TabSwitcherStaticButtonTests.swift
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
@testable import DuckDuckGo

class TabSwitcherStaticButtonTests: XCTestCase {

    func testInitialState() {
        let button = TabSwitcherStaticButton()
        XCTAssertEqual(0, button.tabCount)
        XCTAssertFalse(button.hasUnread)
        XCTAssertNil(button.text)
    }

    func testWhenAnimateCalledThenCountIsNotIncremented() {
        let button = TabSwitcherStaticButton()
        button.animateUpdate { }
        XCTAssertEqual(0, button.tabCount)
        XCTAssertNil(button.text)
    }

    func testWhenCountSetBackToZeroThenTextIsBlank() {
        let button = TabSwitcherStaticButton()
        button.tabCount = 1
        XCTAssertNotNil(button.text)
        button.tabCount = 0
        XCTAssertNil(button.text)
    }

    func testWhenExceedsMaxThenLabelIsSetAppropriately() {
        let button = TabSwitcherStaticButton()
        button.tabCount = 100
        XCTAssertEqual("∞", button.text)
    }


    func testWhenCountIsUpdatedThenLabelIsUpdated() {
        let button = TabSwitcherStaticButton()
        button.tabCount = 99
        XCTAssertEqual("99", button.text)
    }
    
}
