//
//  TabSwitcherAnimatedButtonTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

class TabSwitcherAnimatedButtonTests: XCTestCase {

    func testInitialState() {
        
        let button = TabSwitcherAnimatedButton()
        XCTAssertEqual(0, button.anim.currentProgress)
        XCTAssertEqual(0, button.tabCount)
        XCTAssertFalse(button.hasUnread)
        XCTAssertNil(button.label.text)
        
    }

    func testStaticButtonInitialState() {

        let button = TabSwitcherStaticButton()
        XCTAssertEqual(0, button.tabCount)
        XCTAssertFalse(button.hasUnread)

    }

    func testWhenAnimateCalledThenCountIsNotIncremented() {
        let button = TabSwitcherAnimatedButton()
        button.animateUpdate { }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
        XCTAssertEqual(0, button.tabCount)
    }

    func testWhenUnreadIsSetThenAnimationIsSetToEnd() {
        
        let button = TabSwitcherAnimatedButton()
        button.hasUnread = true
        XCTAssertEqual(1.0, button.anim.currentProgress)
        
    }

    func testWhenCountSetBackToZeroThenTextIsBlank() {
        
        let button = TabSwitcherAnimatedButton()
        button.tabCount = 1
        XCTAssertNotNil(button.label.text)
        button.tabCount = 0
        XCTAssertNil(button.label.text)

    }

    func testWhenExceedsMaxThenLabelIsSetAppropriately() {
        
        let button = TabSwitcherAnimatedButton()
        button.tabCount = 100
        XCTAssertEqual("~", button.label.text)
        
    }

    func testWhenCountIsUpdatedThenLabelIsUpdated() {
        
        let button = TabSwitcherAnimatedButton()
        button.tabCount = 99
        XCTAssertEqual("99", button.label.text)
        
    }
    
}
