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
import Combine
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

    // MARK: - Model Switch: Preserve Attachments

    func testWhenModelDoesNotSupportImagesThenAttachmentsArePreserved() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [
            makeModel(id: "image-model", supportsImageUpload: true),
            makeModel(id: "non-image-model", supportsImageUpload: false)
        ]
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "test.jpg")
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)

        sut.updateSelectedModel("non-image-model")
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
    }

    func testWhenModelDoesNotSupportImagesThenStripLayoutSuppressed() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [
            makeModel(id: "image-model", supportsImageUpload: true),
            makeModel(id: "non-image-model", supportsImageUpload: false)
        ]
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "test.jpg")

        sut.updateSelectedModel("non-image-model")
        XCTAssertFalse(sut.viewController.modelSupportsImageAttachments)
    }

    func testWhenSwitchingBackToImageModelThenStripLayoutRestored() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [
            makeModel(id: "image-model", supportsImageUpload: true),
            makeModel(id: "non-image-model", supportsImageUpload: false)
        ]
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "test.jpg")

        sut.updateSelectedModel("non-image-model")
        sut.updateSelectedModel("image-model")
        XCTAssertTrue(sut.viewController.modelSupportsImageAttachments)
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
    }

    // MARK: - Image Button Enabled State

    func testWhenStripIsFullThenImageButtonIsDisabled() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "image-model", supportsImageUpload: true)]
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "a.jpg")
        sut.addImageAttachment(image: image, fileName: "b.jpg")
        sut.addImageAttachment(image: image, fileName: "c.jpg")

        XCTAssertFalse(sut.viewController.isImageButtonEnabled)
    }

    func testWhenAttachmentRemovedFromFullStripThenImageButtonIsEnabled() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "image-model", supportsImageUpload: true)]
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "a.jpg")
        sut.addImageAttachment(image: image, fileName: "b.jpg")
        sut.addImageAttachment(image: image, fileName: "c.jpg")
        XCTAssertFalse(sut.viewController.isImageButtonEnabled)

        let firstId = sut.viewController.currentAttachments.first!.id
        sut.removeAttachment(id: firstId)
        XCTAssertTrue(sut.viewController.isImageButtonEnabled)
    }

    func testWhenConversationLimitReachedThenImageButtonIsDisabled() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "image-model", supportsImageUpload: true)]
        sut.attachmentUsage = AIChatAttachmentUsage(imagesUsed: 5, filesUsed: 0, fileSizeBytesUsed: 0)
        sut.updateImageButtonVisibility()

        XCTAssertFalse(sut.viewController.isImageButtonEnabled)
    }

    func testWhenGeneratingThenImageButtonIsDisabled() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "image-model", supportsImageUpload: true)]

        sut.aiChatStatus = .streaming
        XCTAssertFalse(sut.viewController.isImageButtonEnabled)

        sut.aiChatStatus = .ready
        XCTAssertTrue(sut.viewController.isImageButtonEnabled)
    }

    func testWhenSubmittingOnNonImageModelThenImagesAreNil() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [
            makeModel(id: "image-model", supportsImageUpload: true),
            makeModel(id: "non-image-model", supportsImageUpload: false)
        ]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "test.jpg")
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)

        sut.updateSelectedModel("non-image-model")
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)

        XCTAssertNil(delegate.submittedImages)
    }

    // MARK: - Helpers

    private func makeCoordinator(preferences: AIChatPreferencesPersisting = StubAIChatPreferences()) -> UnifiedToggleInputCoordinator {
        UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            preferences: preferences)
    }

    private func makeModel(id: String, supportsImageUpload: Bool) -> AIChatModel {
        AIChatModel(id: id, name: id, provider: .unknown, supportsImageUpload: supportsImageUpload, entityHasAccess: true)
    }
}

@MainActor
private final class SpyUnifiedToggleInputDelegate: UnifiedToggleInputDelegate {
    var submittedImages: [AIChatNativePrompt.NativePromptImage]?

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, tools: [AIChatRAGTool]?, reasoningEffort: AIChatReasoningEffort?, images: [AIChatNativePrompt.NativePromptImage]?) {
        submittedImages = images
    }
    func unifiedToggleInputDidSubmitQuery(_ query: String) {}
    func unifiedToggleInputDidRequestVoiceSearch() {}
    func unifiedToggleInputDidRequestAIChat() {}
    func unifiedToggleInputDidChangeHeight() {}
    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {}
}

private final class StubAIChatPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}
