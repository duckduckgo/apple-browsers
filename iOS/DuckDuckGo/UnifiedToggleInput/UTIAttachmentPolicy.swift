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

struct UTIAttachmentPolicy {

    let attachmentLimits: AIChatAttachmentTierLimits?
    let attachmentUsage: AIChatAttachmentUsage?
    let pendingAttachments: [UnifiedToggleInputAttachment]
    let model: AIChatModel?

    private var pendingImageCount: Int {
        pendingAttachments.filter(\.isImage).count
    }

    private var pendingFileCount: Int {
        pendingAttachments.filter(\.isFile).count
    }

    private var pendingFileSizeBytes: Int {
        pendingAttachments.reduce(0) { $0 + $1.fileSizeBytes }
    }

    private var maxImagesPerTurn: Int? {
        attachmentLimits?.images.maxPerTurn
    }

    private var maxImagesPerConversation: Int? {
        attachmentLimits?.images.maxPerConversation
    }

    private var maxFilesPerConversation: Int? {
        attachmentLimits?.files.maxPerConversation
    }

    private var maxFileSizeBytes: Int? {
        attachmentLimits.map { $0.files.maxFileSizeMB * 1_048_576 }
    }

    private var maxTotalFileSizeBytes: Int? {
        attachmentLimits?.files.maxTotalFileSizeBytes
    }

    private var maxPagesPerFile: Int? {
        attachmentLimits?.files.maxPagesPerFile
    }

    private var maxInputCharsWithAttachments: Int? {
        attachmentLimits?.images.maxInputCharsWithAttachments
    }

    var maximumPendingAttachments: Int? {
        guard let attachmentLimits else { return nil }
        return max(attachmentLimits.images.maxPerTurn, attachmentLimits.files.maxPerConversation)
    }

    private var remainingPendingAttachmentSlots: Int {
        guard let maximumPendingAttachments else { return 0 }
        return max(0, maximumPendingAttachments - pendingAttachments.count)
    }

    var remainingImagesInConversation: Int {
        guard let maxImagesPerConversation else { return 0 }
        let conversationUsed = attachmentUsage?.imagesUsed ?? 0
        return max(0, maxImagesPerConversation - conversationUsed)
    }

    var remainingImagesForPicker: Int {
        guard let maxImagesPerTurn else { return 0 }
        let perTurnRemaining = max(0, maxImagesPerTurn - pendingImageCount)
        let conversationRemaining = max(0, remainingImagesInConversation - pendingImageCount)
        return max(0, min(perTurnRemaining, conversationRemaining, remainingPendingAttachmentSlots))
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

        return remainingPendingAttachmentSlots > 0 && remainingConversationSlots > 0 && remainingBytes > 0
    }

    var remainingFileSizeBytes: Int {
        guard let maxTotalFileSizeBytes else { return 0 }
        let fileBytesUsed = attachmentUsage?.fileSizeBytesUsed ?? 0
        return max(0, maxTotalFileSizeBytes - fileBytesUsed - pendingFileSizeBytes)
    }

    func fileValidationMessage(for attachment: AIChatFileAttachment) -> String? {
        guard canAttachFiles,
              model?.supportedFileTypes.contains(attachment.mimeType) == true else {
            return UserText.aiChatAttachmentFileExceedsConversationLimit
        }

        if let maxFileSizeBytes, attachment.fileSizeBytes > maxFileSizeBytes {
            return UserText.aiChatAttachmentFileTooLarge
        }

        if attachment.fileSizeBytes > remainingFileSizeBytes {
            return UserText.aiChatAttachmentFileExceedsConversationLimit
        }

        if let pageValidationMessage = pageValidationMessage(for: attachment) {
            return pageValidationMessage
        }

        return nil
    }

    func canAttachFile(_ attachment: AIChatFileAttachment) -> Bool {
        fileValidationMessage(for: attachment) == nil
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

    private func pageValidationMessage(for attachment: AIChatFileAttachment) -> String? {
        guard attachment.mimeType == "application/pdf",
              let maxPagesPerFile else {
            return nil
        }

        guard let pageCount = attachment.pageCount else {
            return UserText.aiChatAttachmentFileUnreadable
        }

        return pageCount > maxPagesPerFile ? UserText.aiChatAttachmentFileTooManyPages : nil
    }
}
