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

struct UTIAttachmentPolicy {

    enum FileValidationFailureReason: String {
        case sizeExceeded = "size_exceeded"
        case countExceeded = "count_exceeded"
        case unsupportedType = "unsupported_type"
        case other
        case encrypted
        case unreadable
    }

    struct FileValidationError {
        let reason: FileValidationFailureReason
        let message: String
    }

    let attachmentLimits: AIChatAttachmentTierLimits?
    let attachmentUsage: AIChatAttachmentUsage?
    let pendingAttachments: [UnifiedToggleInputAttachment]
    let model: AIChatModel?

    var remainingImagesInConversation: Int {
        guard let maxImagesPerConversation else { return 0 }
        let conversationUsed = attachmentUsage?.imagesUsed ?? 0
        return max(0, maxImagesPerConversation - conversationUsed)
    }

    var remainingImagesForPicker: Int {
        guard let maxImagesPerTurn else { return 0 }
        let perTurnRemaining = max(0, maxImagesPerTurn - pendingImageCount)
        let conversationRemaining = max(0, remainingImagesInConversation - pendingImageCount)
        return max(0, min(perTurnRemaining, conversationRemaining))
    }

    var isConversationImageLimitReached: Bool {
        remainingImagesInConversation == 0
    }

    var canAttachImages: Bool {
        model?.supportsImageUpload == true && remainingImagesForPicker > 0
    }

    var canAttachFiles: Bool {
        guard model?.supportsFileUpload == true,
              let maxFilesPerConversation,
              let maxTotalFileSizeBytes else {
            return false
        }

        let filesUsed = attachmentUsage?.filesUsed ?? 0
        let fileBytesUsed = attachmentUsage?.fileSizeBytesUsed ?? 0
        let remainingConversationSlots = maxFilesPerConversation - filesUsed - pendingFileCount
        let remainingBytes = maxTotalFileSizeBytes - fileBytesUsed - pendingFileSizeBytes

        return remainingConversationSlots > 0 && remainingBytes > 0
    }

    var remainingFileSizeBytes: Int {
        guard let maxTotalFileSizeBytes else { return 0 }
        let fileBytesUsed = attachmentUsage?.fileSizeBytesUsed ?? 0
        return max(0, maxTotalFileSizeBytes - fileBytesUsed - pendingFileSizeBytes)
    }

    func fileValidationMessage(for attachment: AIChatFileAttachment) -> String? {
        fileValidationError(for: attachment)?.message
    }

    func fileValidationError(for attachment: AIChatFileAttachment) -> FileValidationError? {
        if let metadataError = fileMetadataValidationError(mimeType: attachment.mimeType, fileSizeBytes: attachment.fileSizeBytes) {
            return metadataError
        }
        return pageValidationError(for: attachment)
    }

    func fileMetadataValidationError(mimeType: String, fileSizeBytes: Int?) -> FileValidationError? {
        guard model?.supportsFileUpload == true else {
            return FileValidationError(reason: .unsupportedType, message: UserText.aiChatAttachmentUnsupportedFileType)
        }

        guard let maxFilesPerConversation,
              let maxFileSizeMB,
              let maxFileSizeBytes,
              let maxTotalFileSizeBytes,
              let maxTotalFileSizeMB else {
            return FileValidationError(reason: .other, message: UserText.aiChatAttachmentUnavailable)
        }

        guard model?.supportedFileTypes.contains(mimeType) == true else {
            return FileValidationError(
                reason: .unsupportedType,
                message: UserText.aiChatAttachmentUnsupportedFileType(acceptedFileTypes: acceptedFileTypeNames)
            )
        }

        let filesUsed = attachmentUsage?.filesUsed ?? 0
        let fileBytesUsed = attachmentUsage?.fileSizeBytesUsed ?? 0
        let remainingConversationSlots = maxFilesPerConversation - filesUsed - pendingFileCount
        let remainingBytes = maxTotalFileSizeBytes - fileBytesUsed - pendingFileSizeBytes

        if remainingConversationSlots <= 0 {
            return FileValidationError(
                reason: .countExceeded,
                message: UserText.aiChatAttachmentFileCountLimit(maxFilesPerConversation: maxFilesPerConversation)
            )
        }

        if let fileSizeBytes {
            if fileSizeBytes > maxFileSizeBytes {
                return FileValidationError(
                    reason: .sizeExceeded,
                    message: UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: maxFileSizeMB)
                )
            }

            if fileSizeBytes > remainingBytes {
                return FileValidationError(
                    reason: .sizeExceeded,
                    message: UserText.aiChatAttachmentFilesExceedTotalSizeLimit(maxTotalFileSizeMB: maxTotalFileSizeMB)
                )
            }
        }

        return nil
    }

    func canAttachFile(_ attachment: AIChatFileAttachment) -> Bool {
        fileValidationMessage(for: attachment) == nil
    }

    func fileSubmissionValidationMessage() -> String? {
        if let invalidAttachment = pendingAttachments.first(where: \.isInvalid) {
            return invalidAttachment.validationMessage
        }

        let pendingFiles = pendingAttachments.compactMap(\.fileAttachment)
        guard !pendingFiles.isEmpty else { return nil }
        guard model?.supportsFileUpload == true else {
            return UserText.aiChatAttachmentUnsupportedFileType
        }

        guard let maxFilesPerConversation,
              let maxFileSizeMB,
              let maxFileSizeBytes,
              let maxTotalFileSizeBytes,
              let maxTotalFileSizeMB else {
            return UserText.aiChatAttachmentUnavailable
        }

        if pendingFiles.contains(where: { model?.supportedFileTypes.contains($0.mimeType) != true }) {
            return UserText.aiChatAttachmentUnsupportedFileType(acceptedFileTypes: acceptedFileTypeNames)
        }

        let filesUsed = attachmentUsage?.filesUsed ?? 0
        if filesUsed + pendingFileCount > maxFilesPerConversation {
            return UserText.aiChatAttachmentFileCountLimit(maxFilesPerConversation: maxFilesPerConversation)
        }

        if pendingFiles.contains(where: { $0.fileSizeBytes > maxFileSizeBytes }) {
            return UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: maxFileSizeMB)
        }

        let fileBytesUsed = attachmentUsage?.fileSizeBytesUsed ?? 0
        if fileBytesUsed + pendingFileSizeBytes > maxTotalFileSizeBytes {
            return UserText.aiChatAttachmentFilesExceedTotalSizeLimit(maxTotalFileSizeMB: maxTotalFileSizeMB)
        }

        return pendingFiles.compactMap { pageValidationError(for: $0)?.message }.first
    }

    func imageSubmissionValidationMessage() -> String? {
        guard pendingImageCount > 0 else { return nil }
        guard model?.supportsImageUpload == true else {
            return UserText.aiChatAttachmentUnavailable
        }

        guard let maxImagesPerTurn,
              let maxImagesPerConversation else {
            return UserText.aiChatAttachmentUnavailable
        }

        let imagesUsed = attachmentUsage?.imagesUsed ?? 0
        if pendingImageCount > maxImagesPerTurn {
            return UserText.aiChatAttachmentImageTurnLimit(maxImagesPerTurn: maxImagesPerTurn)
        }

        if imagesUsed + pendingImageCount > maxImagesPerConversation {
            return UserText.aiChatAttachmentImageCountLimit(maxImagesPerConversation: maxImagesPerConversation)
        }

        return nil
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
        let promptLength = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard !pendingAttachments.isEmpty,
              let maxInputCharsWithAttachments,
              promptLength > maxInputCharsWithAttachments else {
            return nil
        }

        return UserText.aiChatAttachmentPromptTooLong
    }
}

private extension UTIAttachmentPolicy {

    var pendingImageCount: Int {
        pendingAttachments.filter(\.isImage).count
    }

    var pendingFileCount: Int {
        pendingAttachments.compactMap(\.fileAttachment).count
    }

    var pendingFileSizeBytes: Int {
        pendingAttachments.compactMap(\.fileAttachment).reduce(0) { $0 + $1.fileSizeBytes }
    }

    var maxImagesPerTurn: Int? {
        attachmentLimits?.images.maxPerTurn
    }

    var maxImagesPerConversation: Int? {
        attachmentLimits?.images.maxPerConversation
    }

    var maxFilesPerConversation: Int? {
        attachmentLimits?.files.maxPerConversation
    }

    var maxFileSizeMB: Int? {
        attachmentLimits?.files.maxFileSizeMB
    }

    var maxFileSizeBytes: Int? {
        maxFileSizeMB.map { $0 * 1_048_576 }
    }

    var maxTotalFileSizeBytes: Int? {
        attachmentLimits?.files.maxTotalFileSizeBytes
    }

    var maxPagesPerFile: Int? {
        attachmentLimits?.files.maxPagesPerFile
    }

    var maxInputCharsWithAttachments: Int? {
        attachmentLimits?.images.maxInputCharsWithAttachments
    }

    var maxTotalFileSizeMB: Int? {
        maxTotalFileSizeBytes.map { Int(ceil(Double($0) / 1_048_576)) }
    }

    func pageValidationError(for attachment: AIChatFileAttachment) -> FileValidationError? {
        guard attachment.mimeType == "application/pdf",
              let maxPagesPerFile else {
            return nil
        }

        guard let pageCount = attachment.pageCount else {
            if attachment.isEncrypted {
                return FileValidationError(reason: .encrypted, message: UserText.aiChatAttachmentFileEncrypted)
            } else {
                return FileValidationError(reason: .unreadable, message: UserText.aiChatAttachmentFileUnreadable)
            }
        }

        if pageCount > maxPagesPerFile {
            return FileValidationError(
                reason: .countExceeded,
                message: UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: maxPagesPerFile)
            )
        }
        return nil
    }

    var acceptedFileTypeNames: [String] {
        model?.supportedFileTypes.map(Self.fileTypeName(for:)) ?? []
    }

    static func fileTypeName(for mimeType: String) -> String {
        switch mimeType {
        case "application/pdf":
            return "PDF"
        case "image/jpeg":
            return "JPG"
        case "image/png":
            return "PNG"
        case "image/webp":
            return "WebP"
        case "image/gif":
            return "GIF"
        default:
            if let filenameExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension {
                return filenameExtension.uppercased()
            }

            let subtype = mimeType.split(separator: "/").last.map(String.init) ?? mimeType
            return (subtype.split(separator: ".").last.map(String.init) ?? subtype).uppercased()
        }
    }
}
