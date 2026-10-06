//
//  AIChatAttachmentValidatorTests.swift
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

import Foundation
import XCTest
@testable import AIChat

final class AIChatAttachmentValidatorTests: XCTestCase {

    // MARK: - File metadata: type / count / size

    func testWhenModelDoesNotSupportFiles_ThenUnsupportedTypeError() {
        let validator = makeValidator(model: makeModel(supportedFileTypes: []))
        let error = validator.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 100)
        XCTAssertEqual(error?.reason, .unsupportedType)
        XCTAssertEqual(error?.message, "unsupported")
    }

    func testWhenMimeTypeNotInSupportedTypes_ThenUnsupportedTypeWithAcceptedError() {
        let validator = makeValidator(model: makeModel(supportedFileTypes: ["application/pdf"]))
        let error = validator.fileMetadataValidationError(mimeType: "text/plain", fileSizeBytes: 100)
        XCTAssertEqual(error?.reason, .unsupportedType)
        XCTAssertEqual(error?.message, "unsupported:PDF")
    }

    func testWhenLimitsAreNil_ThenUnavailableError() {
        let validator = makeValidator(includeLimits: false)
        let error = validator.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 100)
        XCTAssertEqual(error?.reason, .other)
        XCTAssertEqual(error?.message, "unavailable")
    }

    func testWhenFileExceedsPerFileSize_ThenTooLargeError() {
        let validator = makeValidator(limits: makeLimits(maxFileSizeMB: 1))
        let error = validator.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 2 * 1_048_576)
        XCTAssertEqual(error?.reason, .sizeExceeded)
        XCTAssertEqual(error?.message, "tooLarge:1")
    }

    func testWhenFilesExceedTotalSize_ThenTotalSizeError() {
        // Per-file limit high enough that only the cumulative total trips. Total = 4 MB; one 3 MB
        // file already pending leaves < 2 MB; a 2 MB pick exceeds the remaining budget.
        let limits = makeLimits(maxFileSizeMB: 10, maxTotalFileSizeBytes: 4 * 1_048_576)
        let pending = [AIChatAttachmentValidator.FileDescriptor(mimeType: "application/pdf", fileSizeBytes: 3 * 1_048_576, pageCount: 1)]
        let validator = makeValidator(limits: limits, pendingFiles: pending)
        let error = validator.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 2 * 1_048_576)
        XCTAssertEqual(error?.reason, .sizeExceeded)
        XCTAssertEqual(error?.message, "totalSize:4")
    }

    func testWhenFileCountAtLimit_ThenCountError() {
        let limits = makeLimits(maxFilesPerConversation: 2)
        let pending = [
            AIChatAttachmentValidator.FileDescriptor(mimeType: "application/pdf", fileSizeBytes: 10, pageCount: 1),
            AIChatAttachmentValidator.FileDescriptor(mimeType: "application/pdf", fileSizeBytes: 10, pageCount: 1)
        ]
        let validator = makeValidator(limits: limits, pendingFiles: pending)
        let error = validator.fileMetadataValidationError(mimeType: "application/pdf", fileSizeBytes: 10)
        XCTAssertEqual(error?.reason, .countExceeded)
        XCTAssertEqual(error?.message, "fileCount:2")
    }

    func testRemainingFilesInConversation_BoundedByUsageAndPending() {
        let pending = [AIChatAttachmentValidator.FileDescriptor(mimeType: "application/pdf", fileSizeBytes: 10, pageCount: 1)]
        let validator = makeValidator(
            limits: makeLimits(maxFilesPerConversation: 3),
            usage: .init(filesUsed: 1),
            pendingFiles: pending
        )
        XCTAssertEqual(validator.remainingFilesInConversation, 1)
    }

    // MARK: - Page validation

    func testWhenPDFUnderPageLimit_ThenValid() {
        let validator = makeValidator(limits: makeLimits(maxPagesPerFile: 15))
        let file = AIChatAttachmentValidator.FileDescriptor(mimeType: "application/pdf", fileSizeBytes: 10, pageCount: 10)
        XCTAssertNil(validator.fileValidationError(for: file))
    }

    func testWhenPDFOverPageLimit_ThenTooManyPagesError() {
        let validator = makeValidator(limits: makeLimits(maxPagesPerFile: 15))
        let file = AIChatAttachmentValidator.FileDescriptor(mimeType: "application/pdf", fileSizeBytes: 10, pageCount: 20)
        let error = validator.fileValidationError(for: file)
        XCTAssertEqual(error?.reason, .countExceeded)
        XCTAssertEqual(error?.message, "tooManyPages:15")
    }

    func testWhenPDFPageCountNilAndEncrypted_ThenEncryptedError() {
        let validator = makeValidator()
        let file = AIChatAttachmentValidator.FileDescriptor(mimeType: "application/pdf", fileSizeBytes: 10, pageCount: nil, isEncrypted: true)
        let error = validator.fileValidationError(for: file)
        XCTAssertEqual(error?.reason, .encrypted)
        XCTAssertEqual(error?.message, "encrypted")
    }

    func testWhenPDFPageCountNilAndNotEncrypted_ThenUnreadableError() {
        let validator = makeValidator()
        let file = AIChatAttachmentValidator.FileDescriptor(mimeType: "application/pdf", fileSizeBytes: 10, pageCount: nil, isEncrypted: false)
        let error = validator.fileValidationError(for: file)
        XCTAssertEqual(error?.reason, .unreadable)
        XCTAssertEqual(error?.message, "unreadable")
    }

    func testWhenNonPDF_ThenPageValidationSkipped() {
        let validator = makeValidator(model: makeModel(supportedFileTypes: ["image/png"]))
        let file = AIChatAttachmentValidator.FileDescriptor(mimeType: "image/png", fileSizeBytes: 10, pageCount: nil)
        XCTAssertNil(validator.fileValidationError(for: file))
    }

    // MARK: - Images

    func testRemainingImagesForPicker_BoundedByPerTurn() {
        // perTurn 3, perConversation 10, usage 0 -> min is 3.
        let validator = makeValidator(limits: makeLimits(maxImagesPerTurn: 3, maxImagesPerConversation: 10))
        XCTAssertEqual(validator.remainingImagesForPicker, 3)
    }

    func testRemainingImagesForPicker_BoundedByConversationUsage() {
        let validator = makeValidator(
            limits: makeLimits(maxImagesPerTurn: 3, maxImagesPerConversation: 5),
            usage: .init(imagesUsed: 4)
        )
        XCTAssertEqual(validator.remainingImagesForPicker, 1)
    }

    func testImageSubmission_OverPerTurn_ThenTurnLimitError() {
        let validator = makeValidator(limits: makeLimits(maxImagesPerTurn: 3, maxImagesPerConversation: 10), pendingImageCount: 4)
        XCTAssertEqual(validator.imageSubmissionValidationMessage(), "imageTurn:3")
    }

    func testImageSubmission_OverConversation_ThenCountLimitError() {
        let validator = makeValidator(
            limits: makeLimits(maxImagesPerTurn: 5, maxImagesPerConversation: 5),
            usage: .init(imagesUsed: 4),
            pendingImageCount: 2
        )
        XCTAssertEqual(validator.imageSubmissionValidationMessage(), "imageCount:5")
    }

    func testImageSubmission_WithinLimits_ThenNil() {
        let validator = makeValidator(limits: makeLimits(maxImagesPerTurn: 3, maxImagesPerConversation: 5), pendingImageCount: 2)
        XCTAssertNil(validator.imageSubmissionValidationMessage())
    }

    func testImageCapacity_WithHeadroom_ThenNil() {
        let validator = makeValidator(limits: makeLimits(maxImagesPerTurn: 3, maxImagesPerConversation: 10), pendingImageCount: 1)
        XCTAssertNil(validator.imageCapacityValidationMessage())
    }

    func testImageCapacity_PerTurnExhaustedButConversationHasRoom_ThenTurnLimit() {
        let validator = makeValidator(limits: makeLimits(maxImagesPerTurn: 3, maxImagesPerConversation: 10), pendingImageCount: 3)
        XCTAssertEqual(validator.imageCapacityValidationMessage(), "imageTurn:3")
    }

    func testImageCapacity_ConversationExhausted_ThenCountLimit() {
        let validator = makeValidator(
            limits: makeLimits(maxImagesPerTurn: 5, maxImagesPerConversation: 5),
            usage: .init(imagesUsed: 4),
            pendingImageCount: 1
        )
        XCTAssertEqual(validator.imageCapacityValidationMessage(), "imageCount:5")
    }

    func testImageCapacity_ModelWithoutImageSupport_ThenUnavailable() {
        let validator = makeValidator(model: makeModel(supportsImageUpload: false))
        XCTAssertEqual(validator.imageCapacityValidationMessage(), "unavailable")
    }

    // MARK: - Prompt length

    func testPrompt_LongTextWithoutAttachments_ThenNil() {
        let validator = makeValidator(limits: makeLimits(maxInputChars: 5))
        XCTAssertNil(validator.promptValidationMessage(for: "123456"))
    }

    func testPrompt_AtLimitWithAttachment_ThenNil() {
        let validator = makeValidator(limits: makeLimits(maxInputChars: 5), pendingImageCount: 1)
        XCTAssertNil(validator.promptValidationMessage(for: "12345"))
    }

    func testPrompt_OverLimitWithAttachment_ThenTooLong() {
        let validator = makeValidator(limits: makeLimits(maxInputChars: 5), pendingImageCount: 1)
        XCTAssertEqual(validator.promptValidationMessage(for: "123456"), "promptTooLong")
    }

    // MARK: - Tier selection

    func testTierSelection() {
        let limits = AIChatAttachmentLimits(
            free: tierLimits(tag: 1),
            plus: tierLimits(tag: 5),
            pro: tierLimits(tag: 9)
        )
        XCTAssertEqual(limits.limits(for: .free).files.maxPerConversation, 1)
        XCTAssertEqual(limits.limits(for: .plus).files.maxPerConversation, 5)
        XCTAssertEqual(limits.limits(for: .pro).files.maxPerConversation, 9)
        XCTAssertEqual(limits.limits(for: .internal).files.maxPerConversation, 9)
    }

    // MARK: - Valid file

    func testValidFile_ThenNil() {
        let validator = makeValidator()
        let file = AIChatAttachmentValidator.FileDescriptor(mimeType: "application/pdf", fileSizeBytes: 100, pageCount: 1)
        XCTAssertNil(validator.fileValidationError(for: file))
    }

    // MARK: - Helpers

    private func makeValidator(
        limits: AIChatAttachmentTierLimits? = nil,
        includeLimits: Bool = true,
        model: AIChatModel? = nil,
        usage: AIChatAttachmentUsageSnapshot = .zero,
        pendingImageCount: Int = 0,
        pendingFiles: [AIChatAttachmentValidator.FileDescriptor] = []
    ) -> AIChatAttachmentValidator {
        AIChatAttachmentValidator(
            limits: includeLimits ? (limits ?? makeLimits()) : nil,
            model: model ?? makeModel(),
            usage: usage,
            pendingImageCount: pendingImageCount,
            pendingFiles: pendingFiles,
            messages: Self.testMessages
        )
    }

    private func makeModel(supportsImageUpload: Bool = true, supportedFileTypes: [String] = ["application/pdf"]) -> AIChatModel {
        AIChatModel(
            id: "model",
            name: "Model",
            provider: .openAI,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: supportedFileTypes,
            entityHasAccess: true
        )
    }

    private func makeLimits(
        maxFilesPerConversation: Int = 3,
        maxFileSizeMB: Int = 5,
        maxTotalFileSizeBytes: Int = 5_242_880,
        maxPagesPerFile: Int = 15,
        maxImagesPerTurn: Int = 3,
        maxImagesPerConversation: Int = 5,
        maxInputChars: Int = 4_500
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
                maxInputCharsWithAttachments: maxInputChars
            )
        )
    }

    private func tierLimits(tag: Int) -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: tag, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 15),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: 4_500)
        )
    }

    private static let testMessages = AIChatAttachmentValidator.Messages(
        unsupportedFileType: "unsupported",
        unavailable: "unavailable",
        fileEncrypted: "encrypted",
        fileUnreadable: "unreadable",
        promptTooLong: "promptTooLong",
        unsupportedFileTypeWithAccepted: { "unsupported:\($0.joined(separator: ","))" },
        fileCountLimit: { "fileCount:\($0)" },
        fileTooLarge: { "tooLarge:\($0)" },
        filesExceedTotalSizeLimit: { "totalSize:\($0)" },
        fileTooManyPages: { "tooManyPages:\($0)" },
        imageTurnLimit: { "imageTurn:\($0)" },
        imageCountLimit: { "imageCount:\($0)" }
    )
}
