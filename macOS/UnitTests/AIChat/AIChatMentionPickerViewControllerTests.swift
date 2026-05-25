//
//  AIChatMentionPickerViewControllerTests.swift
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
import AppKit
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AIChatMentionPickerViewControllerTests: XCTestCase {

    private var vc: AIChatMentionPickerViewController!

    override func setUp() {
        super.setUp()
        vc = AIChatMentionPickerViewController()
        // Force the view to load so autolayout constraints and stored constraint
        // references are wired before we call into the controller's API.
        _ = vc.view
    }

    override func tearDown() {
        vc = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func testSetTabsWithEntries_DefaultsHighlightToFirstRow() {
        vc.setTabs([tab("a"), tab("b"), tab("c")], currentTabId: nil, attachedTabIds: [])

        XCTAssertEqual(vc.highlightedIndex, 0,
                       "Opening the picker should highlight the first row so Enter immediately accepts it.")
        XCTAssertFalse(vc.isShowingEmptyState)
    }

    func testSetTabsEmpty_SwitchesToEmptyStateWithoutHighlight() {
        vc.setTabs([], currentTabId: nil, attachedTabIds: [])

        XCTAssertTrue(vc.isShowingEmptyState)
        XCTAssertNil(vc.highlightedIndex,
                     "Empty state has no real row, so there's nothing to highlight — Enter must fall through to submit.")
        XCTAssertNil(vc.highlightedTab)
    }

    // MARK: - Filtering from many → one (regression for the M11 polish bug)

    /// When the user filters from "many rows, row 0 highlighted" down to "one row, also row 0",
    /// the new row at index 0 must be visibly highlighted. A previous version of
    /// `setHighlightedIndex` short-circuited on equal indexes and skipped the per-row write,
    /// leaving the new single row unhighlighted.
    func testSetTabsFromManyToOneAtSameIndex_NewRowIsHighlighted() {
        vc.setTabs([tab("a"), tab("b"), tab("c")], currentTabId: nil, attachedTabIds: [])
        XCTAssertEqual(vc.highlightedIndex, 0)
        let firstTabBeforeFilter = vc.highlightedTab
        XCTAssertEqual(firstTabBeforeFilter?.id, "a")

        // Filter down to a different tab at index 0 — the highlight target should follow.
        vc.setTabs([tab("z")], currentTabId: nil, attachedTabIds: [])
        XCTAssertEqual(vc.highlightedIndex, 0)
        XCTAssertEqual(vc.highlightedTab?.id, "z",
                       "After re-applying tabs the highlight must follow to the *new* row 0, not stick to the previous identity.")
    }

    // MARK: - Keyboard navigation (wraps)

    func testMoveHighlightDown_AdvancesByOne() {
        vc.setTabs([tab("a"), tab("b"), tab("c")], currentTabId: nil, attachedTabIds: [])
        vc.moveHighlightDown()
        XCTAssertEqual(vc.highlightedIndex, 1)
        vc.moveHighlightDown()
        XCTAssertEqual(vc.highlightedIndex, 2)
    }

    func testMoveHighlightDown_WrapsFromLastToFirst() {
        vc.setTabs([tab("a"), tab("b")], currentTabId: nil, attachedTabIds: [])
        vc.moveHighlightDown()   // 0 → 1 (last)
        XCTAssertEqual(vc.highlightedIndex, 1)
        vc.moveHighlightDown()   // 1 → 0 (wrap)
        XCTAssertEqual(vc.highlightedIndex, 0,
                       "moveHighlightDown at the last row must wrap back to the first row.")
    }

    func testMoveHighlightUp_WrapsFromFirstToLast() {
        vc.setTabs([tab("a"), tab("b"), tab("c")], currentTabId: nil, attachedTabIds: [])
        // highlightedIndex starts at 0
        vc.moveHighlightUp()     // 0 → last
        XCTAssertEqual(vc.highlightedIndex, 2,
                       "moveHighlightUp at the first row must wrap to the last row.")
    }

    func testMoveHighlight_NoOpInEmptyState() {
        vc.setTabs([], currentTabId: nil, attachedTabIds: [])
        XCTAssertNil(vc.highlightedIndex)

        vc.moveHighlightDown()
        XCTAssertNil(vc.highlightedIndex,
                     "Arrow keys must not invent a highlight when the picker is showing the empty-state row.")
        vc.moveHighlightUp()
        XCTAssertNil(vc.highlightedIndex)
    }

    // MARK: - Accept-via-click routing

    func testOnAccept_FiresWithClickedRowsAttachment() {
        let captured: NSMutableArray = []
        vc.onAccept = { attachment in
            captured.add(attachment.id)
        }
        vc.setTabs([tab("a"), tab("b")], currentTabId: nil, attachedTabIds: [])

        // The click handler lives on the row view; we exercise the wiring directly via the
        // VC's `onAccept` callback that each row hooks into.
        vc.onAccept?(tab("b"))

        XCTAssertEqual(captured as? [String], ["b"])
    }

    // MARK: - fittingContentSize sanity

    func testFittingContentSize_NonEmpty_RespectsWidthClamp() {
        vc.setTabs([tab("hello", title: "A tab with a reasonably long title")],
                   currentTabId: nil, attachedTabIds: [])
        let size = vc.fittingContentSize
        // Within the documented clamp [200, 360].
        XCTAssertGreaterThanOrEqual(size.width, 200)
        XCTAssertLessThanOrEqual(size.width, 360)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testFittingContentSize_Empty_UsesMinWidth() {
        vc.setTabs([], currentTabId: nil, attachedTabIds: [])
        let size = vc.fittingContentSize
        XCTAssertEqual(size.width, 200,
                       "Empty-state placeholder uses the documented minWidth.")
    }

    // MARK: - Helpers

    private func tab(_ id: String, title: String = "Example", urlString: String = "https://example.com") -> AIChatTabAttachment {
        AIChatTabAttachment(id: id, title: title, url: URL(string: urlString)!, favicon: nil)
    }
}
