//
//  AIChatTabSelectionDiffTests.swift
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

final class AIChatTabSelectionDiffTests: XCTestCase {

    private func makeTab(_ id: String) -> AIChatTabAttachment {
        AIChatTabAttachment(id: id, title: "Tab \(id)", url: URL(string: "https://example.com/\(id)")!, favicon: nil)
    }

    func testUncheckedOfferedTabIsRemoved() {
        let offered = [makeTab("1"), makeTab("2")]
        let diff = AIChatTabSelectionDiff.compute(current: [makeTab("1"), makeTab("2")],
                                                 selected: [makeTab("1")],
                                                 offered: offered)
        XCTAssertEqual(diff.remove, ["2"])
        XCTAssertTrue(diff.add.isEmpty)
    }

    func testNewlyCheckedTabIsAdded() {
        let offered = [makeTab("1"), makeTab("2")]
        let diff = AIChatTabSelectionDiff.compute(current: [makeTab("1")],
                                                 selected: [makeTab("1"), makeTab("2")],
                                                 offered: offered)
        XCTAssertTrue(diff.remove.isEmpty)
        XCTAssertEqual(diff.add.map(\.id), ["2"])
    }

    func testAttachmentMissingFromOfferedListIsKept() {
        let diff = AIChatTabSelectionDiff.compute(current: [makeTab("1"), makeTab("stale")],
                                                 selected: [makeTab("1")],
                                                 offered: [makeTab("1"), makeTab("2")])
        XCTAssertTrue(diff.remove.isEmpty)
        XCTAssertTrue(diff.add.isEmpty)
    }

    func testAlreadyAttachedTabIsNotReAdded() {
        let offered = [makeTab("1")]
        let diff = AIChatTabSelectionDiff.compute(current: [makeTab("1")],
                                                 selected: [makeTab("1")],
                                                 offered: offered)
        XCTAssertTrue(diff.remove.isEmpty)
        XCTAssertTrue(diff.add.isEmpty)
    }

    func testEmptySelectionRemovesEveryOfferedAttachment() {
        let offered = [makeTab("1"), makeTab("2")]
        let diff = AIChatTabSelectionDiff.compute(current: [makeTab("1"), makeTab("2"), makeTab("stale")],
                                                 selected: [],
                                                 offered: offered)
        XCTAssertEqual(diff.remove, ["1", "2"])
        XCTAssertTrue(diff.add.isEmpty)
    }
}
