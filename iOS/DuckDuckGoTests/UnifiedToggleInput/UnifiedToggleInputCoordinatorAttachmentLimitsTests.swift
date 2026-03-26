//
//  UnifiedToggleInputCoordinatorAttachmentLimitsTests.swift
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
final class UnifiedToggleInputCoordinatorAttachmentLimitsTests: XCTestCase {

    func testWhenNoUsageThenRemainingImagesIsMax() {
        let sut = makeCoordinator()
        XCTAssertEqual(sut.remainingImagesInConversation, 5)
    }

    func testWhenSomeImagesUsedThenRemainingImagesReflectsUsage() {
        let sut = makeCoordinator()
        sut.attachmentUsage = AIChatAttachmentUsage(imagesUsed: 3, filesUsed: 0, fileSizeBytesUsed: 0)
        XCTAssertEqual(sut.remainingImagesInConversation, 2)
    }

    func testWhenImagesAtLimitThenRemainingIsZeroAndLimitReached() {
        let sut = makeCoordinator()
        sut.attachmentUsage = AIChatAttachmentUsage(imagesUsed: 5, filesUsed: 0, fileSizeBytesUsed: 0)
        XCTAssertEqual(sut.remainingImagesInConversation, 0)
        XCTAssertTrue(sut.isConversationImageLimitReached)
    }

    func testWhenImagesOverLimitThenRemainingClampsToZero() {
        let sut = makeCoordinator()
        sut.attachmentUsage = AIChatAttachmentUsage(imagesUsed: 7, filesUsed: 0, fileSizeBytesUsed: 0)
        XCTAssertEqual(sut.remainingImagesInConversation, 0)
    }

    func testWhenConversationNearLimitThenPickerLimitReflectsMinimum() {
        let sut = makeCoordinator()
        sut.attachmentUsage = AIChatAttachmentUsage(imagesUsed: 4, filesUsed: 0, fileSizeBytesUsed: 0)
        XCTAssertEqual(sut.remainingImagesForPicker, 1)
    }

    func testWhenNewChatStartedThenUsageResets() {
        let sut = makeCoordinator()
        sut.attachmentUsage = AIChatAttachmentUsage(imagesUsed: 5, filesUsed: 0, fileSizeBytesUsed: 0)
        sut.startNewChat()
        XCTAssertNil(sut.attachmentUsage)
        XCTAssertEqual(sut.remainingImagesInConversation, 5)
    }

    // MARK: - Helpers

    private func makeCoordinator() -> UnifiedToggleInputCoordinator {
        UnifiedToggleInputCoordinator(
            isToggleEnabled: true,
            preferences: StubAIChatPreferences())
    }
}

private final class StubAIChatPreferences: AIChatPreferencesPersisting {
    var selectedModelId: String?
    var selectedModelShortName: String?
}
