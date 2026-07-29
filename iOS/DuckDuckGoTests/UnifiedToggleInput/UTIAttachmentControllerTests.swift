//
//  UTIAttachmentControllerTests.swift
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
import Core
import UIKit
import XCTest
@testable import DuckDuckGo

/// Isolated unit tests for `UTIAttachmentController` — exercises the controller directly through
/// stub `ViewSurface` / `Environment` / `Callbacks`, without a live coordinator. Coordinator-level
/// wiring + policy construction stay covered by `UnifiedToggleInputCoordinatorAttachmentLimitsTests`.
@MainActor
final class UTIAttachmentControllerTests: XCTestCase {

    private var view: FakeAttachmentView!
    private var config: FakeEnvironmentConfig!
    private var callbackSpy: CallbackSpy!

    override func setUp() {
        super.setUp()
        PixelFiringMock.tearDown()
        view = FakeAttachmentView()
        config = FakeEnvironmentConfig()
        callbackSpy = CallbackSpy()
    }

    override func tearDown() {
        PixelFiringMock.tearDown()
        view = nil
        config = nil
        callbackSpy = nil
        super.tearDown()
    }

    // MARK: - Images

    func testAddImageAttachment_whenModelSupportsImages_addsImageAndPersists() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()

        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")

        XCTAssertEqual(view.attachments.count, 1)
        XCTAssertTrue(view.attachments.first?.isImage == true)
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 1)
    }

    func testAddImageAttachment_whenModelDoesNotSupportImages_isNoOp() {
        config.model = makeModel(supportsImageUpload: false)
        config.limits = makeLimits()
        let sut = makeController()

        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")

        XCTAssertTrue(view.attachments.isEmpty)
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 0)
    }

    // MARK: - Files

    func testAddValidFileAttachment_addsFileAndFiresAttachedPixel() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: ["application/pdf"])
        config.limits = makeLimits()
        let sut = makeController()

        sut.addFileAttachment(makeFileAttachment())

        XCTAssertEqual(view.attachments.count, 1)
        XCTAssertFalse(view.attachments.first?.isInvalid == true)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputFileAttached.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params?["source"], "file_picker")
    }

    func testAddInvalidFileAttachment_addsInvalidChipShowsErrorAndFiresValidationPixel() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: ["application/pdf"])
        config.limits = makeLimits()
        let sut = makeController()

        sut.addFileAttachment(makeFileAttachment(pageCount: 9)) // exceeds maxPagesPerFile (8)

        XCTAssertEqual(view.attachments.count, 1)
        XCTAssertTrue(view.attachments.first?.isInvalid == true)
        XCTAssertNotNil(view.validationMessage)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputFileValidationFailed.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params?["source"], "file_picker")
    }

    // MARK: - Remove / clear

    func testRemoveAttachment_removesFromViewAndPersists() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()
        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")
        let id = view.attachments.first!.id
        callbackSpy.onDraftChangedCount = 0

        sut.removeAttachment(id: id)

        XCTAssertTrue(view.attachments.isEmpty)
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 1)
    }

    func testClearAttachments_removesAllAndClearsValidation() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()
        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")
        sut.addImageAttachment(image: UIImage(), fileName: "b.jpg")
        view.validationMessage = "stale error"

        sut.clearAttachments()

        XCTAssertTrue(view.attachments.isEmpty)
        XCTAssertNil(view.validationMessage)
    }

    // MARK: - Paste rejection banner

    func testReportRejectedPaste_showsTransientBannerAndFiresValidationPixelWithPasteSource() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: ["application/pdf"])
        config.limits = makeLimits()
        let sut = makeController()

        sut.reportRejectedPaste(reason: .fileTooLarge)

        XCTAssertEqual(view.validationMessage, UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: 5))
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.unifiedToggleInputFileValidationFailed.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params?["reason"], "size_exceeded")
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.params?["source"], "paste")
    }

    func testTransientBanner_survivesValidationResyncWithNoInvalidAttachments() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: ["application/pdf"])
        config.limits = makeLimits()
        config.inputMode = .aiChat
        let sut = makeController()

        sut.reportRejectedPaste(reason: .fileTooLarge)
        XCTAssertNotNil(view.validationMessage)

        // A re-sync with no attachment-derived error must fall back to the transient banner, not clear it.
        sut.syncValidationErrorForCurrentMode()

        XCTAssertNotNil(view.validationMessage)
    }

    // MARK: - Attach button presentation

    func testUpdateAttachButtonPresentation_hidesButtonWhenNoAttachmentSupport() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: [])
        config.limits = makeLimits()
        let sut = makeController()

        sut.updateAttachButtonPresentation()

        XCTAssertTrue(view.imageButtonHidden)
    }

    func testUpdateAttachButtonPresentation_disablesButtonWhileGenerating() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        view.isGenerating = true
        let sut = makeController()

        sut.updateAttachButtonPresentation()

        XCTAssertFalse(view.imageButtonHidden)
        XCTAssertFalse(view.imageButtonEnabled)
    }

    // MARK: - Unsupported-attachment pruning

    func testRemoveUnsupportedAttachmentsForSelectedModel_removesImageWhenModelLosesImageSupport() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()
        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")
        XCTAssertEqual(view.attachments.count, 1)

        config.model = makeModel(supportsImageUpload: false)
        sut.removeUnsupportedAttachmentsForSelectedModel()

        XCTAssertTrue(view.attachments.isEmpty)
    }

    // MARK: - Submission validation

    func testSubmissionValidationMessage_inSearchMode_returnsNil() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()

        XCTAssertNil(sut.submissionValidationMessage(for: "hello", mode: .search))
    }

    // MARK: - Helpers

    private func makeController() -> UTIAttachmentController {
        let view = self.view!
        let config = self.config!
        return UTIAttachmentController(
            pixelReporter: UTIPixelReporter(
                firing: UTIPixelFiring(pixel: PixelFiringMock.self, daily: PixelFiringMock.self),
                context: { UTIPixelContext(surface: .addressBar, isDuckAISurfaceForAttribution: false, inputMode: .aiChat) }
            ),
            view: view.surface,
            environment: .init(
                policy: {
                    UTIAttachmentPolicy(
                        attachmentLimits: config.limits,
                        attachmentUsage: config.usage,
                        pendingAttachments: view.attachments,
                        model: config.model
                    )
                },
                inputMode: { config.inputMode },
                pixelSurface: { .addressBar },
                isContextualChatState: { config.isContextualChatState },
                supportsImageUpload: { config.model?.supportsImageUpload ?? false },
                supportedFileTypes: { config.model?.supportedFileTypes ?? [] },
                hasSelectedModel: { config.model != nil },
                attachmentLimits: { config.limits },
                currentTabUID: { "tab-1" },
                isPageContextAttachable: { nil },
                pageContextAttachHandler: { nil },
                presenterViewController: { nil }
            ),
            callbacks: callbackSpy.callbacks
        )
    }

    private func makeModel(supportsImageUpload: Bool, supportedFileTypes: [String] = []) -> AIChatModel {
        AIChatModel(id: "m", name: "m", provider: .unknown, supportsImageUpload: supportsImageUpload, supportedFileTypes: supportedFileTypes, entityHasAccess: true)
    }

    private func makeLimits() -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 8),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: 4500)
        )
    }

    private func makeFileAttachment(fileName: String = "test.pdf", pageCount: Int? = 1) -> AIChatFileAttachment {
        let data = Data(repeating: 0, count: 1_000)
        return AIChatFileAttachment(data: data, fileName: fileName, mimeType: "application/pdf", fileSizeBytes: data.count, pageCount: pageCount)
    }
}

@MainActor
private final class FakeAttachmentView {
    var attachments: [UnifiedToggleInputAttachment] = []
    var isGenerating = false
    var validationMessage: String?
    var imageButtonHidden = false
    var imageButtonEnabled = true
    var attachmentMenu: UIMenu?

    var surface: UTIAttachmentController.ViewSurface {
        .init(
            currentAttachments: { self.attachments },
            isGenerating: { self.isGenerating },
            addAttachment: { self.attachments.append($0) },
            removeAttachment: { id in self.attachments.removeAll { $0.id == id } },
            removeAllAttachments: { self.attachments.removeAll() },
            replaceAttachment: { id, attachment in
                guard let index = self.attachments.firstIndex(where: { $0.id == id }) else { return }
                self.attachments[index] = attachment
            },
            showValidationError: { self.validationMessage = $0 },
            clearValidationError: { self.validationMessage = nil },
            setImageButtonHidden: { self.imageButtonHidden = $0 },
            setImageButtonEnabled: { self.imageButtonEnabled = $0 },
            setAttachmentMenu: { self.attachmentMenu = $0 }
        )
    }
}

@MainActor
private final class FakeEnvironmentConfig {
    var model: AIChatModel?
    var limits: AIChatAttachmentTierLimits?
    var usage: AIChatAttachmentUsage?
    var inputMode: TextEntryMode = .aiChat
    var isContextualChatState = false
}

@MainActor
private final class CallbackSpy {
    var onDraftChangedCount = 0
    var onExpandIfNeededCount = 0
    var updateFloatingReturnKeyCount = 0

    var callbacks: UTIAttachmentController.Callbacks {
        .init(
            onDraftChanged: { self.onDraftChangedCount += 1 },
            onExpandIfNeeded: { self.onExpandIfNeededCount += 1 },
            updateFloatingReturnKey: { self.updateFloatingReturnKeyCount += 1 }
        )
    }
}
