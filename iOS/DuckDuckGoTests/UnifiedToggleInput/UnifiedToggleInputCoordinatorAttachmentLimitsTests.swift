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

    // MARK: - Model Switch: Unsupported Attachments

    func testWhenModelDoesNotSupportImagesThenImageAttachmentsAreCleared() {
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
        XCTAssertEqual(sut.viewController.currentAttachments.count, 0)
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
        XCTAssertTrue(sut.viewController.isImageButtonHidden)
    }

    func testWhenSwitchingBackToImageModelThenClearedImageAttachmentsAreNotRestored() {
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
        XCTAssertFalse(sut.viewController.isImageButtonHidden)
        XCTAssertEqual(sut.viewController.currentAttachments.count, 0)
    }

    func testWhenModelDoesNotSupportFilesThenFileAttachmentsAreCleared() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [
            makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"]),
            makeModel(id: "image-model", supportsImageUpload: true)
        ]
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)

        sut.updateSelectedModel("image-model")

        XCTAssertEqual(sut.viewController.currentAttachments.count, 0)
    }

    // MARK: - Image Button Enabled State

    func testWhenImageLimitReachedThenImageButtonIsDisabled() {
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

    func testWhenImageRemovedFromImageLimitThenImageButtonIsEnabled() {
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

    func testWhenImageLimitReachedButFilesRemainThenAttachmentButtonIsEnabled() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "a.jpg")
        sut.addImageAttachment(image: image, fileName: "b.jpg")
        sut.addImageAttachment(image: image, fileName: "c.jpg")

        XCTAssertTrue(sut.viewController.isImageButtonEnabled)
    }

    func testWhenImageLimitReachedButFilesRemainThenAttachmentMenuOnlyShowsFileAction() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "a.jpg")
        sut.addImageAttachment(image: image, fileName: "b.jpg")
        sut.addImageAttachment(image: image, fileName: "c.jpg")

        let menuTitles = attachmentMenuTitles(for: sut)
        XCTAssertEqual(menuTitles, [UserText.aiChatAttachmentOptionAttachFile])
    }

    func testWhenFileLimitReachedButImagesRemainThenAttachmentButtonIsEnabled() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))
        sut.addFileAttachment(makeFileAttachment(fileName: "b.pdf"))
        sut.addFileAttachment(makeFileAttachment(fileName: "c.pdf"))

        XCTAssertTrue(sut.viewController.isImageButtonEnabled)
    }

    func testWhenFileLimitReachedButImagesRemainThenAttachmentMenuKeepsPhotoAction() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))
        sut.addFileAttachment(makeFileAttachment(fileName: "b.pdf"))
        sut.addFileAttachment(makeFileAttachment(fileName: "c.pdf"))

        let menuTitles = attachmentMenuTitles(for: sut)
        XCTAssertTrue(menuTitles.contains(UserText.aiChatAttachmentOptionAttachPhoto))
        XCTAssertFalse(menuTitles.contains(UserText.aiChatAttachmentOptionAttachFile))
    }

    func testWhenImageAndFileAvailableThenAttachmentMenuShowsPhotoAndFileActions() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.updateImageButtonVisibility()

        let menuTitles = attachmentMenuTitles(for: sut)
        XCTAssertTrue(menuTitles.contains(UserText.aiChatAttachmentOptionAttachPhoto))
        XCTAssertTrue(menuTitles.contains(UserText.aiChatAttachmentOptionAttachFile))
    }

    func testWhenSubmittingMixedAttachmentsThenImagesAndFilesAreSubmitted() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "a.jpg")
        sut.addImageAttachment(image: image, fileName: "b.jpg")
        sut.addImageAttachment(image: image, fileName: "c.jpg")
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))
        sut.addFileAttachment(makeFileAttachment(fileName: "b.pdf"))
        sut.addFileAttachment(makeFileAttachment(fileName: "c.pdf"))

        XCTAssertEqual(sut.viewController.currentAttachments.count, 6)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)

        XCTAssertEqual(delegate.submittedImages?.count, 3)
        XCTAssertEqual(delegate.submittedFiles?.count, 3)
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

        XCTAssertEqual(sut.viewController.currentAttachments.count, 0)
        XCTAssertNil(delegate.submittedImages)
    }

    func testWhenFileUsageBecomesOverLimitBeforeSubmitThenPromptDoesNotSubmitAndAttachmentsRemain() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))
        sut.attachmentUsage = AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 3, fileSizeBytesUsed: 0)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)

        XCTAssertNil(delegate.submittedFiles)
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
    }

    func testWhenImageUsageBecomesOverLimitBeforeSubmitThenPromptDoesNotSubmitAndAttachmentsRemain() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "image-model", supportsImageUpload: true)]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "a.jpg")
        sut.attachmentUsage = AIChatAttachmentUsage(imagesUsed: 5, filesUsed: 0, fileSizeBytesUsed: 0)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)

        XCTAssertNil(delegate.submittedImages)
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
    }

    // MARK: - Helpers

    private func makeCoordinator(preferences: AIChatPreferencesPersisting = StubAIChatPreferences()) -> UnifiedToggleInputCoordinator {
        let coordinator = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            preferences: preferences)
        coordinator.modelStore.attachmentLimits = makeLimits()
        return coordinator
    }

    private func makeModel(id: String, supportsImageUpload: Bool, supportedFileTypes: [String] = []) -> AIChatModel {
        AIChatModel(id: id, name: id, provider: .unknown, supportsImageUpload: supportsImageUpload, supportedFileTypes: supportedFileTypes, entityHasAccess: true)
    }

    private func makeLimits() -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 8),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: 4500)
        )
    }

    private func makeFileAttachment(fileName: String = "test.pdf") -> AIChatFileAttachment {
        let data = Data(repeating: 0, count: 1_000)
        return AIChatFileAttachment(
            data: data,
            fileName: fileName,
            mimeType: "application/pdf",
            fileSizeBytes: data.count,
            pageCount: 1
        )
    }

    private func attachmentMenuTitles(for coordinator: UnifiedToggleInputCoordinator) -> [String] {
        coordinator.viewController.attachmentMenu?.children.map(\.title) ?? []
    }
}

@MainActor
private final class SpyUnifiedToggleInputDelegate: UnifiedToggleInputDelegate {
    var submittedImages: [AIChatNativePrompt.NativePromptImage]?
    var submittedFiles: [AIChatNativePrompt.NativePromptFile]?

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, tools: [AIChatRAGTool]?, reasoningEffort: AIChatReasoningEffort?, images: [AIChatNativePrompt.NativePromptImage]?, files: [AIChatNativePrompt.NativePromptFile]?) {
        submittedImages = images
        submittedFiles = files
    }
    func unifiedToggleInputDidSubmitQuery(_ query: String) {}
    func unifiedToggleInputDidRequestVoiceSearch() {}
    func unifiedToggleInputDidRequestAIVoiceChat() {}
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
