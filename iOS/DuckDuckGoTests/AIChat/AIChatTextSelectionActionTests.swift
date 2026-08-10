//
//  AIChatTextSelectionActionTests.swift
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

final class AIChatTextSelectionActionTests: XCTestCase {

    func testOnlyAskWaitsForTheUsersOwnQuestion() {
        XCTAssertFalse(AIChatTextSelectionAction.ask.autoSubmits)
        XCTAssertTrue(AIChatTextSelectionAction.summarize.autoSubmits)
        XCTAssertTrue(AIChatTextSelectionAction.translate.autoSubmits)
    }

    /// The submitting actions carry the text with them, so attaching it too would send it twice.
    func testOnlyAskAttachesTheSelection() {
        XCTAssertTrue(AIChatTextSelectionAction.ask.attachesSelection)
        XCTAssertFalse(AIChatTextSelectionAction.summarize.attachesSelection)
        XCTAssertFalse(AIChatTextSelectionAction.translate.attachesSelection)
    }

    func testAskHasNoSuggestionBecauseItIsWhatAttachesTheSelection() {
        XCTAssertNil(AIChatTextSelectionAction.ask.selectionSuggestionID)
    }

    func testSuggestionIDsMatchTheCatalogKeysInDisplayOrder() {
        XCTAssertEqual(AIChatTextSelectionAction.selectionSuggestionIDs, ["summarize-selection", "translate-selection"])
    }

    func testRoundTripsFromASuggestionID() {
        XCTAssertEqual(AIChatTextSelectionAction(selectionSuggestionID: "summarize-selection"), .summarize)
        XCTAssertEqual(AIChatTextSelectionAction(selectionSuggestionID: "translate-selection"), .translate)
    }

    func testUnknownSuggestionIDDoesNotResolve() {
        XCTAssertNil(AIChatTextSelectionAction(selectionSuggestionID: "summarize-page"))
    }
}
