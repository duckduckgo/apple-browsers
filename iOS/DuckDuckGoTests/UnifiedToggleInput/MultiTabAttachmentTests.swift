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

import AIChat
import Core
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class MultiTabAttachmentTests: XCTestCase {

    func test_tabModelKeepsAttachmentIdentitySeparateFromTabIdentity() {
        let first = attachment(id: "one")
        let reattached = attachment(id: "one")
        let other = attachment(id: "two")

        XCTAssertNotEqual(first.id, reattached.id)
        XCTAssertEqual(first.tabId, reattached.tabId)
        XCTAssertNotEqual(first.tabId, other.tabId)
        XCTAssertEqual(first.url, other.url)
    }

    func test_tabMetadataDoesNotBecomeAnImageOrFilePayload() {
        let tab = UnifiedToggleInputAttachment.tab(attachment(id: "one"))

        XCTAssertEqual(tab.fileName, "Page")
        XCTAssertEqual(tab.fileSizeBytes, 0)
        XCTAssertNil(tab.mimeType)
        XCTAssertFalse(tab.isImage)
        XCTAssertFalse(tab.isFile)
        XCTAssertNil(UnifiedToggleInputImageEncoder.encode([tab]))
        XCTAssertNil(UnifiedToggleInputFileEncoder.encode([tab]))
    }

    func test_policyCountsDistinctSourceTabsIncludingPendingCurrentPage() {
        let policy = policy(attachments: [attachment(id: "current"), attachment(id: "other"), attachment(id: "other")],
                            currentPageAttached: true)

        XCTAssertEqual(policy.selectedTabIDs, ["current", "other"])
        XCTAssertFalse(policy.canAttachTab(withID: "other"))
        XCTAssertTrue(policy.canAttachTab(withID: "third"))
    }

    func test_policyCurrentPageAndTwoOthersReachLimit() {
        let policy = policy(attachments: [attachment(id: "one"), attachment(id: "two")], currentPageAttached: true)

        XCTAssertEqual(policy.selectedTabIDs.count, 3)
        XCTAssertFalse(policy.canAttachTab(withID: "three"))
    }

    func test_policyDeliveredCurrentPageDoesNotReserveSlot() {
        let policy = policy(attachments: [attachment(id: "one"), attachment(id: "two")])

        XCTAssertEqual(policy.selectedTabIDs.count, 2)
        XCTAssertTrue(policy.canAttachTab(withID: "current"))
    }

    func test_policyUsesConfiguredLimitAndDisablesAddingWhenUnavailable() {
        var policy = policy(attachments: [attachment(id: "one")], limit: 1)
        XCTAssertFalse(policy.canAttachTab(withID: "two"))
        policy.maximumTabAttachmentCount = 2
        XCTAssertTrue(policy.canAttachTab(withID: "two"))
        policy.maximumTabAttachmentCount = nil
        XCTAssertFalse(policy.canAttachTab(withID: "two"))
    }

    func test_policyTabContextDoesNotRequireUploadCapability() {
        let policy = policy(attachments: [], limit: 3)
        XCTAssertTrue(policy.isAttachmentSupported(.tab(attachment(id: "one"))))
    }

    func test_sourceScopesBothModesAndPreservesSameAddressTabs() {
        let tabs = [tab(id: "normal-one"), tab(id: "fire-one", fire: true), tab(id: "normal-two"), tab(id: "fire-two", fire: true)]
        let normal = MultiTabAttachmentSource(currentTabID: "normal-two", mode: .normal, tabsProvider: { tabs })
        let fire = MultiTabAttachmentSource(currentTabID: "fire-two", mode: .fire, tabsProvider: { tabs })

        XCTAssertEqual(normal.candidates().map(\.tabId), ["normal-two", "normal-one"])
        XCTAssertEqual(fire.candidates().map(\.tabId), ["fire-two", "fire-one"])
    }

    func test_sourceFiltersIneligiblePagesAndDeduplicatesIdentity() {
        let page = tab(id: "page")
        let empty = Tab(uid: "empty", fireTab: false)
        let chat = Tab(uid: "chat", link: Link(title: "Duck.ai", url: URL(string: "https://duck.ai/")!), fireTab: false)
        let source = MultiTabAttachmentSource(currentTabID: "empty", mode: .normal, tabsProvider: { [empty, page, page, chat] })

        XCTAssertEqual(source.candidates().map(\.tabId), ["page"])
    }

    func test_sourcePinsCurrentTabThenSortsByRecencyWithStableTies() {
        let current = tab(id: "current", lastViewed: Date(timeIntervalSince1970: 1))
        let recent = tab(id: "recent", lastViewed: Date(timeIntervalSince1970: 20))
        let tied = tab(id: "tied", lastViewed: Date(timeIntervalSince1970: 20))
        let unknown = tab(id: "unknown")
        let source = MultiTabAttachmentSource(currentTabID: "current", mode: .normal, tabsProvider: { [unknown, recent, tied, current] })

        XCTAssertEqual(source.candidates().map(\.tabId), ["current", "recent", "tied", "unknown"])
    }

    func test_sourceRereadsModelsWhenTabsAreClosed() {
        var tabs = [tab(id: "one"), tab(id: "two")]
        let source = MultiTabAttachmentSource(currentTabID: "one", mode: .normal, tabsProvider: { tabs })
        XCTAssertEqual(source.candidates().count, 2)
        tabs.removeFirst()
        XCTAssertEqual(source.candidates().map(\.tabId), ["two"])
    }

    func test_pickerStagesSelectionAndAllowsReplacementAtCapacity() throws {
        let source = MultiTabAttachmentSource(currentTabID: "current", mode: .normal,
                                              tabsProvider: { [self.tab(id: "current"), self.tab(id: "other")] })
        let initial: Set<TabUID> = ["current"]
        let picker = MultiTabAttachmentPickerViewModel(candidates: source.candidates(), selectedTabIds: initial, attachmentLimit: 1)
        let current = try XCTUnwrap(picker.items.first { $0.id == "current" })
        let other = try XCTUnwrap(picker.items.first { $0.id == "other" })

        XCTAssertTrue(picker.isEnabled(current))
        XCTAssertFalse(picker.isEnabled(other))
        picker.toggleSelection(for: other)
        XCTAssertEqual(picker.selectedTabIds, initial)
        picker.toggleSelection(for: current)
        XCTAssertTrue(picker.isEnabled(other))
        picker.toggleSelection(for: other)
        XCTAssertEqual(picker.selectedTabIds, ["other"])
    }

    func test_pickerSearchRetainsSelectionOutsideResults() {
        let candidate = MultiTabAttachmentCandidate(tabId: "one", title: "Selected page", url: URL(string: "https://example.com")!)
        let picker = MultiTabAttachmentPickerViewModel(candidates: [candidate], selectedTabIds: ["one"], attachmentLimit: 3)
        picker.query = "no matching page"

        XCTAssertTrue(picker.filteredItems.isEmpty)
        XCTAssertEqual(picker.selectedTabIds, ["one"])
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
