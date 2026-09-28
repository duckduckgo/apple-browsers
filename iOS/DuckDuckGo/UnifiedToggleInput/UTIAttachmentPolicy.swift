//
//  UTIAttachmentPolicy.swift
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
import Foundation
import UniformTypeIdentifiers

/// iOS adapter over the shared `AIChatAttachmentValidator`. Keeps the UIKit-bound
/// `UnifiedToggleInputAttachment` representation and injects iOS `UserText` strings; the limit
/// arithmetic itself lives in the shared validator so iOS and macOS stay in lockstep.
struct UTIAttachmentPolicy {

    typealias FileValidationFailureReason = AIChatAttachmentValidator.FileValidationFailureReason
    typealias FileValidationError = AIChatAttachmentValidator.FileValidationError

    let attachmentLimits: AIChatAttachmentTierLimits?
    let attachmentUsage: AIChatAttachmentUsage?
    let pendingAttachments: [UnifiedToggleInputAttachment]
    let model: AIChatModel?

    private var validator: AIChatAttachmentValidator {
        AIChatAttachmentValidator(
            limits: attachmentLimits,
            model: model,
            usage: AIChatAttachmentUsageSnapshot(
                imagesUsed: attachmentUsage?.imagesUsed ?? 0,
                filesUsed: attachmentUsage?.filesUsed ?? 0,
                fileSizeBytesUsed: attachmentUsage?.fileSizeBytesUsed ?? 0
            ),
            pendingImageCount: pendingAttachments.filter(\.isImage).count,
            pendingFiles: pendingAttachments.compactMap(\.fileAttachment).map(AIChatAttachmentValidator.FileDescriptor.init),
            messages: Self.messages
        )
    }

    var remainingImagesInConversation: Int {
        validator.remainingImagesInConversation
    }

    var remainingImagesForPicker: Int {
        validator.remainingImagesForPicker
    }

    var isConversationImageLimitReached: Bool {
        validator.isConversationImageLimitReached
    }

    var canAttachImages: Bool {
        validator.canAttachImages
    }

    var canAttachFiles: Bool {
        validator.canAttachFiles
    }

    var remainingFileSizeBytes: Int {
        validator.remainingFileSizeBytes
    }

    var remainingFilesInConversation: Int {
        validator.remainingFilesInConversation
    }

    func fileValidationMessage(for attachment: AIChatFileAttachment) -> String? {
        validator.fileValidationMessage(for: .init(attachment))
    }

    func fileValidationError(for attachment: AIChatFileAttachment) -> FileValidationError? {
        validator.fileValidationError(for: .init(attachment))
    }

    func fileMetadataValidationError(mimeType: String, fileSizeBytes: Int?) -> FileValidationError? {
        validator.fileMetadataValidationError(mimeType: mimeType, fileSizeBytes: fileSizeBytes)
    }

    func canAttachFile(_ attachment: AIChatFileAttachment) -> Bool {
        validator.canAttachFile(.init(attachment))
    }

    func fileSubmissionValidationMessage() -> String? {
        // Invalid attachments are an iOS UI concept (a file was attached then flagged invalid), so
        // this pre-check stays in the adapter; the shared validator only sees valid file descriptors.
        if let invalidAttachment = pendingAttachments.first(where: \.isInvalid) {
            return invalidAttachment.validationMessage
        }
        return validator.fileSubmissionValidationMessage()
    }

    func imageSubmissionValidationMessage() -> String? {
        validator.imageSubmissionValidationMessage()
    }

    func imageCapacityValidationMessage() -> String? {
        validator.imageCapacityValidationMessage()
    }

    func isAttachmentSupported(_ attachment: UnifiedToggleInputAttachment) -> Bool {
        switch attachment {
        case .image:
            return model?.supportsImageUpload == true
        case .file(let fileAttachment):
            return model?.supportedFileTypes.contains(fileAttachment.mimeType) == true
        case .invalidFile(let fileAttachment):
            return model?.supportedFileTypes.contains(fileAttachment.mimeType) == true
        }
    }

    func promptValidationMessage(for text: String) -> String? {
        validator.promptValidationMessage(for: text)
    }
}

private extension UTIAttachmentPolicy {

    static let messages = AIChatAttachmentValidator.Messages(
        unsupportedFileType: UserText.aiChatAttachmentUnsupportedFileType,
        unavailable: UserText.aiChatAttachmentUnavailable,
        fileEncrypted: UserText.aiChatAttachmentFileEncrypted,
        fileUnreadable: UserText.aiChatAttachmentFileUnreadable,
        promptTooLong: UserText.aiChatAttachmentPromptTooLong,
        unsupportedFileTypeWithAccepted: { UserText.aiChatAttachmentUnsupportedFileType(acceptedFileTypes: $0) },
        fileCountLimit: { UserText.aiChatAttachmentFileCountLimit(maxFilesPerConversation: $0) },
        fileTooLarge: { UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: $0) },
        filesExceedTotalSizeLimit: { UserText.aiChatAttachmentFilesExceedTotalSizeLimit(maxTotalFileSizeMB: $0) },
        fileTooManyPages: { UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: $0) },
        imageTurnLimit: { UserText.aiChatAttachmentImageTurnLimit(maxImagesPerTurn: $0) },
        imageCountLimit: { UserText.aiChatAttachmentImageCountLimit(maxImagesPerConversation: $0) }
    )
}
