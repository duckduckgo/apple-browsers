//
//  NewTabKeyboardDepartureTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class NewTabKeyboardDepartureTests: XCTestCase {

    func testWhenNoKeyboardIsUpThenTheTabOpensNow() {
        XCTAssertEqual(NewTabKeyboardDeparture.plan(keyboardShowing: false, isHiding: false, hasFocusedField: false), .openNow)
    }

    func testWhenAFocusedFieldHoldsTheKeyboardThenItIsResignedAndWaitedFor() {
        XCTAssertEqual(NewTabKeyboardDeparture.plan(keyboardShowing: true, isHiding: false, hasFocusedField: true), .resignThenWaitForHide)
    }

    func testWhenTheKeyboardIsAlreadyHidingThenTheTabWaitsForIt() {
        XCTAssertEqual(NewTabKeyboardDeparture.plan(keyboardShowing: true, isHiding: true, hasFocusedField: false), .waitForHide)
    }

    func testWhenTheKeyboardFlagIsStaleWithNothingFocusedThenTheTabOpensNow() {
        XCTAssertEqual(NewTabKeyboardDeparture.plan(keyboardShowing: true, isHiding: false, hasFocusedField: false), .openNow)
    }
}
