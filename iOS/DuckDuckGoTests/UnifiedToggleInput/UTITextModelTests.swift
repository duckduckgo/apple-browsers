//
//  UTITextModelTests.swift
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

import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTITextModelTests: XCTestCase {

    private var appliedToView: [String] = []
    private var persistCount = 0
    private var floatingKeyUpdateCount = 0
    private var attachmentErrorClearCount = 0

    private func makeSUT() -> UTITextModel {
        UTITextModel(sideEffects: .init(
            applyTextToView: { [weak self] in self?.appliedToView.append($0) },
            persistDraft: { [weak self] in self?.persistCount += 1 },
            updateFloatingReturnKey: { [weak self] in self?.floatingKeyUpdateCount += 1 },
            clearAttachmentValidationErrorIfPossible: { [weak self] in self?.attachmentErrorClearCount += 1 }
        ))
    }

    func test_setText_setsCurrentTextAndUserTypedState_andRunsSideEffects() {
        let sut = makeSUT()

        sut.setText("hello")

        XCTAssertEqual(sut.currentText, "hello")
        XCTAssertEqual(sut.textState, .userTyped)
        XCTAssertEqual(appliedToView, ["hello"], "Programmatic setText pushes the text into the view")
        XCTAssertEqual(persistCount, 1)
        XCTAssertEqual(floatingKeyUpdateCount, 1)
    }

    func test_setText_empty_setsEmptyState() {
        let sut = makeSUT()

        sut.setText("")

        XCTAssertEqual(sut.currentText, "")
        XCTAssertEqual(sut.textState, .empty)
    }

    func test_handleUserTextChange_updatesStatePublishesAndClearsAttachmentError() {
        let sut = makeSUT()
        var published: [String] = []
        let cancellable = sut.textChangePublisher.sink { published.append($0) }
        defer { cancellable.cancel() }

        sut.handleUserTextChange("typed")

        XCTAssertEqual(sut.currentText, "typed")
        XCTAssertEqual(sut.textState, .userTyped)
        XCTAssertEqual(persistCount, 1)
        XCTAssertEqual(attachmentErrorClearCount, 1)
        XCTAssertEqual(published, ["typed"], "User text changes are published downstream")
        XCTAssertTrue(appliedToView.isEmpty, "User change comes FROM the view — must not push text back into it")
    }

    func test_handleUserTextChange_duringDismissCleanup_withEmptyText_isIgnored() {
        let sut = makeSUT()
        sut.setText("draft")
        persistCount = 0

        sut.clearForDismiss()                 // begins dismiss cleanup (isPerformingDismissCleanup == true)
        sut.handleUserTextChange("")           // the queued blanking change the view emits during dismiss

        XCTAssertEqual(sut.currentText, "draft", "The per-tab draft must survive the dismiss-time blanking")
        XCTAssertEqual(persistCount, 0, "Ignored change must not persist an empty draft")
    }

    func test_clearForDismiss_scrubsTextStateButPreservesCurrentText() {
        let sut = makeSUT()
        sut.setText("keep me")
        appliedToView.removeAll()

        sut.clearForDismiss()

        XCTAssertEqual(sut.currentText, "keep me", "Draft is preserved through dismiss cleanup")
        XCTAssertEqual(sut.textState, .empty, "Visible text state is scrubbed to empty")
        XCTAssertNil(sut.omnibarPrefilledText)
        XCTAssertEqual(appliedToView, [""], "Visible field is cleared")
        XCTAssertTrue(sut.isPerformingDismissCleanup, "Cleanup flag is set synchronously")
    }

    func test_clearForDismiss_clearsCleanupFlagOnNextRunloop() {
        let sut = makeSUT()
        sut.clearForDismiss()
        XCTAssertTrue(sut.isPerformingDismissCleanup)

        let expectation = expectation(description: "cleanup flag cleared")
        DispatchQueue.main.async {
            XCTAssertFalse(sut.isPerformingDismissCleanup, "Flag clears one runloop later, after the queued sink")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
