//
//  DuckAiHighUsageModelNoticeResolverTests.swift
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
@testable import AIChat

final class DuckAiHighUsageModelNoticeResolverTests: XCTestCase {

    private var dismissalStore: InMemoryDuckAiHighUsageNoticeDismissalStore!
    private var sut: DuckAiHighUsageModelNoticeResolver!

    override func setUp() {
        super.setUp()
        dismissalStore = InMemoryDuckAiHighUsageNoticeDismissalStore()
        sut = DuckAiHighUsageModelNoticeResolver(dismissalStore: dismissalStore)
    }

    override func tearDown() {
        dismissalStore = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - The list

    /// Pins the hand-maintained mirror of web's `highUsageModelIds`.
    func testHighUsageModelIdsMatchTheWebList() {
        XCTAssertEqual(DuckAiHighUsageModels.ids, ["claude-opus-4-8"])
    }

    // MARK: - Visibility

    func testWhenTheModelIsHighUsageThenTheNoticeIsShown() {
        let notice = resolve(modelId: "claude-opus-4-8", modelShortName: "Opus 4.8")
        XCTAssertEqual(notice?.modelId, "claude-opus-4-8")
        XCTAssertEqual(notice?.modelShortName, "Opus 4.8")
    }

    func testWhenTheModelIsNotHighUsageThenNothingIsShown() {
        XCTAssertNil(resolve(modelId: "gpt-5.4-mini", modelShortName: "5.4 mini"))
    }

    func testWhenNoModelIsSelectedThenNothingIsShown() {
        XCTAssertNil(resolve(modelId: nil, modelShortName: nil))
    }

    /// The copy names the model, so an unnamed one has nothing to say.
    func testWhenTheModelHasNoShortNameThenNothingIsShown() {
        XCTAssertNil(resolve(modelId: "claude-opus-4-8", modelShortName: nil))
    }

    func testWhenTheModelShortNameIsEmptyThenNothingIsShown() {
        XCTAssertNil(resolve(modelId: "claude-opus-4-8", modelShortName: ""))
    }

    // MARK: - Dismissal

    func testWhenTheNoticeWasDismissedForThatModelThenNothingIsShown() {
        dismissalStore.setDismissed(modelId: "claude-opus-4-8")
        XCTAssertNil(resolve(modelId: "claude-opus-4-8", modelShortName: "Opus 4.8"))
    }

    /// Keyed per model, so a future high-usage model still gets its own first showing.
    func testWhenTheNoticeWasDismissedForAnotherModelThenItIsStillShown() {
        dismissalStore.setDismissed(modelId: "some-other-model")
        XCTAssertNotNil(resolve(modelId: "claude-opus-4-8", modelShortName: "Opus 4.8"))
    }

    // MARK: - Reporting

    func testWhenTheModelIsNotHighUsageThenTheReasonSaysSo() {
        guard case .none(let reason) = sut.resolve(modelId: "gpt-5.4-mini", modelShortName: "5.4 mini") else {
            return XCTFail("Expected no notice")
        }
        XCTAssertEqual(reason, .modelIsNotHighUsage)
    }

    func testWhenDismissedThenTheReasonSaysSo() {
        dismissalStore.setDismissed(modelId: "claude-opus-4-8")
        guard case .none(let reason) = sut.resolve(modelId: "claude-opus-4-8", modelShortName: "Opus 4.8") else {
            return XCTFail("Expected no notice")
        }
        XCTAssertEqual(reason, .dismissed)
    }

    // MARK: - Helpers

    private func resolve(modelId: String?, modelShortName: String?) -> DuckAiHighUsageModelNotice? {
        guard case .notice(let notice) = sut.resolve(modelId: modelId, modelShortName: modelShortName) else {
            return nil
        }
        return notice
    }
}
