//
//  MultiTabAttachmentTests.swift
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

import Core
import XCTest
@testable import DuckDuckGo

@MainActor
final class MultiTabAttachmentTests: XCTestCase {

    func test_policyCurrentPageAndTwoOthersReachLimit() {
        let policy = policy(attachments: [attachment(id: "one"), attachment(id: "two")], currentPageAttached: true)

        XCTAssertEqual(policy.selectedTabIDs.count, 3)
        XCTAssertFalse(policy.canAttachTab(withID: "three"))
    }

    func test_sourceScopesBothModesAndPreservesSameAddressTabs() {
        let tabs = [tab(id: "normal-one"), tab(id: "fire-one", fire: true), tab(id: "normal-two"), tab(id: "fire-two", fire: true)]
        let normal = MultiTabAttachmentSource(currentTabID: "normal-two", mode: .normal, tabsProvider: { tabs })
        let fire = MultiTabAttachmentSource(currentTabID: "fire-two", mode: .fire, tabsProvider: { tabs })

        XCTAssertEqual(normal.candidates().map(\.tabId), ["normal-two", "normal-one"])
        XCTAssertEqual(fire.candidates().map(\.tabId), ["fire-two", "fire-one"])
    }

    private func attachment(id: TabUID) -> UnifiedToggleInputTabAttachment {
        UnifiedToggleInputTabAttachment(tabId: id, title: "Page", url: URL(string: "https://example.com/page")!)
    }

    private func tab(id: TabUID, fire: Bool = false, lastViewed: Date? = nil) -> Tab {
        Tab(uid: id, link: Link(title: id, url: URL(string: "https://example.com/page")!), lastViewedDate: lastViewed, fireTab: fire)
    }

    private func policy(attachments: [UnifiedToggleInputTabAttachment], currentPageAttached: Bool = false, limit: Int = 3) -> UTIAttachmentPolicy {
        UTIAttachmentPolicy(attachmentLimits: nil, attachmentUsage: nil, pendingAttachments: attachments.map { .tab($0) }, model: nil,
                            maximumTabAttachmentCount: limit, currentPageTabID: "current", isCurrentPageAttached: currentPageAttached)
    }
}
