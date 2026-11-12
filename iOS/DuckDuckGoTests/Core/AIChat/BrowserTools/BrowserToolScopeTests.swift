//
//  BrowserToolScopeTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo

@MainActor
final class BrowserToolScopeTests: XCTestCase {
    func testScopeRequiresActualOwnerObjectAndFreshMembership() {
        let owner = Tab(uid: "owner", fireTab: false)
        var tabs = [owner]
        let scope = BrowserToolScope(owner: owner,
                                     source: MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { tabs }),
                                     selectedTabID: { nil })
        XCTAssertTrue(scope.isValid)
        tabs = [Tab(uid: owner.uid, fireTab: false)]
        XCTAssertFalse(scope.isValid)
        tabs = [owner]
        XCTAssertTrue(scope.isValid)
        tabs = []
        XCTAssertFalse(scope.isValid)
    }

    func testScopeDoesNotRetainOwnerAndRevocationIsPermanent() {
        var owner: Tab? = Tab(fireTab: false)
        weak var weakOwner = owner
        let source = MultiTabAttachmentSource(currentTabID: owner!.uid, mode: .normal, tabsProvider: { owner.map { [$0] } ?? [] })
        let scope = BrowserToolScope(owner: owner!, source: source, selectedTabID: { nil })
        XCTAssertTrue(scope.isValid)
        owner = nil
        XCTAssertNil(weakOwner)
        XCTAssertFalse(scope.isValid)

        let retainedOwner = Tab(fireTab: false)
        let validSource = MultiTabAttachmentSource(currentTabID: retainedOwner.uid, mode: .normal, tabsProvider: { [retainedOwner] })
        let revoked = BrowserToolScope(owner: retainedOwner, source: validSource, selectedTabID: { nil })
        XCTAssertTrue(revoked.isValid)
        revoked.revoke()
        XCTAssertFalse(revoked.isValid)
    }

    func testFireOwnerOrSourceIsUnavailable() {
        for ownerIsFire in [false, true] {
            for sourceIsFire in [false, true] {
                let owner = Tab(fireTab: ownerIsFire)
                let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: sourceIsFire ? .fire : .normal,
                                                      tabsProvider: { [owner] })
                let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { nil })
                XCTAssertEqual(scope.isValid, !ownerIsFire && !sourceIsFire)
            }
        }
    }

    func testContextRequiresOwnerTokenAndNormalMode() {
        let owner = Tab(fireTab: false)
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { nil })
        let otherScope = BrowserToolScope(owner: owner, source: source, selectedTabID: { nil })
        XCTAssertNotEqual(scope.token, otherScope.token)
        func context(ownerID: String, token: String?, burner: Bool) -> BrowserToolCallContext {
            BrowserToolCallContext(ownerTabID: ownerID, ownerWindowToken: token,
                                  isBurner: burner)
        }
        XCTAssertTrue(scope.accepts(context(ownerID: owner.uid, token: scope.token, burner: false)))
        let invalidContexts = [context(ownerID: "other", token: scope.token, burner: false),
                               context(ownerID: owner.uid, token: otherScope.token, burner: false),
                               context(ownerID: owner.uid, token: nil, burner: false),
                               context(ownerID: owner.uid, token: scope.token, burner: true)]
        for invalid in invalidContexts {
            XCTAssertFalse(scope.accepts(invalid))
        }
        scope.revoke()
        XCTAssertFalse(scope.accepts(BrowserToolCallContext(ownerTabID: owner.uid, ownerWindowToken: scope.token,
                                                           isBurner: false)))
    }

    func testContainsRequiresNormalObjectMembershipAndValidOwner() {
        let owner = Tab(uid: "owner", fireTab: false)
        let target = Tab(uid: "target", fireTab: false)
        let fire = Tab(uid: "fire", fireTab: true)
        var tabs = [owner, target, fire]
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { tabs })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid })
        XCTAssertTrue(scope.contains(target))
        XCTAssertFalse(scope.contains(Tab(uid: target.uid, fireTab: false)))
        XCTAssertFalse(scope.contains(fire))
        XCTAssertFalse(scope.selectTab(target))
        tabs = [owner]
        XCTAssertFalse(scope.contains(target))
        tabs = [Tab(uid: owner.uid, fireTab: false), target]
        XCTAssertFalse(scope.contains(target))
        tabs = [owner, target]
        scope.revoke()
        XCTAssertFalse(scope.contains(target))
    }

}
