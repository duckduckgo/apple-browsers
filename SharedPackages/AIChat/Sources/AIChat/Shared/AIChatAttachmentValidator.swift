//
//  AIChatAttachmentValidator.swift
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
import UniformTypeIdentifiers

/// Attachments already sent in the current conversation. The address-bar entry point (a brand-new
/// chat) has no prior usage and passes `.zero`; an in-conversation surface maps its live usage here.
public struct AIChatAttachmentUsageSnapshot: Equatable, Sendable {
    public let imagesUsed: Int
    public let filesUsed: Int
    public let fileSizeBytesUsed: Int

    public init(imagesUsed: Int = 0, filesUsed: Int = 0, fileSizeBytesUsed: Int = 0) {
        self.imagesUsed = imagesUsed
        self.filesUsed = filesUsed
        self.fileSizeBytesUsed = fileSizeBytesUsed
    }

    public static let zero = AIChatAttachmentUsageSnapshot()
}

/// Platform-agnostic validation of attachment limits returned by the models endpoint
/// (`attachmentLimits`). Holds the limit arithmetic so iOS and macOS share one source of truth;
/// callers supply their pending attachments as primitives and inject the localized message strings
/// (the validator deliberately never references `UserText`, which is platform-specific).
public struct AIChatAttachmentValidator {

    public enum FileValidationFailureReason: String, Sendable {
        case sizeExceeded = "size_exceeded"
        case countExceeded = "count_exceeded"
        case unsupportedType = "unsupported_type"
        case other
        case encrypted
        case unreadable
    }

    public struct FileValidationError: Equatable, Sendable {
        public let reason: FileValidationFailureReason
        public let message: String

        public init(reason: FileValidationFailureReason, message: String) {
            self.reason = reason
            self.message = message
        }
    }

    /// The subset of an attachment the validator reads. Built from an `AIChatFileAttachment` or
    /// directly at pick-time (before an attachment record exists).
    public struct FileDescriptor: Equatable, Sendable {
        public let mimeType: String
        public let fileSizeBytes: Int
        public let pageCount: Int?
        public let isEncrypted: Bool

        public init(mimeType: String, fileSizeBytes: Int, pageCount: Int? = nil, isEncrypted: Bool = false) {
            self.mimeType = mimeType
            self.fileSizeBytes = fileSizeBytes
            self.pageCount = pageCount
            self.isEncrypted = isEncrypted
        }

        public init(_ attachment: AIChatFileAttachment) {
            self.init(
                mimeType: attachment.mimeType,
                fileSizeBytes: attachment.fileSizeBytes,
                pageCount: attachment.pageCount,
                isEncrypted: attachment.isEncrypted
            )
        }
    }

    /// Localized message strings injected by the caller, keyed by failure mode. Parameterized
    /// messages take the relevant limit so the copy can interpolate it.
    public struct Messages {
        public let unsupportedFileType: String
        public let unavailable: String
        public let fileEncrypted: String
        public let fileUnreadable: String
        public let promptTooLong: String
        public let unsupportedFileTypeWithAccepted: (_ acceptedFileTypes: [String]) -> String
        public let fileCountLimit: (_ maxFilesPerConversation: Int) -> String
        public let fileTooLarge: (_ maxFileSizeMB: Int) -> String
        public let filesExceedTotalSizeLimit: (_ maxTotalFileSizeMB: Int) -> String
        public let fileTooManyPages: (_ maxPagesPerFile: Int) -> String
        public let imageTurnLimit: (_ maxImagesPerTurn: Int) -> String
        public let imageCountLimit: (_ maxImagesPerConversation: Int) -> String

        public init(
            unsupportedFileType: String,
            unavailable: String,
            fileEncrypted: String,
            fileUnreadable: String,
            promptTooLong: String,
            unsupportedFileTypeWithAccepted: @escaping (_ acceptedFileTypes: [String]) -> String,
            fileCountLimit: @escaping (_ maxFilesPerConversation: Int) -> String,
            fileTooLarge: @escaping (_ maxFileSizeMB: Int) -> String,
            filesExceedTotalSizeLimit: @escaping (_ maxTotalFileSizeMB: Int) -> String,
            fileTooManyPages: @escaping (_ maxPagesPerFile: Int) -> String,
            imageTurnLimit: @escaping (_ maxImagesPerTurn: Int) -> String,
            imageCountLimit: @escaping (_ maxImagesPerConversation: Int) -> String
        ) {
            self.unsupportedFileType = unsupportedFileType
            self.unavailable = unavailable
            self.fileEncrypted = fileEncrypted
            self.fileUnreadable = fileUnreadable
            self.promptTooLong = promptTooLong
            self.unsupportedFileTypeWithAccepted = unsupportedFileTypeWithAccepted
            self.fileCountLimit = fileCountLimit
            self.fileTooLarge = fileTooLarge
            self.filesExceedTotalSizeLimit = filesExceedTotalSizeLimit
            self.fileTooManyPages = fileTooManyPages
            self.imageTurnLimit = imageTurnLimit
            self.imageCountLimit = imageCountLimit
        }
    }

    public let limits: AIChatAttachmentTierLimits?
    public let model: AIChatModel?
    public let usage: AIChatAttachmentUsageSnapshot
    public let pendingImageCount: Int
    public let pendingFiles: [FileDescriptor]
    public let messages: Messages

    public init(
        limits: AIChatAttachmentTierLimits?,
        model: AIChatModel?,
        usage: AIChatAttachmentUsageSnapshot = .zero,
        pendingImageCount: Int = 0,
        pendingFiles: [FileDescriptor] = [],
        messages: Messages
    ) {
        self.limits = limits
        self.model = model
        self.usage = usage
        self.pendingImageCount = pendingImageCount
        self.pendingFiles = pendingFiles
        self.messages = messages
    }

    // MARK: - Image capacity

    public var remainingImagesInConversation: Int {
        guard let maxImagesPerConversation else { return 0 }
        return max(0, maxImagesPerConversation - usage.imagesUsed)
    }

    /// How many more images the picker should allow right now — the min of the per-turn and
    /// per-conversation headroom, both reduced by what's already pending.
    public var remainingImagesForPicker: Int {
        guard let maxImagesPerTurn else { return 0 }
        let perTurnRemaining = max(0, maxImagesPerTurn - pendingImageCount)
        let conversationRemaining = max(0, remainingImagesInConversation - pendingImageCount)
        return max(0, min(perTurnRemaining, conversationRemaining))
    }

    public var isConversationImageLimitReached: Bool {
        remainingImagesInConversation == 0
    }

    public var canAttachImages: Bool {
        model?.supportsImageUpload == true && remainingImagesForPicker > 0
    }

    // MARK: - File capacity

    public var canAttachFiles: Bool {
        guard model?.supportsFileUpload == true,
              let maxFilesPerConversation,
              let maxTotalFileSizeBytes else {
            return false
        }

        let remainingConversationSlots = maxFilesPerConversation - usage.filesUsed - pendingFileCount
        let remainingBytes = maxTotalFileSizeBytes - usage.fileSizeBytesUsed - pendingFileSizeBytes

        return remainingConversationSlots > 0 && remainingBytes > 0
    }

    public var remainingFileSizeBytes: Int {
        guard let maxTotalFileSizeBytes else { return 0 }
        return max(0, maxTotalFileSizeBytes - usage.fileSizeBytesUsed - pendingFileSizeBytes)
    }

    // MARK: - File validation

    public func fileValidationMessage(for file: FileDescriptor) -> String? {
        fileValidationError(for: file)?.message
    }

    /// - Parameter enforceCount: when `false`, the per-conversation file-count limit is not
    ///   checked. Callers that surface the count limit through their own UI (e.g. macOS's "one
    ///   over the cap" carousel cue) pass `false` so a count overflow doesn't pre-empt the
    ///   size / page / type checks that should reject the file outright.
    public func fileValidationError(for file: FileDescriptor, enforceCount: Bool = true) -> FileValidationError? {
        if let metadataError = fileMetadataValidationError(mimeType: file.mimeType, fileSizeBytes: file.fileSizeBytes, enforceCount: enforceCount) {
            return metadataError
        }
        return pageValidationError(for: file)
    }

    public func canAttachFile(_ file: FileDescriptor) -> Bool {
        fileValidationMessage(for: file) == nil
    }

    public func fileMetadataValidationError(mimeType: String, fileSizeBytes: Int?, enforceCount: Bool = true) -> FileValidationError? {
        guard model?.supportsFileUpload == true else {
            return FileValidationError(reason: .unsupportedType, message: messages.unsupportedFileType)
        }

        guard let maxFilesPerConversation,
              let maxFileSizeMB,
              let maxFileSizeBytes,
              let maxTotalFileSizeBytes,
              let maxTotalFileSizeMB else {
            return FileValidationError(reason: .other, message: messages.unavailable)
        }

        guard model?.supportedFileTypes.contains(mimeType) == true else {
            return FileValidationError(
                reason: .unsupportedType,
                message: messages.unsupportedFileTypeWithAccepted(acceptedFileTypeNames)
            )
        }

        let remainingConversationSlots = maxFilesPerConversation - usage.filesUsed - pendingFileCount
        let remainingBytes = maxTotalFileSizeBytes - usage.fileSizeBytesUsed - pendingFileSizeBytes

        if enforceCount, remainingConversationSlots <= 0 {
            return FileValidationError(
                reason: .countExceeded,
                message: messages.fileCountLimit(maxFilesPerConversation)
            )
        }

        if let fileSizeBytes {
            if fileSizeBytes > maxFileSizeBytes {
                return FileValidationError(
                    reason: .sizeExceeded,
                    message: messages.fileTooLarge(maxFileSizeMB)
                )
            }

            if fileSizeBytes > remainingBytes {
                return FileValidationError(
                    reason: .sizeExceeded,
                    message: messages.filesExceedTotalSizeLimit(maxTotalFileSizeMB)
                )
            }
        }

        return nil
    }

    /// Validation against the entire pending file set, for the pre-submit gate.
    public func fileSubmissionValidationMessage() -> String? {
        guard !pendingFiles.isEmpty else { return nil }
        guard model?.supportsFileUpload == true else {
            return messages.unsupportedFileType
        }

        guard let maxFilesPerConversation,
              let maxFileSizeMB,
              let maxFileSizeBytes,
              let maxTotalFileSizeBytes,
              let maxTotalFileSizeMB else {
            return messages.unavailable
        }

        if pendingFiles.contains(where: { model?.supportedFileTypes.contains($0.mimeType) != true }) {
            return messages.unsupportedFileTypeWithAccepted(acceptedFileTypeNames)
        }

        if usage.filesUsed + pendingFileCount > maxFilesPerConversation {
            return messages.fileCountLimit(maxFilesPerConversation)
        }

        if pendingFiles.contains(where: { $0.fileSizeBytes > maxFileSizeBytes }) {
            return messages.fileTooLarge(maxFileSizeMB)
        }

        if usage.fileSizeBytesUsed + pendingFileSizeBytes > maxTotalFileSizeBytes {
            return messages.filesExceedTotalSizeLimit(maxTotalFileSizeMB)
        }

        return pendingFiles.compactMap { pageValidationError(for: $0)?.message }.first
    }

    // MARK: - Image / prompt validation

    public func imageSubmissionValidationMessage() -> String? {
        guard pendingImageCount > 0 else { return nil }
        guard model?.supportsImageUpload == true else {
            return messages.unavailable
        }

        guard let maxImagesPerTurn,
              let maxImagesPerConversation else {
            return messages.unavailable
        }

        if pendingImageCount > maxImagesPerTurn {
            return messages.imageTurnLimit(maxImagesPerTurn)
        }

        if usage.imagesUsed + pendingImageCount > maxImagesPerConversation {
            return messages.imageCountLimit(maxImagesPerConversation)
        }

        return nil
    }

    public func promptValidationMessage(for text: String) -> String? {
        let promptLength = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard !(pendingFiles.isEmpty && pendingImageCount == 0),
              let maxInputCharsWithAttachments,
              promptLength > maxInputCharsWithAttachments else {
            return nil
        }

        return messages.promptTooLong
    }

    // MARK: - Accepted file-type names

    public var acceptedFileTypeNames: [String] {
        model?.supportedFileTypes.map(Self.fileTypeName(for:)) ?? []
    }

    public static func fileTypeName(for mimeType: String) -> String {
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

// MARK: - Limit accessors

private extension AIChatAttachmentValidator {

    var pendingFileCount: Int {
        pendingFiles.count
    }

    var pendingFileSizeBytes: Int {
        pendingFiles.reduce(0) { $0 + $1.fileSizeBytes }
    }

    var maxImagesPerTurn: Int? {
        limits?.images.maxPerTurn
    }

    var maxImagesPerConversation: Int? {
        limits?.images.maxPerConversation
    }

    var maxFilesPerConversation: Int? {
        limits?.files.maxPerConversation
    }

    var maxFileSizeMB: Int? {
        limits?.files.maxFileSizeMB
    }

    var maxFileSizeBytes: Int? {
        maxFileSizeMB.map { $0 * 1_048_576 }
    }

    var maxTotalFileSizeBytes: Int? {
        limits?.files.maxTotalFileSizeBytes
    }

    var maxTotalFileSizeMB: Int? {
        maxTotalFileSizeBytes.map { Int(ceil(Double($0) / 1_048_576)) }
    }

    var maxPagesPerFile: Int? {
        limits?.files.maxPagesPerFile
    }

    var maxInputCharsWithAttachments: Int? {
        limits?.images.maxInputCharsWithAttachments
    }

    func pageValidationError(for file: FileDescriptor) -> FileValidationError? {
        guard file.mimeType == "application/pdf",
              let maxPagesPerFile else {
            return nil
        }

        guard let pageCount = file.pageCount else {
            if file.isEncrypted {
                return FileValidationError(reason: .encrypted, message: messages.fileEncrypted)
            } else {
                return FileValidationError(reason: .unreadable, message: messages.fileUnreadable)
            }
        }

        if pageCount > maxPagesPerFile {
            return FileValidationError(
                reason: .countExceeded,
                message: messages.fileTooManyPages(maxPagesPerFile)
            )
        }
        return nil
    }
}
