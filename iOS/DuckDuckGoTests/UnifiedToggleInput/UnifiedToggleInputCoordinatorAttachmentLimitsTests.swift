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
import UIKit
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

    func testWhenImageLimitReachedButFilesRemainThenAttachmentMenuKeepsImageActionsDisabled() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let image = UIImage(systemName: "photo")!
        sut.addImageAttachment(image: image, fileName: "a.jpg")
        sut.addImageAttachment(image: image, fileName: "b.jpg")
        sut.addImageAttachment(image: image, fileName: "c.jpg")

        let actions = attachmentMenuActionsByTitle(for: sut)
        XCTAssertTrue(actions[UserText.aiChatAttachmentOptionAttachPhoto]?.attributes.contains(.disabled) == true)
        XCTAssertFalse(actions[UserText.aiChatAttachmentOptionAttachFile]?.attributes.contains(.disabled) == true)
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

        let actions = attachmentMenuActionsByTitle(for: sut)
        XCTAssertFalse(actions[UserText.aiChatAttachmentOptionAttachPhoto]?.attributes.contains(.disabled) == true)
        XCTAssertTrue(actions[UserText.aiChatAttachmentOptionAttachFile]?.attributes.contains(.disabled) == true)
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

    func testWhenPageContextActionAvailableThenAttachmentMenuShowsAskAboutPageAction() {
        let sut = makeCoordinator(host: .contextualChat)
        var attachCallCount = 0
        sut.onPageContextAttachRequested = { attachCallCount += 1 }
        sut.updateImageButtonVisibility()

        let actions = attachmentMenuActionsByTitle(for: sut)
        XCTAssertTrue(actions[UserText.aiChatAttachmentOptionAttachPhoto]?.attributes.contains(.disabled) == true)
        XCTAssertTrue(actions[UserText.aiChatAttachmentOptionAttachFile]?.attributes.contains(.disabled) == true)
        XCTAssertFalse(actions[UserText.aiChatAttachmentOptionAskAboutPage]?.attributes.contains(.disabled) == true)

        let action = actions[UserText.aiChatAttachmentOptionAskAboutPage]
        if #available(iOS 16.0, *) {
            action?.performWithSender(nil, target: nil)
        }

        XCTAssertFalse(sut.viewController.isImageButtonHidden)
        XCTAssertTrue(sut.viewController.isImageButtonEnabled)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(attachCallCount, 1)
        }
    }

    func testWhenPageContextNotAttachableButOtherAttachmentsAvailableThenAskAboutPageActionIsDisabled() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(host: .contextualChat, preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.onPageContextAttachRequested = {}
        sut.isPageContextAttachable = { false }
        sut.updateImageButtonVisibility()

        let actions = attachmentMenuActionsByTitle(for: sut)
        // The menu still shows (photo/file available); the page-context item is disabled.
        XCTAssertNotNil(actions[UserText.aiChatAttachmentOptionAttachPhoto])
        XCTAssertTrue(actions[UserText.aiChatAttachmentOptionAskAboutPage]?.attributes.contains(.disabled) == true)
    }

    func testWhenPageContextIsOnlyAttachmentAndNotAttachableThenAttachButtonHidden() {
        let sut = makeCoordinator(host: .contextualChat)
        sut.onPageContextAttachRequested = {}
        sut.isPageContextAttachable = { false }
        sut.updateImageButtonVisibility()

        XCTAssertTrue(sut.viewController.isImageButtonHidden)
    }

    func testWhenPageContextActionAvailableOutsideContextualChatThenAttachmentMenuDoesNotShowAskAboutPageAction() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(host: .omnibar, preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.onPageContextAttachRequested = {}
        sut.showExpanded()
        sut.updateImageButtonVisibility()

        let menuTitles = attachmentMenuTitles(for: sut)
        XCTAssertTrue(menuTitles.contains(UserText.aiChatAttachmentOptionAttachPhoto))
        XCTAssertTrue(menuTitles.contains(UserText.aiChatAttachmentOptionAttachFile))
        XCTAssertFalse(menuTitles.contains(UserText.aiChatAttachmentOptionAskAboutPage))
    }

    func testWhenPageContextActionAvailableThenAttachmentMenuKeepsFixedRawOrder() {
        let sut = makeCoordinator(host: .contextualChat)
        sut.onPageContextAttachRequested = {}
        sut.updateImageButtonVisibility()

        let rawTitles = attachmentMenuActions(for: sut).map(\.title)

        XCTAssertEqual(rawTitles, [
            UserText.aiChatAttachmentOptionTakePhoto,
            UserText.aiChatAttachmentOptionAttachPhoto,
            UserText.aiChatAttachmentOptionAttachFile,
            UserText.aiChatAttachmentOptionAskAboutPage
        ])
    }

    func testWhenPageContextAndOtherAttachmentsAvailableThenAskAboutPageIsLast() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(host: .contextualChat, preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.onPageContextAttachRequested = {}
        sut.updateImageButtonVisibility()

        let menuTitles = attachmentMenuTitles(for: sut)
        XCTAssertTrue(menuTitles.contains(UserText.aiChatAttachmentOptionAttachPhoto))
        XCTAssertTrue(menuTitles.contains(UserText.aiChatAttachmentOptionAttachFile))
        XCTAssertEqual(menuTitles.last, UserText.aiChatAttachmentOptionAskAboutPage)
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

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat, trigger: .sendButton)

        XCTAssertEqual(delegate.submittedAttachments?.images?.count, 3)
        XCTAssertEqual(delegate.submittedAttachments?.files?.count, 3)
    }

    func testWhenSubmittingFileAttachmentWithoutTextThenFileIsSubmitted() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "", mode: .aiChat, trigger: .sendButton)

        XCTAssertEqual(delegate.submittedPrompt, "")
        XCTAssertEqual(delegate.submittedAttachments?.files?.count, 1)
    }

    func testWhenToolbarSubmitHasFileAttachmentWithoutTextThenFileIsSubmitted() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))

        sut.unifiedToggleInputVCDidRequestSubmitCurrentInput(sut.viewController)
        flushMainQueue()

        XCTAssertEqual(delegate.submittedPrompt, "")
        XCTAssertEqual(delegate.submittedAttachments?.files?.count, 1)
    }

    func testWhenToolbarAttachmentOnlySubmitWouldExceedFileLimitThenPromptDoesNotSubmit() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        sut.updateInputMode(.aiChat, animated: false)
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))
        sut.attachmentUsage = AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 3, fileSizeBytesUsed: 0)

        sut.unifiedToggleInputVCDidRequestSubmitCurrentInput(sut.viewController)

        XCTAssertNil(delegate.submittedPrompt)
        XCTAssertNil(delegate.submittedAttachments?.files)
        XCTAssertEqual(
            sut.viewController.attachmentValidationMessage,
            UserText.aiChatAttachmentFileCountLimit(maxFilesPerConversation: 3)
        )
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
    }

    func testWhenFileValidationFailsThenInvalidAttachmentIsAdded() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]

        sut.addFileAttachment(makeFileAttachment(fileName: "too-many-pages.pdf", pageCount: 9))

        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
        XCTAssertTrue(sut.viewController.currentAttachments.first?.isInvalid ?? false)
        XCTAssertEqual(
            sut.viewController.currentAttachments.first?.validationMessage,
            UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 8)
        )
    }

    func testWhenInvalidFileAttachmentIsPresentThenPromptDoesNotSubmit() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        sut.addFileAttachment(makeFileAttachment(fileName: "too-many-pages.pdf", pageCount: 9))

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat, trigger: .sendButton)

        XCTAssertNil(delegate.submittedPrompt)
        XCTAssertNil(delegate.submittedAttachments?.files)
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
    }

    func testWhenModelChangeMakesInvalidFileValidThenAttachmentIsPromoted() throws {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "unsupported-file-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [
            makeModel(id: "unsupported-file-model", supportsImageUpload: true, supportedFileTypes: []),
            makeModel(id: "file-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])
        ]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        let fileData = makePDFData()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-\(UUID().uuidString).pdf")
        try fileData.write(to: fileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        sut.updateInputMode(.aiChat, animated: false)
        sut.addFileAttachment(
            AIChatFileAttachment(
                data: fileData,
                fileName: "a.pdf",
                mimeType: "application/pdf",
                fileSizeBytes: fileData.count
            ),
            sourceURL: fileURL
        )
        XCTAssertTrue(sut.viewController.currentAttachments.first?.isInvalid ?? false)
        XCTAssertNotNil(sut.viewController.attachmentValidationMessage)

        sut.updateSelectedModel("file-model")

        waitUntil("invalid file is promoted after source recovery") {
            sut.viewController.currentAttachments.first?.fileAttachment != nil
        }
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
        XCTAssertFalse(sut.viewController.currentAttachments.first?.isInvalid ?? true)
        XCTAssertEqual(sut.viewController.currentAttachments.first?.fileAttachment?.fileName, "a.pdf")
        XCTAssertEqual(sut.viewController.currentAttachments.first?.fileAttachment?.data, fileData)
        XCTAssertNil(sut.viewController.attachmentValidationMessage)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "use the file", mode: .aiChat, trigger: .sendButton)

        XCTAssertEqual(delegate.submittedPrompt, "use the file")
        XCTAssertEqual(delegate.submittedAttachments?.files?.count, 1)
        XCTAssertEqual(delegate.submittedAttachments?.files?.first?.fileName, "a.pdf")
        XCTAssertEqual(delegate.submittedAttachments?.files?.first?.mimeType, "application/pdf")
    }

    func testWhenModelChangeMakesInvalidFileValidButSourceIsMissingThenExistingErrorIsPreserved() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "unsupported-file-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [
            makeModel(id: "unsupported-file-model", supportsImageUpload: true, supportedFileTypes: []),
            makeModel(id: "file-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])
        ]
        let validationMessage = UserText.aiChatAttachmentUnsupportedFileType
        sut.viewController.addAttachment(.invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                fileName: "a.pdf",
                mimeType: "application/pdf",
                fileSizeBytes: 1_000,
                validationMessage: validationMessage,
                sourceURL: nil
            )
        ))
        sut.viewController.showAttachmentValidationError(validationMessage)

        sut.updateSelectedModel("file-model")

        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
        XCTAssertTrue(sut.viewController.currentAttachments.first?.isInvalid ?? false)
        XCTAssertEqual(sut.viewController.attachmentValidationMessage, validationMessage)
    }

    func testWhenToolbarSubmitHasInvalidAttachmentThenPromptDoesNotSubmit() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        sut.addFileAttachment(makeFileAttachment(fileName: "too-many-pages.pdf", pageCount: 9))

        sut.unifiedToggleInputVCDidRequestSubmitCurrentInput(sut.viewController)

        XCTAssertNil(delegate.submittedPrompt)
        XCTAssertNil(delegate.submittedAttachments?.files)
        XCTAssertEqual(
            sut.viewController.attachmentValidationMessage,
            UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 8)
        )
    }

    func testWhenSwitchingToSearchThenBackToDuckAIAttachmentsArePreserved() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))

        sut.updateInputMode(.search, animated: false)

        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)

        sut.updateInputMode(.aiChat, animated: false)

        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
        XCTAssertEqual(sut.viewController.currentAttachments.first?.fileName, "a.pdf")
    }

    func testWhenSwitchingInvalidAttachmentToSearchThenBackToDuckAIErrorReturns() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.addFileAttachment(makeFileAttachment(fileName: "too-many-pages.pdf", pageCount: 9))
        let expectedMessage = UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 8)
        XCTAssertEqual(sut.viewController.attachmentValidationMessage, expectedMessage)

        sut.updateInputMode(.search, animated: false)

        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
        XCTAssertNil(sut.viewController.attachmentValidationMessage)

        sut.updateInputMode(.aiChat, animated: false)

        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
        XCTAssertEqual(sut.viewController.attachmentValidationMessage, expectedMessage)
    }

    func testTransientLimitBannerSurvivesAsyncModelResync() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "image-model", supportsImageUpload: true, supportedFileTypes: [])]
        sut.activateFromOmnibar(inputMode: .aiChat)

        let limitMessage = UserText.aiChatAttachmentImageTurnLimit(maxImagesPerTurn: 3)
        sut.presentPasteError(limitMessage)
        XCTAssertEqual(sut.viewController.attachmentValidationMessage, limitMessage)

        // A models refresh (onModelsUpdated fires on a Duck.ai tab, routing through handleModelsUpdated) must not clear a limit banner that isn't backed by an attachment.
        sut.updateSelectedModel("image-model")
        XCTAssertEqual(sut.viewController.attachmentValidationMessage, limitMessage)

        // A genuine user action still clears it.
        sut.clearAttachments()
        XCTAssertNil(sut.viewController.attachmentValidationMessage)
    }

    func testTransientLimitBannerDoesNotLeakToAnotherTab() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "image-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "image-model", supportsImageUpload: true, supportedFileTypes: [])]
        sut.activateFromOmnibar(inputMode: .aiChat)

        sut.presentPasteError(UserText.aiChatAttachmentImageTurnLimit(maxImagesPerTurn: 3))
        XCTAssertNotNil(sut.viewController.attachmentValidationMessage)

        // Loading another tab's state (an aiChat tab with no invalid attachment) must not re-show the previous tab's paste banner.
        sut.applyState(TabInputState(toggleMode: .aiChat))
        XCTAssertNil(sut.viewController.attachmentValidationMessage)
    }

    func testAttachmentErrorBannerDisplaysAllAttachmentErrorCopy() {
        let sut = makeCoordinator()
        let messages = [
            UserText.aiChatAttachmentFileCountLimit(maxFilesPerConversation: 3),
            UserText.aiChatAttachmentFileEncrypted,
            UserText.aiChatAttachmentFilesExceedTotalSizeLimit(maxTotalFileSizeMB: 5),
            UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: 5),
            UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 15),
            UserText.aiChatAttachmentFileUnreadable,
            UserText.aiChatAttachmentImageCountLimit(maxImagesPerConversation: 5),
            UserText.aiChatAttachmentImageTurnLimit(maxImagesPerTurn: 3),
            UserText.aiChatAttachmentPromptTooLong,
            UserText.aiChatAttachmentUnavailable,
            UserText.aiChatAttachmentUnsupportedFileType,
            UserText.aiChatAttachmentUnsupportedFileType(acceptedFileType: "PDF"),
            UserText.aiChatAttachmentUnsupportedFileType(acceptedFileTypes: ["PNG", "JPG", "PDF"]),
        ]

        for message in messages {
            sut.viewController.showAttachmentValidationError(message)

            XCTAssertEqual(sut.viewController.attachmentValidationMessage, message)
            XCTAssertTrue(viewContainsLabelText(message, in: sut.viewController.view), message)
        }
    }

    func testWhenSubmittingSearchAfterAddingAttachmentThenAttachmentsAreCleared() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))
        sut.updateInputMode(.search, animated: false)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "example", mode: .search, trigger: .sendButton)

        XCTAssertEqual(sut.viewController.currentAttachments.count, 0)
        XCTAssertNil(sut.viewController.attachmentValidationMessage)
    }

    func testWhenSubmittingSearchFromDuckAITabAfterAddingAttachmentThenLiveInputIsCleared() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.showExpanded(inputMode: .aiChat)
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))
        sut.setText("example")
        sut.updateInputMode(.search, animated: false)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "example", mode: .search, trigger: .sendButton)

        XCTAssertEqual(sut.viewController.currentAttachments.count, 0)
        XCTAssertNil(sut.viewController.attachmentValidationMessage)
        XCTAssertEqual(sut.viewController.text, "")
    }

    func testWhenExternalQuerySubmissionFromDuckAITabAfterAddingAttachmentThenLiveInputIsCleared() {
        let prefs = StubAIChatPreferences()
        prefs.selectedModelId = "mixed-model"
        let sut = makeCoordinator(preferences: prefs)
        sut.modelStore.models = [makeModel(id: "mixed-model", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])]
        sut.showExpanded(inputMode: .aiChat)
        sut.addFileAttachment(makeFileAttachment(fileName: "a.pdf"))
        sut.setText("example")

        sut.handleExternalSubmission(.query)

        XCTAssertEqual(sut.viewController.currentAttachments.count, 0)
        XCTAssertNil(sut.viewController.attachmentValidationMessage)
        XCTAssertEqual(sut.viewController.text, "")
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
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat, trigger: .sendButton)

        XCTAssertEqual(sut.viewController.currentAttachments.count, 0)
        XCTAssertNil(delegate.submittedAttachments?.images)
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

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat, trigger: .sendButton)

        XCTAssertNil(delegate.submittedAttachments?.files)
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

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat, trigger: .sendButton)

        XCTAssertNil(delegate.submittedAttachments?.images)
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
    }

    private func longText(_ count: Int) -> String { String(repeating: "a", count: count) }

    private func addPastedText(_ text: String, to sut: UnifiedToggleInputCoordinator) {
        sut.viewController.addAttachment(.pastedText(AIChatPastedText(content: text)))
    }

    func testPasteOnlyPromptIsDeliveredWithEmptyTextAndThePasteInThePayload() throws {
        let sut = makePastedTextCoordinator()
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        sut.updateInputMode(.aiChat, animated: false)
        addPastedText(longText(4_000), to: sut)

        sut.unifiedToggleInputVCDidRequestSubmitCurrentInput(sut.viewController)
        flushMainQueue()

        XCTAssertEqual(delegate.submittedPrompt, "")
        XCTAssertEqual(delegate.submittedAttachments?.textPasted, [AIChatNativePrompt.NativePromptPastedText(content: longText(4_000))])
        XCTAssertEqual(delegate.submittedAttachments?.isEmpty, false, "A paste-only prompt must not be dropped as empty")
        XCTAssertNil(delegate.submittedAttachments?.images)
        XCTAssertNil(delegate.submittedAttachments?.files)
    }

    func testTextAndTwoPastesAreDeliveredInPasteOrder() throws {
        let sut = makePastedTextCoordinator()
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        sut.updateInputMode(.aiChat, animated: false)
        let first = longText(4_000)
        let second = String(repeating: "b", count: 4_000)
        addPastedText(first, to: sut)
        addPastedText(second, to: sut)
        sut.setText("Summarise these")

        sut.unifiedToggleInputVCDidRequestSubmitCurrentInput(sut.viewController)
        flushMainQueue()

        XCTAssertEqual(delegate.submittedPrompt, "Summarise these")
        XCTAssertEqual(delegate.submittedAttachments?.textPasted?.map(\.content), [first, second])
    }

    func testPastedTextIsSentToTheFrontendOnlyThroughThePayloadNotTheURL() throws {
        let sut = makePastedTextCoordinator()
        let delegate = SpyUnifiedToggleInputDelegate()
        sut.delegate = delegate
        sut.updateInputMode(.aiChat, animated: false)
        addPastedText(longText(4_000), to: sut)
        sut.setText("typed")

        sut.unifiedToggleInputVCDidRequestSubmitCurrentInput(sut.viewController)
        flushMainQueue()

        XCTAssertEqual(delegate.submittedPrompt, "typed", "Only the typed text reaches the URL builder")
        XCTAssertFalse(delegate.submittedPrompt?.contains(longText(4_000)) ?? true)
    }

    func testEditWithPastesMakesViewOnlyChipsAndRepliesWithWhatRemains() async throws {
        let sut = makePastedTextCoordinator()
        sut.updateInputMode(.aiChat, animated: false)
        let request = EditPromptRequest(prompt: "sent", attachments: AIChatPromptAttachments(textPasted: [.init(content: "one"), .init(content: "two")]), hasResponsesToLose: false)

        let editTask = Task { await sut.editPrompt(request) }
        await Task.yield()
        XCTAssertEqual(sut.viewController.currentAttachments.compactMap(\.pastedText).map(\.content), ["one", "two"])
        sut.removeAttachment(id: sut.viewController.currentAttachments[0].id)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "edited", mode: .aiChat, trigger: .sendButton)
        let json = try await encodedReply(editTask)

        XCTAssertEqual(json, #"{"prompt":"edited","textPasted":[{"content":"two"}]}"#)
    }

    func testEditWithAllPastesRemovedRepliesWithAnEmptyList() async throws {
        let sut = makePastedTextCoordinator()
        sut.updateInputMode(.aiChat, animated: false)
        let request = EditPromptRequest(prompt: "sent", attachments: AIChatPromptAttachments(textPasted: [.init(content: "one")]), hasResponsesToLose: false)

        let editTask = Task { await sut.editPrompt(request) }
        await Task.yield()
        sut.clearAttachments()

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "edited", mode: .aiChat, trigger: .sendButton)
        let json = try await encodedReply(editTask)

        XCTAssertEqual(json, #"{"prompt":"edited","textPasted":[]}"#)
    }

    func testEditWithPastesWhileTheFlagIsOffMakesNoChipsAndLeavesTheKeyOut() async throws {
        let sut = makeCoordinator()
        sut.updateInputMode(.aiChat, animated: false)
        let request = EditPromptRequest(prompt: "sent", attachments: AIChatPromptAttachments(textPasted: [.init(content: "one")]), hasResponsesToLose: false)

        let editTask = Task { await sut.editPrompt(request) }
        await Task.yield()
        XCTAssertTrue(sut.viewController.currentAttachments.isEmpty)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "edited", mode: .aiChat, trigger: .sendButton)
        let json = try await encodedReply(editTask)

        XCTAssertEqual(json, #"{"prompt":"edited"}"#)
    }

    func testEditWithoutPastesLeavesTheKeyOutEvenWithTheFlagOn() async throws {
        let sut = makePastedTextCoordinator()
        sut.updateInputMode(.aiChat, animated: false)
        let request = EditPromptRequest(prompt: "sent", attachments: .none, hasResponsesToLose: false)

        let editTask = Task { await sut.editPrompt(request) }
        await Task.yield()

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "edited", mode: .aiChat, trigger: .sendButton)
        let json = try await encodedReply(editTask)

        XCTAssertEqual(json, #"{"prompt":"edited"}"#)
    }

    func testEditWithAnEmptyPromptAndAKeptPasteIsSent() async throws {
        let sut = makePastedTextCoordinator()
        sut.updateInputMode(.aiChat, animated: false)
        let request = EditPromptRequest(prompt: "sent", attachments: AIChatPromptAttachments(textPasted: [.init(content: "kept")]), hasResponsesToLose: false)

        let editTask = Task { await sut.editPrompt(request) }
        await Task.yield()
        sut.setText("")

        sut.unifiedToggleInputVCDidRequestSubmitCurrentInput(sut.viewController)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let json = try await encodedReply(editTask)

        XCTAssertEqual(json, #"{"prompt":"","textPasted":[{"content":"kept"}]}"#)
    }

    private func encodedReply(_ editTask: Task<EditPromptReply, Never>) async throws -> String {
        let reply = await editTask.value
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try XCTUnwrap(String(data: encoder.encode(reply), encoding: .utf8))
    }

    // MARK: - Helpers

    private func makePastedTextCoordinator(preferences: AIChatPreferencesPersisting = StubAIChatPreferences()) -> UnifiedToggleInputCoordinator {
        let coordinator = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            preferences: preferences,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInputPastedText]))
        coordinator.modelStore.attachmentLimits = makeLimits()
        return coordinator
    }

    private func makeCoordinator(host: UnifiedToggleInputHost = .omnibar,
                                 preferences: AIChatPreferencesPersisting = StubAIChatPreferences(),
                                 duckAIWideEventInstrumentation: DuckAIWideEventInstrumentation? = nil) -> UnifiedToggleInputCoordinator {
        let coordinator = UnifiedToggleInputCoordinator(
            host: host,
            isToggleEnabled: host == .omnibar,
            preferences: preferences,
            duckAIWideEventInstrumentation: duckAIWideEventInstrumentation)
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

    private func makeFileAttachment(fileName: String = "test.pdf", pageCount: Int? = 1) -> AIChatFileAttachment {
        let data = Data(repeating: 0, count: 1_000)
        return AIChatFileAttachment(
            data: data,
            fileName: fileName,
            mimeType: "application/pdf",
            fileSizeBytes: data.count,
            pageCount: pageCount
        )
    }

    private func makePDFData() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        return renderer.pdfData { context in
            context.beginPage()
            "test".draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
    }

    private func viewContainsLabelText(_ text: String, in view: UIView) -> Bool {
        if let label = view as? UILabel, label.text == text {
            return true
        }

        return view.subviews.contains { viewContainsLabelText(text, in: $0) }
    }

    private func attachmentMenuTitles(for coordinator: UnifiedToggleInputCoordinator) -> [String] {
        visibleAttachmentMenuActions(for: coordinator).map(\.title)
    }

    private func visibleAttachmentMenuActions(for coordinator: UnifiedToggleInputCoordinator) -> [UIAction] {
        attachmentMenuActions(for: coordinator)
            .filter { !$0.attributes.contains(.hidden) }
    }

    private func attachmentMenuActions(for coordinator: UnifiedToggleInputCoordinator) -> [UIAction] {
        coordinator.viewController.attachmentMenu?.children.compactMap { $0 as? UIAction } ?? []
    }

    private func attachmentMenuActionsByTitle(for coordinator: UnifiedToggleInputCoordinator) -> [String: UIAction] {
        Dictionary(uniqueKeysWithValues: attachmentMenuActions(for: coordinator).map { ($0.title, $0) })
    }

    private func flushMainQueue() {
        let expectation = expectation(description: "main queue flushed")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 2, condition: @escaping () -> Bool) {
        if condition() {
            return
        }

        let expectation = expectation(description: description)

        func poll() {
            if condition() {
                expectation.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    poll()
                }
            }
        }

        poll()
        wait(for: [expectation], timeout: timeout)
    }
}

@MainActor
private final class SpyUnifiedToggleInputDelegate: UnifiedToggleInputDelegate {
    var submittedPrompt: String?
    var submittedAttachments: AIChatPromptAttachments?

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, tools: [AIChatRAGTool]?, reasoningEffort: AIChatReasoningEffort?, attachments: AIChatPromptAttachments, termsAccepted: Bool) {
        submittedPrompt = prompt
        submittedAttachments = attachments
    }
    func unifiedToggleInputDidSubmitQuery(_ query: String) {}
    func unifiedToggleInputDidRequestVoiceSearch() {}
    func unifiedToggleInputDidRequestAIVoiceChat() {}
    func unifiedToggleInputDidRequestAIChat(prefilledText: String) {}
    func unifiedToggleInputDidChangeHeight() {}
    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {}
    func unifiedToggleInputDidRequestFire() {}
    func unifiedToggleInputDidRequestAppMenu() {}
    func unifiedToggleInputDidRequestAppMenuLongPress() {}
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
