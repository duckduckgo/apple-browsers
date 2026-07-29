//
//  UnifiedToggleInputPasteHandler.swift
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
import UniformTypeIdentifiers

/// Injected into the shared text controls so a native image/file paste is routed into the attachment strip; `nil` on non-UTI hosts leaves default text paste untouched.
@MainActor
protocol AttachmentPasteHandling: AnyObject {

    /// Whether the pasteboard holds image/file content that can become an attachment; metadata-only, safe from `canPerformAction(_:withSender:)`.
    func canPasteAttachments(from pasteboard: UIPasteboard) -> Bool

    /// Turns supported pasteboard items into attachments; loads asynchronously.
    func pasteAttachments(from pasteboard: UIPasteboard)
}

/// Shared `paste(_:)` / `canPerformAction(_:)` routing that keeps the paste-intercept logic in one place for the text control.
@MainActor
enum AttachmentPasteRouting {

    static func canPaste(with handler: AttachmentPasteHandling?) -> Bool {
        handler?.canPasteAttachments(from: .general) ?? false
    }

    /// Routes the general pasteboard to the handler; returns `false` when the caller should fall back to the default paste.
    static func routePaste(with handler: AttachmentPasteHandling?) -> Bool {
        guard let handler, handler.canPasteAttachments(from: .general) else { return false }
        handler.pasteAttachments(from: .general)
        return true
    }
}

/// Why a pasted file couldn't be attached, carried from the loader so the error is reported for the actual reason (not recomputed against later state).
enum PasteRejectionReason: Equatable {
    case fileTooLarge
    case filesExceedTotalSize
    case fileCountLimit
}

/// What the current model accepts plus the remaining headroom, snapshotted once per paste so the loader can preflight sizes/counts.
struct UnifiedToggleInputPasteSupport {
    let isEnabled: Bool
    let acceptsImages: Bool
    let fileTypes: [UTType]
    /// Number of images the loader may decode before it stops, so a paste of many photos can't over-allocate.
    let maxImageCount: Int?
    /// Per-file byte limit, used to reject an oversized paste from its size alone before reading it into memory.
    let maxFileSizeBytes: Int?
    /// Remaining conversation file slots; the loader stops reading once exhausted so a large multi-file paste can't over-allocate.
    let remainingFileCount: Int?
    /// Remaining conversation file bytes; the loader reads only files that fit within this budget.
    let remainingTotalFileBytes: Int?

    init(
        isEnabled: Bool,
        acceptsImages: Bool,
        fileTypes: [UTType],
        maxImageCount: Int? = nil,
        maxFileSizeBytes: Int? = nil,
        remainingFileCount: Int? = nil,
        remainingTotalFileBytes: Int? = nil
    ) {
        self.isEnabled = isEnabled
        self.acceptsImages = acceptsImages
        self.fileTypes = fileTypes
        self.maxImageCount = maxImageCount
        self.maxFileSizeBytes = maxFileSizeBytes
        self.remainingFileCount = remainingFileCount
        self.remainingTotalFileBytes = remainingTotalFileBytes
    }

    var acceptsAnyAttachment: Bool { acceptsImages || !fileTypes.isEmpty }
}

/// The host the paste handler calls back into to read limits and add/report attachments (the coordinator).
@MainActor
protocol UnifiedToggleInputPasteDelegate: AnyObject {
    var pasteAttachmentSupport: UnifiedToggleInputPasteSupport { get }
    /// Identity of the tab/surface the paste started on; the handler drops results if it changed during the async load.
    var pasteContextIdentity: String? { get }
    func imageCapacityMessage() -> String?
    func pasteWillBeginExpandingIfNeeded()
    /// Adds the image if there is headroom; returns `false` when the image limit is reached.
    @discardableResult func addPastedImage(_ image: UIImage, fileName: String) -> Bool
    func addPastedFile(_ file: AIChatFileAttachment)
    /// Reports a file rejected during load (over size/count/total) with an error for the given reason; never adds an attachment.
    func reportRejectedPaste(reason: PasteRejectionReason)
    func presentPasteError(_ message: String)
}

/// Owns the paste orchestration (gate → load → add → report) so the coordinator only supplies limits and add actions via `UnifiedToggleInputPasteDelegate`.
@MainActor
final class UnifiedToggleInputPasteHandler: AttachmentPasteHandling {

    weak var delegate: UnifiedToggleInputPasteDelegate?

    func canPasteAttachments(from pasteboard: UIPasteboard) -> Bool {
        guard let support = delegate?.pasteAttachmentSupport, support.isEnabled, support.acceptsAnyAttachment else { return false }
        return PasteboardAttachmentReader.hasSupportedAttachments(
            in: pasteboard,
            allowsImages: support.acceptsImages,
            allowedFileTypes: support.fileTypes
        )
    }

    func pasteAttachments(from pasteboard: UIPasteboard) {
        guard let delegate else { return }
        let support = delegate.pasteAttachmentSupport
        guard support.isEnabled, support.acceptsAnyAttachment else { return }
        let providers = pasteboard.itemProviders
        let context = delegate.pasteContextIdentity
        delegate.pasteWillBeginExpandingIfNeeded()
        Task { [weak self] in
            let result = await PasteboardAttachmentReader.loadAttachments(
                from: providers,
                allowsImages: support.acceptsImages,
                allowedFileTypes: support.fileTypes,
                maxImageCount: support.maxImageCount,
                maxFileSizeBytes: support.maxFileSizeBytes,
                remainingFileCount: support.remainingFileCount,
                remainingTotalFileBytes: support.remainingTotalFileBytes
            )
            self?.applyLoadedAttachments(result, expectedContext: context)
        }
    }

    /// Applied after the async load; drops the result if paste was disabled or the tab/conversation changed during the load. Files first so a rejected image's limit message (presented last) survives a following file add.
    func applyLoadedAttachments(_ result: PasteboardAttachmentReader.Result, expectedContext: String? = nil) {
        guard let delegate,
              delegate.pasteAttachmentSupport.isEnabled,
              delegate.pasteContextIdentity == expectedContext else { return }

        for file in result.files {
            delegate.addPastedFile(file)
        }

        if let rejection = result.rejection {
            delegate.reportRejectedPaste(reason: rejection)
        }

        var didExceedImageLimit = false
        for image in result.images {
            guard delegate.addPastedImage(image.image, fileName: image.fileName) else {
                didExceedImageLimit = true
                break
            }
        }

        if didExceedImageLimit || result.imagesTruncated, let message = delegate.imageCapacityMessage() {
            delegate.presentPasteError(message)
        }
    }
}

/// Extracts image/file attachments from a `UIPasteboard`, mirroring the picker paths so pasted content flows through the same validation and UI as the attach menu.
@MainActor
enum PasteboardAttachmentReader {

    struct Result {
        var images: [(image: UIImage, fileName: String)] = []
        var files: [AIChatFileAttachment] = []
        /// The reason the first over-budget file was rejected; capped at one so an exhausted capacity can't flood the strip.
        var rejection: PasteRejectionReason?
        /// More image providers were present than the allowance, so some were dropped without decoding.
        var imagesTruncated = false
    }

    private enum LoadedFile {
        case read(AIChatFileAttachment)
        case rejected(PasteRejectionReason)
    }

    /// Metadata-only probe (no byte reads, so no paste banner) that mirrors `loadAttachments`' per-provider classification, so a "yes" here means the loader will actually find something.
    static func hasSupportedAttachments(
        in pasteboard: UIPasteboard,
        allowsImages: Bool,
        allowedFileTypes: [UTType]
    ) -> Bool {
        let fileIdentifiers = allowedFileTypes.map(\.identifier)
        return pasteboard.itemProviders.contains { provider in
            if allowsImages, provider.canLoadObject(ofClass: UIImage.self) {
                return true
            }
            return fileIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }
    }

    /// Reads the pasteboard bytes (surfaces the banner) and builds attachments. Images stop decoding at the allowance and files are
    /// size/count-preflighted from metadata against the remaining budget, so a large multi-item paste only ever loads what can be accepted.
    static func loadAttachments(
        from providers: [NSItemProvider],
        allowsImages: Bool,
        allowedFileTypes: [UTType],
        maxImageCount: Int? = nil,
        maxFileSizeBytes: Int? = nil,
        remainingFileCount: Int? = nil,
        remainingTotalFileBytes: Int? = nil
    ) async -> Result {
        var result = Result()
        var loadedImageCount = 0
        var readFileCount = 0
        var readFileBytes = 0
        var fileCapacityExhausted = false

        for provider in providers {
            if allowsImages, provider.canLoadObject(ofClass: UIImage.self) {
                if let maxImageCount, loadedImageCount >= maxImageCount {
                    result.imagesTruncated = true
                    continue
                }
                if let image = await loadImage(from: provider) {
                    result.images.append((image, provider.suggestedName ?? "image"))
                    loadedImageCount += 1
                }
            } else if let type = allowedFileTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                guard !fileCapacityExhausted else { continue }

                let remainingCount = remainingFileCount.map { $0 - readFileCount }
                let remainingBytes = remainingTotalFileBytes.map { $0 - readFileBytes }
                if remainingCount.map({ $0 <= 0 }) ?? false {
                    fileCapacityExhausted = true
                    recordRejection(.fileCountLimit, in: &result)
                    continue
                }
                if remainingBytes.map({ $0 <= 0 }) ?? false {
                    fileCapacityExhausted = true
                    recordRejection(.filesExceedTotalSize, in: &result)
                    continue
                }

                switch await loadFile(from: provider, type: type, maxFileSizeBytes: maxFileSizeBytes, remainingBytes: remainingBytes) {
                case .read(let file):
                    readFileCount += 1
                    readFileBytes += file.fileSizeBytes
                    result.files.append(file)
                case .rejected(let reason):
                    recordRejection(reason, in: &result)
                case nil:
                    break
                }
            }
        }
        return result
    }

    private static func recordRejection(_ reason: PasteRejectionReason, in result: inout Result) {
        if result.rejection == nil {
            result.rejection = reason
        }
    }

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    /// Loads via a file representation and preflights per-file size and remaining total bytes from metadata; over-budget files are
    /// returned as rejections (metadata only, never read), so bytes are read only for files that can be accepted.
    private static func loadFile(
        from provider: NSItemProvider,
        type: UTType,
        maxFileSizeBytes: Int?,
        remainingBytes: Int?
    ) async -> LoadedFile? {
        let fileName = fileName(for: provider, type: type)
        let mimeType = mimeType(for: type)

        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                if let fileSize {
                    if let maxFileSizeBytes, fileSize > maxFileSizeBytes {
                        continuation.resume(returning: .rejected(.fileTooLarge))
                        return
                    }
                    if let remainingBytes, fileSize > remainingBytes {
                        continuation.resume(returning: .rejected(.filesExceedTotalSize))
                        return
                    }
                }

                guard let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: .read(UnifiedToggleInputAttachmentPresenter.makeFileAttachment(data: data, fileName: fileName, mimeType: mimeType)))
            }
        }
    }

    private static func fileName(for provider: NSItemProvider, type: UTType) -> String {
        let baseName = provider.suggestedName ?? "file"
        guard (baseName as NSString).pathExtension.isEmpty, let ext = type.preferredFilenameExtension else { return baseName }
        return "\(baseName).\(ext)"
    }

    private static func mimeType(for type: UTType) -> String {
        type.preferredMIMEType ?? "application/octet-stream"
    }
}
