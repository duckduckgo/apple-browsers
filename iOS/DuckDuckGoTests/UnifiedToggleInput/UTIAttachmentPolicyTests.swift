//
//  UTIAttachmentPolicyTests.swift
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

final class UTIAttachmentPolicyTests: XCTestCase {

    func testWhenNoUsageThenRemainingImagesIsMax() {
        let policy = UTIAttachmentPolicy(attachmentUsage: nil, pendingAttachmentCount: 0)
        XCTAssertEqual(policy.remainingImagesInConversation, 5)
    }

    func testWhenSomeImagesUsedThenRemainingReflectsUsage() {
        let policy = UTIAttachmentPolicy(
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 3, filesUsed: 0, fileSizeBytesUsed: 0),
            pendingAttachmentCount: 0
        )
        XCTAssertEqual(policy.remainingImagesInConversation, 2)
    }

    func testWhenImagesAtLimitThenRemainingIsZeroAndLimitReached() {
        let policy = UTIAttachmentPolicy(
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 5, filesUsed: 0, fileSizeBytesUsed: 0),
            pendingAttachmentCount: 0
        )
        XCTAssertEqual(policy.remainingImagesInConversation, 0)
        XCTAssertTrue(policy.isConversationImageLimitReached)
    }

    func testWhenImagesOverLimitThenRemainingClampsToZero() {
        let policy = UTIAttachmentPolicy(
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 7, filesUsed: 0, fileSizeBytesUsed: 0),
            pendingAttachmentCount: 0
        )
        XCTAssertEqual(policy.remainingImagesInConversation, 0)
    }

    func testWhenConversationNearLimitThenPickerLimitReflectsMinimum() {
        let policy = UTIAttachmentPolicy(
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 4, filesUsed: 0, fileSizeBytesUsed: 0),
            pendingAttachmentCount: 0
        )
        XCTAssertEqual(policy.remainingImagesForPicker, 1)
    }

    func testWhenPendingAttachmentsExistThenPickerLimitReduced() {
        let policy = UTIAttachmentPolicy(attachmentUsage: nil, pendingAttachmentCount: 2)
        XCTAssertEqual(policy.remainingImagesForPicker, 1)
    }

    func testWhenPendingAttachmentsAtPerTurnMaxThenPickerReturnsZero() {
        let policy = UTIAttachmentPolicy(attachmentUsage: nil, pendingAttachmentCount: 3)
        XCTAssertEqual(policy.remainingImagesForPicker, 0)
    }

    func testWhenNoUsageAndNoPendingThenNotLimitReached() {
        let policy = UTIAttachmentPolicy(attachmentUsage: nil, pendingAttachmentCount: 0)
        XCTAssertFalse(policy.isConversationImageLimitReached)
    }

    func testPickerLimitRespectsConversationAndPerTurnMinimum() {
        let policy = UTIAttachmentPolicy(
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 3, filesUsed: 0, fileSizeBytesUsed: 0),
            pendingAttachmentCount: 1
        )
        XCTAssertEqual(policy.remainingImagesForPicker, 1)
    }
}
