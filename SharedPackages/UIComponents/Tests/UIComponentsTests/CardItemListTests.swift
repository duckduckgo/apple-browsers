//
//  CardItemListTests.swift
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

#if os(iOS)

import Testing
@testable import UIComponents

@MainActor
struct CardItemListSelectActionTests {

    @Test("An out-of-bounds index returns no action")
    func selectActionWithOutOfBoundsIndexReturnsNil() {
        let handler = CardItemList.selectAction(over: ["a"]) { _ in }

        #expect(handler(5) == nil)
        #expect(handler(-1) == nil)
    }

    @Test("An empty collection returns no action for any index")
    func selectActionWithEmptyCollectionReturnsNilForAnyIndex() {
        let handler = CardItemList.selectAction(over: [String]()) { _ in }

        #expect(handler(0) == nil)
    }

    @Test("A valid selectable row returns an action that fires with its element")
    func selectActionWithValidSelectableRowReturnsActionThatFiresWithElement() {
        var captured: String?
        let handler = CardItemList.selectAction(over: ["a", "b", "c"]) { captured = $0 }

        let action = handler(1)

        #expect(action != nil)
        action?()
        #expect(captured == "b")
    }

    @Test("A selectability predicate gates which rows return an action")
    func selectActionWithSelectabilityPredicateGatesRows() {
        let handler = CardItemList.selectAction(over: [1, 2, 3], where: { $0.isMultiple(of: 2) }) { _ in }

        #expect(handler(0) == nil)    // element 1 — not selectable
        #expect(handler(1) != nil)    // element 2 — selectable
    }

    @Test("The action does not fire until it is invoked")
    func selectActionDoesNotFireActionUntilInvoked() {
        var fired = false
        let handler = CardItemList.selectAction(over: ["x"]) { _ in fired = true }

        _ = handler(0)
        #expect(!fired)

        handler(0)?()
        #expect(fired)
    }
}

#endif
