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
import UIKit
import XCTest
@testable import DuckDuckGo

final class UTIAttachmentPolicyTests: XCTestCase {

    func test_remainingImagesInConversation_usesBackendTierLimit() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxImagesPerConversation: 10),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 6, filesUsed: 0, fileSizeBytesUsed: 0)
        )

        XCTAssertEqual(policy.remainingImagesInConversation, 4)
    }

    func test_remainingImagesForPicker_respectsPerTurnConversationAndPendingImages() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxImagesPerTurn: 3, maxImagesPerConversation: 10),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 8, filesUsed: 0, fileSizeBytesUsed: 0),
            pendingAttachments: [makeImage()]
        )

        XCTAssertEqual(policy.remainingImagesForPicker, 1)
    }

    func test_remainingImagesForPicker_isZeroWhenBackendLimitsAreMissing() {
        let policy = makePolicy(
            includeAttachmentLimits: false,
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 4, filesUsed: 0, fileSizeBytesUsed: 0)
        )

        XCTAssertEqual(policy.remainingImagesForPicker, 0)
        XCTAssertFalse(policy.canAttachImages)
    }

    func test_remainingImagesForPicker_ignoresPendingFiles() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxImagesPerTurn: 3, maxImagesPerConversation: 10),
            pendingAttachments: (0..<3).map { _ in makeFileAttachment() }
        )

        XCTAssertEqual(policy.remainingImagesForPicker, 3)
    }

    func test_canAttachFiles_falseWhenFileLimitReachedForTier() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 3),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 3, fileSizeBytesUsed: 0)
        )

        XCTAssertFalse(policy.canAttachFiles)
    }

    func test_canAttachFiles_trueWhenPaidTierHasRemainingFileSlots() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 5),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 3, fileSizeBytesUsed: 0)
        )

        XCTAssertTrue(policy.canAttachFiles)
    }

    func test_canAttachFiles_trueWhenPaidTierHasOnePendingSlotRemaining() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 5),
            pendingAttachments: (0..<4).map { _ in makeFileAttachment() }
        )

        XCTAssertTrue(policy.canAttachFiles)
    }

    func test_canAttachFiles_falseWhenPaidTierPendingFileLimitReached() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 5),
            pendingAttachments: (0..<5).map { _ in makeFileAttachment() }
        )

        XCTAssertFalse(policy.canAttachFiles)
    }

    func test_canAttachFiles_ignoresPendingImagesAtImageLimit() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 3, maxImagesPerTurn: 3),
            pendingAttachments: (0..<3).map { _ in makeImage() }
        )

        XCTAssertTrue(policy.canAttachFiles)
    }

    func test_canAttachFiles_ignoresInvalidFileAttachmentsForCapacity() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 1, maxTotalFileSizeBytes: 1_000),
            pendingAttachments: [makeInvalidFileAttachment(size: 2_000)]
        )

        XCTAssertTrue(policy.canAttachFiles)
    }

    func test_fileValidation_rejectsUnsupportedMimeType() {
        let policy = makePolicy()
        let file = makeFile(mimeType: "text/plain", pageCount: nil)

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentUnsupportedFileType(acceptedFileType: "PDF"))
    }

    func test_fileValidation_rejectsUnsupportedMimeTypeWithMultipleAcceptedTypes() {
        let policy = makePolicy(model: makeModel(supportedFileTypes: ["image/png", "image/jpeg", "application/pdf"]))
        let file = makeFile(mimeType: "text/plain", pageCount: nil)

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentUnsupportedFileType(acceptedFileTypes: ["PNG", "JPG", "PDF"]))
    }

    func test_fileValidation_whenModelDoesNotSupportFiles_returnsGenericUnsupportedMessage() {
        let policy = makePolicy(model: makeModel(supportedFileTypes: []))
        let file = makeFile(mimeType: "text/plain", pageCount: nil)

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentUnsupportedFileType)
    }

    func test_fileValidation_rejectsFileAboveMaxFileSize() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxFileSizeMB: 5))
        let file = makeFile(size: 5_242_881)

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: 5))
    }

    func test_fileMetadataValidation_rejectsFileAboveMaxFileSizeBeforeDataIsLoaded() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxFileSizeMB: 5))

        XCTAssertEqual(
            policy.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 5_242_881)?.message,
            UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: 5)
        )
    }

    func test_fileMetadataValidation_whenLimitsAreMissing_returnsUnavailableMessage() {
        let policy = makePolicy(includeAttachmentLimits: false)

        XCTAssertEqual(
            policy.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 100)?.message,
            UserText.aiChatAttachmentUnavailable
        )
    }

    func test_fileMetadataValidation_rejectsUnsupportedMimeTypeWithSingleAcceptedType() {
        let policy = makePolicy()

        XCTAssertEqual(
            policy.fileMetadataValidationError(mimeType: "text/plain", fileSizeBytes: 100)?.message,
            UserText.aiChatAttachmentUnsupportedFileType(acceptedFileType: "PDF")
        )
    }

    func test_fileMetadataValidation_rejectsUnsupportedMimeTypeWithMultipleAcceptedTypes() {
        let policy = makePolicy(model: makeModel(supportedFileTypes: ["image/png", "image/jpeg", "application/pdf"]))

        XCTAssertEqual(
            policy.fileMetadataValidationError(mimeType: "text/plain", fileSizeBytes: 100)?.message,
            UserText.aiChatAttachmentUnsupportedFileType(acceptedFileTypes: ["PNG", "JPG", "PDF"])
        )
    }

    func test_fileMetadataValidation_whenModelDoesNotSupportFiles_returnsGenericUnsupportedMessage() {
        let policy = makePolicy(model: makeModel(supportedFileTypes: []))

        XCTAssertEqual(
            policy.fileMetadataValidationError(mimeType: "text/plain", fileSizeBytes: 100)?.message,
            UserText.aiChatAttachmentUnsupportedFileType
        )
    }

    // MARK: - fileMetadataValidationError reason mapping

    func test_fileMetadataValidationError_whenModelDoesNotSupportFiles_returnsUnsupportedTypeReason() {
        let policy = makePolicy(model: makeModel(supportedFileTypes: []))

        XCTAssertEqual(policy.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 100)?.reason, .unsupportedType)
    }

    func test_fileMetadataValidationError_whenLimitsAreMissing_returnsOtherReason() {
        let policy = makePolicy(includeAttachmentLimits: false)

        XCTAssertEqual(policy.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 100)?.reason, .other)
    }

    func test_fileMetadataValidationError_whenMimeTypeNotSupported_returnsUnsupportedTypeReason() {
        let policy = makePolicy()

        XCTAssertEqual(policy.fileMetadataValidationError(mimeType: "text/plain", fileSizeBytes: 100)?.reason, .unsupportedType)
    }

    func test_fileMetadataValidationError_whenFileCountExceeded_returnsCountExceededReason() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 3),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 3, fileSizeBytesUsed: 0)
        )

        XCTAssertEqual(policy.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 100)?.reason, .countExceeded)
    }

    func test_fileMetadataValidationError_whenFileTooLarge_returnsSizeExceededReason() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxFileSizeMB: 5))

        XCTAssertEqual(policy.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 5_242_881)?.reason, .sizeExceeded)
    }

    func test_fileMetadataValidationError_whenMetadataIsValid_returnsNil() {
        let policy = makePolicy()

        XCTAssertNil(policy.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: nil))
    }

    func test_fileValidation_rejectsFileAboveRemainingTotalSize() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxTotalFileSizeBytes: 5_242_880),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 0, fileSizeBytesUsed: 5_242_400)
        )
        let file = makeFile(size: 600)

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentFilesExceedTotalSizeLimit(maxTotalFileSizeMB: 5))
    }

    func test_fileValidation_rejectsFileWhenConversationCountLimitReached() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 3),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 3, fileSizeBytesUsed: 0)
        )
        let file = makeFile()

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentFileCountLimit(maxFilesPerConversation: 3))
    }

    func test_fileValidation_rejectsFileWhenConversationCountLimitIsExceeded() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 3),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 4, fileSizeBytesUsed: 0)
        )
        let file = makeFile()

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentFileCountLimit(maxFilesPerConversation: 3))
    }

    func test_fileValidation_rejectsPdfAboveMaxPages() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxPagesPerFile: 15))
        let file = makeFile(pageCount: 16)

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 15))
    }

    func test_fileValidation_rejectsUnreadablePdfWhenPageLimitApplies() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxPagesPerFile: 15))
        let file = makeFile(pageCount: nil)

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentFileUnreadable)
    }

    func test_fileValidation_rejectsEncryptedPdfWithEncryptedMessageWhenPageLimitApplies() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxPagesPerFile: 15))
        let file = makeFile(pageCount: nil, isEncrypted: true)

        XCTAssertEqual(policy.fileValidationMessage(for: file), UserText.aiChatAttachmentFileEncrypted)
    }

    func test_fileValidation_allowsPdfAtMaxPages() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxPagesPerFile: 15))
        let file = makeFile(pageCount: 15)

        XCTAssertNil(policy.fileValidationMessage(for: file))
    }

    func test_promptValidation_allowsLongTextWithoutAttachments() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxInputCharsWithAttachments: 5))

        XCTAssertNil(policy.promptValidationMessage(for: "123456"))
    }

    func test_promptValidation_allowsTextAtAttachmentLimit() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxInputCharsWithAttachments: 5),
            pendingAttachments: [makeFileAttachment()]
        )

        XCTAssertNil(policy.promptValidationMessage(for: "12345"))
    }

    func test_promptValidation_rejectsTextAboveAttachmentLimit() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxInputCharsWithAttachments: 5),
            pendingAttachments: [makeFileAttachment()]
        )

        XCTAssertEqual(policy.promptValidationMessage(for: "123456"), UserText.aiChatAttachmentPromptTooLong)
    }

    func test_fileSubmissionValidation_allowsFilesAtConversationLimit() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 3),
            pendingAttachments: (0..<3).map { _ in makeFileAttachment() }
        )

        XCTAssertNil(policy.fileSubmissionValidationMessage())
    }

    func test_fileSubmissionValidation_rejectsFilesWhenUsageChangesBeforeSubmit() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 3),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 3, fileSizeBytesUsed: 0),
            pendingAttachments: [makeFileAttachment()]
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentFileCountLimit(maxFilesPerConversation: 3))
    }

    func test_fileSubmissionValidation_whenLimitsAreMissing_returnsUnavailableMessage() {
        let policy = makePolicy(
            includeAttachmentLimits: false,
            pendingAttachments: [makeFileAttachment()]
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentUnavailable)
    }

    func test_fileSubmissionValidation_rejectsUnsupportedPendingFileWithMultipleAcceptedTypes() {
        let policy = makePolicy(
            pendingAttachments: [makeFileAttachment(mimeType: "text/plain")],
            model: makeModel(supportedFileTypes: ["image/png", "image/jpeg", "application/pdf"])
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentUnsupportedFileType(acceptedFileTypes: ["PNG", "JPG", "PDF"]))
    }

    func test_fileSubmissionValidation_usesFallbackNameForUnknownAcceptedType() {
        let policy = makePolicy(
            pendingAttachments: [makeFileAttachment(mimeType: "text/plain")],
            model: makeModel(supportedFileTypes: ["text/csv"])
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentUnsupportedFileType(acceptedFileType: "CSV"))
    }

    func test_fileSubmissionValidation_rejectsUnsupportedPendingFileWithSingleAcceptedType() {
        let policy = makePolicy(
            pendingAttachments: [makeFileAttachment(mimeType: "text/plain")]
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentUnsupportedFileType(acceptedFileType: "PDF"))
    }

    func test_fileSubmissionValidation_whenModelDoesNotSupportFiles_returnsGenericUnsupportedMessage() {
        let policy = makePolicy(
            pendingAttachments: [makeFileAttachment()],
            model: makeModel(supportedFileTypes: [])
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentUnsupportedFileType)
    }

    func test_fileSubmissionValidation_rejectsInvalidFileAttachmentWithStoredMessage() {
        let validationMessage = UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 15)
        let policy = makePolicy(
            pendingAttachments: [
                .invalidFile(
                    UnifiedToggleInputInvalidFileAttachment(
                        fileName: "too-many-pages.pdf",
                        mimeType: "application/pdf",
                        fileSizeBytes: 1_000,
                        validationMessage: validationMessage
                    )
                )
            ]
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), validationMessage)
    }

    func test_fileSubmissionValidation_rejectsFileAboveMaxFileSize() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFileSizeMB: 5),
            pendingAttachments: [makeFileAttachment(size: 5_242_881)]
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: 5))
    }

    func test_fileSubmissionValidation_rejectsFilesAboveTotalSize() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxTotalFileSizeBytes: 5_242_880),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 0, fileSizeBytesUsed: 5_242_400),
            pendingAttachments: [makeFileAttachment(size: 600)]
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentFilesExceedTotalSizeLimit(maxTotalFileSizeMB: 5))
    }

    func test_fileSubmissionValidation_rejectsPdfAboveMaxPages() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxPagesPerFile: 15),
            pendingAttachments: [makeFileAttachment(pageCount: 16)]
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 15))
    }

    func test_fileSubmissionValidation_rejectsUnreadablePdfWhenPageLimitApplies() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxPagesPerFile: 15),
            pendingAttachments: [makeFileAttachment(pageCount: nil)]
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentFileUnreadable)
    }

    func test_fileSubmissionValidation_rejectsEncryptedPdfWhenPageLimitApplies() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxPagesPerFile: 15),
            pendingAttachments: [makeFileAttachment(pageCount: nil, isEncrypted: true)]
        )

        XCTAssertEqual(policy.fileSubmissionValidationMessage(), UserText.aiChatAttachmentFileEncrypted)
    }

    func test_imageSubmissionValidation_rejectsImagesWhenUsageChangesBeforeSubmit() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxImagesPerConversation: 5),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 5, filesUsed: 0, fileSizeBytesUsed: 0),
            pendingAttachments: [makeImage()]
        )

        XCTAssertEqual(policy.imageSubmissionValidationMessage(), UserText.aiChatAttachmentImageCountLimit(maxImagesPerConversation: 5))
    }

    func test_imageSubmissionValidation_whenLimitsAreMissing_returnsUnavailableMessage() {
        let policy = makePolicy(
            includeAttachmentLimits: false,
            pendingAttachments: [makeImage()]
        )

        XCTAssertEqual(policy.imageSubmissionValidationMessage(), UserText.aiChatAttachmentUnavailable)
    }

    func test_imageSubmissionValidation_rejectsImagesAbovePerTurnLimitWithPerTurnMessage() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxImagesPerTurn: 3, maxImagesPerConversation: 5),
            pendingAttachments: (0..<4).map { _ in makeImage() }
        )

        XCTAssertEqual(policy.imageSubmissionValidationMessage(), UserText.aiChatAttachmentImageTurnLimit(maxImagesPerTurn: 3))
    }

    // MARK: - fileValidationError reason mapping
    // These pin down the `reason` value used by the `m_aichat_unified_input_file_validation_failed` pixel.

    func test_fileValidationError_whenModelDoesNotSupportFiles_returnsUnsupportedTypeReason() {
        let policy = makePolicy(model: makeModel(supportedFileTypes: []))
        let file = makeFile(mimeType: "application/pdf")

        XCTAssertEqual(policy.fileValidationError(for: file)?.reason, .unsupportedType)
    }

    func test_fileValidationError_whenLimitsAreMissing_returnsOtherReason() {
        let policy = makePolicy(includeAttachmentLimits: false)
        let file = makeFile()

        XCTAssertEqual(policy.fileValidationError(for: file)?.reason, .other)
    }

    func test_fileValidationError_whenMimeTypeNotSupported_returnsUnsupportedTypeReason() {
        let policy = makePolicy()
        let file = makeFile(mimeType: "text/plain")

        XCTAssertEqual(policy.fileValidationError(for: file)?.reason, .unsupportedType)
    }

    func test_fileValidationError_whenFileCountExceeded_returnsCountExceededReason() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxFilesPerConversation: 3),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 3, fileSizeBytesUsed: 0)
        )
        let file = makeFile()

        XCTAssertEqual(policy.fileValidationError(for: file)?.reason, .countExceeded)
    }

    func test_fileValidationError_whenFileTooLarge_returnsSizeExceededReason() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxFileSizeMB: 5))
        let file = makeFile(size: 5_242_881)

        XCTAssertEqual(policy.fileValidationError(for: file)?.reason, .sizeExceeded)
    }

    func test_fileValidationError_whenTotalSizeExceeded_returnsSizeExceededReason() {
        let policy = makePolicy(
            attachmentLimits: makeLimits(maxTotalFileSizeBytes: 5_242_880),
            attachmentUsage: AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 0, fileSizeBytesUsed: 5_000_000)
        )
        let file = makeFile(size: 500_000)

        XCTAssertEqual(policy.fileValidationError(for: file)?.reason, .sizeExceeded)
    }

    func test_fileValidationError_whenPdfHasTooManyPages_returnsCountExceededReason() {
        let policy = makePolicy(attachmentLimits: makeLimits(maxPagesPerFile: 15))
        let file = makeFile(pageCount: 16)

        XCTAssertEqual(policy.fileValidationError(for: file)?.reason, .countExceeded)
    }

    func test_fileValidationError_whenPdfIsEncrypted_returnsEncryptedReason() {
        let policy = makePolicy()
        let file = makeFile(pageCount: nil, isEncrypted: true)

        XCTAssertEqual(policy.fileValidationError(for: file)?.reason, .encrypted)
    }

    func test_fileValidationError_whenPdfIsUnreadable_returnsUnreadableReason() {
        let policy = makePolicy()
        let file = makeFile(pageCount: nil, isEncrypted: false)

        XCTAssertEqual(policy.fileValidationError(for: file)?.reason, .unreadable)
    }

    func test_fileValidationError_whenFileIsValid_returnsNil() {
        let policy = makePolicy()
        let file = makeFile(pageCount: 1)

        XCTAssertNil(policy.fileValidationError(for: file))
    }

    private func makePolicy(
        attachmentLimits: AIChatAttachmentTierLimits? = nil,
        includeAttachmentLimits: Bool = true,
        attachmentUsage: AIChatAttachmentUsage? = nil,
        pendingAttachments: [UnifiedToggleInputAttachment] = [],
        model: AIChatModel? = nil
    ) -> UTIAttachmentPolicy {
        UTIAttachmentPolicy(
            attachmentLimits: includeAttachmentLimits ? (attachmentLimits ?? makeLimits()) : nil,
            attachmentUsage: attachmentUsage,
            pendingAttachments: pendingAttachments,
            model: model ?? makeModel()
        )
    }

    private func makeLimits(
        maxFilesPerConversation: Int = 3,
        maxFileSizeMB: Int = 5,
        maxTotalFileSizeBytes: Int = 5_242_880,
        maxPagesPerFile: Int = 15,
        maxImagesPerTurn: Int = 3,
        maxImagesPerConversation: Int = 5,
        maxInputCharsWithAttachments: Int = 4_500
    ) -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(
                maxPerConversation: maxFilesPerConversation,
                maxFileSizeMB: maxFileSizeMB,
                maxTotalFileSizeBytes: maxTotalFileSizeBytes,
                maxPagesPerFile: maxPagesPerFile
            ),
            images: AIChatAttachmentImageLimits(
                maxPerTurn: maxImagesPerTurn,
                maxPerConversation: maxImagesPerConversation,
                maxInputCharsWithAttachments: maxInputCharsWithAttachments
            )
        )
    }

    private func makeModel(
        supportsImageUpload: Bool = true,
        supportedFileTypes: [String] = ["application/pdf"]
    ) -> AIChatModel {
        AIChatModel(
            id: "model",
            name: "Model",
            provider: .unknown,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: supportedFileTypes,
            entityHasAccess: true
        )
    }

    private func makeFileAttachment(
        size: Int = 1_000,
        mimeType: String = "application/pdf",
        pageCount: Int? = 1,
        isEncrypted: Bool = false
    ) -> UnifiedToggleInputAttachment {
        .file(
            AIChatFileAttachment(
                data: Data(repeating: 0, count: size),
                fileName: "test.pdf",
                mimeType: mimeType,
                fileSizeBytes: size,
                pageCount: pageCount,
                isEncrypted: isEncrypted
            )
        )
    }

    private func makeFile(
        size: Int = 1_000,
        mimeType: String = "application/pdf",
        pageCount: Int? = 1,
        isEncrypted: Bool = false
    ) -> AIChatFileAttachment {
        AIChatFileAttachment(
            data: Data(repeating: 0, count: size),
            fileName: "test.pdf",
            mimeType: mimeType,
            fileSizeBytes: size,
            pageCount: pageCount,
            isEncrypted: isEncrypted
        )
    }

    private func makeImage() -> UnifiedToggleInputAttachment {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        return .image(AIChatImageAttachment(image: image, fileName: "image.png"))
    }

    private func makeInvalidFileAttachment(
        size: Int = 1_000,
        mimeType: String = "application/pdf",
        validationMessage: String = UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 15)
    ) -> UnifiedToggleInputAttachment {
        .invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                fileName: "invalid.pdf",
                mimeType: mimeType,
                fileSizeBytes: size,
                validationMessage: validationMessage
            )
        )
    }
}
