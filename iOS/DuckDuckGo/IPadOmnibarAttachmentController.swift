//
//  IPadOmnibarAttachmentController.swift
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
import UniformTypeIdentifiers

/// Drives the Duck.ai attachment picker shown on the far left of the iPad address bar's expanded
/// AI-chat input area, and the strip of pending attachments displayed above the toolbar row.
///
/// Reuses the iPhone attachment stack — `UnifiedToggleInputAttachmentPresenter` for picking,
/// `UnifiedToggleInputAttachmentsStripView` for display, `UTIAttachmentPolicy` for limits, and the
/// shared encoders for submission — so iPad and iPhone stay in lockstep. The strip view owns the
/// pending attachments; this controller reads them for policy checks and submission payloads.
@MainActor
final class IPadOmnibarAttachmentController {

    private let store: UTIModelStore
    private let presenter = UnifiedToggleInputAttachmentPresenter()

    /// The strip that renders and owns the pending attachments. Set by the omnibar view controller
    /// once its view is loaded.
    weak var attachmentsStripView: UnifiedToggleInputAttachmentsStripView? {
        didSet {
            attachmentsStripView?.onAttachmentRemoved = { _, attachment, isUserInitiated in
                guard isUserInitiated else { return }
                UnifiedToggleInputCoordinatorPixelHelper.fireAttachmentRemovedPixel(for: attachment, surface: .addressBar)
            }
        }
    }

    /// Supplies the view controller used to present the photo / camera / document pickers.
    var presenterProvider: (() -> UIViewController?)?

    /// Requested after a picker completes, so the omnibar can ensure it stays expanded.
    var onExpandRequested: (() -> Void)?

    init(store: UTIModelStore) {
        self.store = store

        presenter.onExpandIfNeeded = { [weak self] in
            self?.onExpandRequested?()
        }
        presenter.onImagePicked = { [weak self] image, fileName in
            self?.addImageAttachment(image: image, fileName: fileName)
        }
        presenter.onFilePicked = { [weak self] attachment, metadata in
            self?.addFileAttachment(attachment, sourceURL: metadata.url)
        }
        presenter.onFileValidationFailed = { [weak self] message, metadata in
            self?.addInvalidFileAttachment(metadata: metadata, validationMessage: message)
        }
        presenter.fileMetadataValidationMessage = { [weak self] metadata in
            self?.attachmentPolicy.fileMetadataValidationError(mimeType: metadata.mimeType, fileSizeBytes: metadata.fileSizeBytes)?.message
        }
    }

    // MARK: - Availability

    /// Whether the selected model accepts any attachment kind (so the button should be shown at all).
    var isAttachButtonAvailable: Bool {
        store.selectedModelSupportsImageUpload || !allowedFileUTTypes.isEmpty
    }

    /// Whether the current selection still allows attaching more (so the button should be enabled).
    var canAttachMore: Bool {
        attachmentPolicy.canAttachImages || canPresentFilePicker
    }

    func makeMenu() -> UIMenu? {
        guard isAttachButtonAvailable, canAttachMore else { return nil }
        return presenter.makeAttachmentMenu(
            presenterProvider: { [weak self] in self?.presenterProvider?() },
            photoSelectionLimit: attachmentPolicy.canAttachImages ? attachmentPolicy.remainingImagesForPicker : 0,
            canAttachFile: canPresentFilePicker,
            allowedFileTypes: allowedFileUTTypes
        )
    }

    // MARK: - Model change

    /// Re-evaluates pending attachments after the selected model changes, dropping any the new model
    /// cannot accept. Any removals notify the omnibar via the strip's `onAttachmentsChanged`; the
    /// caller still refreshes the attach menu directly (limits/types can change with no removal).
    func handleModelChanged() {
        removeUnsupportedAttachmentsForSelectedModel()
    }

    // MARK: - Submission

    var hasAttachments: Bool {
        !currentAttachments.isEmpty
    }

    var pendingAttachments: [UnifiedToggleInputAttachment] {
        currentAttachments
    }

    /// Whether at least one pending attachment is valid (submittable). Mirrors the iPhone unified
    /// toggle rule that lets a valid attachment stand in for prompt text.
    var hasValidAttachment: Bool {
        currentAttachments.contains { !$0.isInvalid }
    }

    /// Whether any pending attachment failed validation. The iPhone flow blocks submission while
    /// this is true; the iPad send path mirrors that.
    var hasInvalidAttachment: Bool {
        currentAttachments.contains(where: \.isInvalid)
    }

    var encodedImages: [AIChatNativePrompt.NativePromptImage]? {
        UnifiedToggleInputImageEncoder.encode(currentAttachments)
    }

    var encodedFiles: [AIChatNativePrompt.NativePromptFile]? {
        UnifiedToggleInputFileEncoder.encode(currentAttachments)
    }

    /// Clears all pending attachments (on submit or when leaving Duck.ai mode).
    func resetSelection() {
        guard hasAttachments else { return }
        attachmentsStripView?.removeAllAttachments()
    }

    // MARK: - Private

    private var currentAttachments: [UnifiedToggleInputAttachment] {
        attachmentsStripView?.attachments ?? []
    }

    /// Built fresh each access so it reflects the latest model and pending attachments. Usage is nil:
    /// the omnibar composes a brand-new chat, so nothing has been consumed yet.
    private var attachmentPolicy: UTIAttachmentPolicy {
        UTIAttachmentPolicy(
            attachmentLimits: store.attachmentLimits,
            attachmentUsage: nil,
            pendingAttachments: currentAttachments,
            model: store.selectedModel
        )
    }

    private var allowedFileUTTypes: [UTType] {
        store.selectedModelSupportedFileTypes.compactMap { UTType(mimeType: $0) }
    }

    private var canPresentFilePicker: Bool {
        attachmentPolicy.canAttachFiles && !allowedFileUTTypes.isEmpty
    }

    private func addImageAttachment(image: UIImage, fileName: String) {
        guard attachmentPolicy.canAttachImages else { return }
        attachmentsStripView?.addAttachment(.image(AIChatImageAttachment(image: image, fileName: fileName)))
    }

    private func addFileAttachment(_ fileAttachment: AIChatFileAttachment, sourceURL: URL?) {
        if let validationError = attachmentPolicy.fileValidationError(for: fileAttachment) {
            DailyPixel.fireDailyAndCount(
                pixel: .unifiedToggleInputFileValidationFailed,
                withAdditionalParameters: ["reason": validationError.reason.rawValue, "surface": UnifiedToggleInputPixelSurface.addressBar.rawValue, "source": "file_picker"]
            )
            attachmentsStripView?.addAttachment(.invalidFile(
                UnifiedToggleInputInvalidFileAttachment(
                    id: fileAttachment.id,
                    fileName: fileAttachment.fileName,
                    mimeType: fileAttachment.mimeType,
                    fileSizeBytes: fileAttachment.fileSizeBytes,
                    validationMessage: validationError.message,
                    sourceURL: sourceURL
                )
            ))
            return
        }

        DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputFileAttached, withAdditionalParameters: ["surface": UnifiedToggleInputPixelSurface.addressBar.rawValue, "source": "file_picker"])
        attachmentsStripView?.addAttachment(.file(fileAttachment))
    }

    private func addInvalidFileAttachment(
        metadata: UnifiedToggleInputAttachmentPresenter.FileMetadata,
        validationMessage: String
    ) {
        let reason: UTIAttachmentPolicy.FileValidationFailureReason
        if let metadataError = attachmentPolicy.fileMetadataValidationError(
            mimeType: metadata.mimeType,
            fileSizeBytes: metadata.fileSizeBytes
        ) {
            reason = metadataError.reason
        } else if validationMessage == UserText.aiChatAttachmentFileUnreadable {
            reason = .unreadable
        } else {
            reason = .other
        }
        DailyPixel.fireDailyAndCount(
            pixel: .unifiedToggleInputFileValidationFailed,
            withAdditionalParameters: ["reason": reason.rawValue, "surface": UnifiedToggleInputPixelSurface.addressBar.rawValue, "source": "file_picker"]
        )
        attachmentsStripView?.addAttachment(.invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                fileName: metadata.fileName,
                mimeType: metadata.mimeType,
                fileSizeBytes: metadata.fileSizeBytes ?? 0,
                validationMessage: validationMessage,
                sourceURL: metadata.url
            )
        ))
    }

    private func removeUnsupportedAttachmentsForSelectedModel() {
        guard store.selectedModel != nil else { return }
        let policy = attachmentPolicy
        let unsupported = currentAttachments.filter { policy.isAttachmentSupported($0) == false }
        unsupported.forEach { attachmentsStripView?.removeAttachment(id: $0.id) }
    }
}
