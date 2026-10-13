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
import PixelKit

@MainActor
final class IPadOmnibarDraft {
    var text = ""
    var attachments: [UnifiedToggleInputAttachment] = []
    private(set) var generation = UUID()
    private(set) var isValid = true

    func clear() {
        text = ""
        attachments = []
        generation = UUID()
    }

    func invalidate() {
        clear()
        isValid = false
    }
}

@MainActor
final class IPadOmnibarAttachmentController {

    private let store: UTIModelStore
    private let keepsUnavailableAttachmentButtonVisible: Bool
    private let presenter = UnifiedToggleInputAttachmentPresenter()
    private let fallbackDraft = IPadOmnibarDraft()
    private weak var boundDraft: IPadOmnibarDraft?
    private var isRenderingDraft = false

    private var currentDraft: IPadOmnibarDraft { boundDraft ?? fallbackDraft }

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

    init(store: UTIModelStore, keepsUnavailableAttachmentButtonVisible: Bool = false) {
        self.store = store
        self.keepsUnavailableAttachmentButtonVisible = keepsUnavailableAttachmentButtonVisible

        presenter.pickerCallbacksProvider = { [weak self] in
            self?.makePickerCallbacks() ?? .init()
        }
    }

    func bindDraft(_ draft: IPadOmnibarDraft) {
        boundDraft = draft
        if store.selectedModel != nil {
            let policy = attachmentPolicy
            draft.attachments.removeAll { !policy.isAttachmentSupported($0) }
        }
        renderDraft()
    }

    func handleAttachmentsChanged() {
        guard !isRenderingDraft, currentDraft.isValid else { return }
        currentDraft.attachments = attachmentsStripView?.attachments ?? []
    }

    func makePickerCallbacks() -> UnifiedToggleInputAttachmentPresenter.PickerCallbacks {
        let draft = currentDraft
        let generation = draft.generation
        let model = store.selectedModel
        let limits = store.attachmentLimits
        let policy = { [weak self, weak draft] in
            if let self, let draft, self.currentDraft === draft {
                return self.attachmentPolicy
            }
            return UTIAttachmentPolicy(attachmentLimits: limits, attachmentUsage: nil,
                                       pendingAttachments: draft?.attachments ?? [], model: model)
        }
        return .init(
            onExpandIfNeeded: { [weak self, weak draft] in
                guard let self, let draft, draft.isValid, draft.generation == generation,
                      self.currentDraft === draft else { return }
                self.onExpandRequested?()
            },
            onImagePicked: { [weak self, weak draft] image, fileName in
                guard let draft, draft.isValid, draft.generation == generation,
                      policy().canAttachImages else { return }
                self?.addAttachment(.image(AIChatImageAttachment(image: image, fileName: fileName)), to: draft)
            },
            onFilePicked: { [weak self, weak draft] attachment, metadata in
                guard let draft, draft.isValid, draft.generation == generation else { return }
                self?.addFileAttachment(attachment, sourceURL: metadata.url, to: draft, policy: policy())
            },
            onFileValidationFailed: { [weak self, weak draft] message, metadata in
                guard let draft, draft.isValid, draft.generation == generation else { return }
                self?.addInvalidFileAttachment(metadata: metadata, validationMessage: message, to: draft, policy: policy())
            },
            fileMetadataValidationMessage: { metadata in
                policy().fileMetadataValidationError(mimeType: metadata.mimeType, fileSizeBytes: metadata.fileSizeBytes)?.message
            }
        )
    }

    private func renderDraft() {
        isRenderingDraft = true
        defer { isRenderingDraft = false }
        attachmentsStripView?.removeAllAttachments()
        currentDraft.attachments.forEach { attachmentsStripView?.addAttachment($0) }
    }

    private func addAttachment(_ attachment: UnifiedToggleInputAttachment, to draft: IPadOmnibarDraft) {
        draft.attachments.append(attachment)
        guard currentDraft === draft else { return }
        isRenderingDraft = true
        defer { isRenderingDraft = false }
        attachmentsStripView?.addAttachment(attachment)
    }

    // MARK: - Availability

    /// Whether the selected model accepts any attachment kind (so the button should be shown at all).
    var isAttachButtonAvailable: Bool {
        store.selectedModelSupportsImageUpload || !allowedFileUTTypes.isEmpty
    }

    var isAttachButtonVisible: Bool {
        isAttachButtonAvailable || (store.selectedModel != nil && keepsUnavailableAttachmentButtonVisible)
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

    func resetSelection() {
        currentDraft.clear()
        renderDraft()
    }

    // MARK: - Private

    private var currentAttachments: [UnifiedToggleInputAttachment] {
        if boundDraft == nil, !isRenderingDraft {
            fallbackDraft.attachments = attachmentsStripView?.attachments ?? []
        }
        return currentDraft.attachments
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

    private func addFileAttachment(_ fileAttachment: AIChatFileAttachment, sourceURL: URL?, to draft: IPadOmnibarDraft, policy: UTIAttachmentPolicy) {
        if let validationError = policy.fileValidationError(for: fileAttachment) {
            PixelKit.fire(Pixel.Event.unifiedToggleInputFileValidationFailed,
                          frequency: .dailyAndCount,
                          options: .parameters(["reason": validationError.reason.rawValue, "surface": UnifiedToggleInputPixelSurface.addressBar.rawValue, "source": "file_picker"]))
            addAttachment(.invalidFile(
                UnifiedToggleInputInvalidFileAttachment(
                    id: fileAttachment.id,
                    fileName: fileAttachment.fileName,
                    mimeType: fileAttachment.mimeType,
                    fileSizeBytes: fileAttachment.fileSizeBytes,
                    validationMessage: validationError.message,
                    sourceURL: sourceURL
                )
            ), to: draft)
            return
        }

        PixelKit.fire(Pixel.Event.unifiedToggleInputFileAttached, frequency: .dailyAndCount, options: .parameters(["surface": UnifiedToggleInputPixelSurface.addressBar.rawValue, "source": "file_picker"]))
        addAttachment(.file(fileAttachment), to: draft)
    }

    private func addInvalidFileAttachment(
        metadata: UnifiedToggleInputAttachmentPresenter.FileMetadata,
        validationMessage: String,
        to draft: IPadOmnibarDraft,
        policy: UTIAttachmentPolicy
    ) {
        let reason: UTIAttachmentPolicy.FileValidationFailureReason
        if let metadataError = policy.fileMetadataValidationError(
            mimeType: metadata.mimeType,
            fileSizeBytes: metadata.fileSizeBytes
        ) {
            reason = metadataError.reason
        } else if validationMessage == UserText.aiChatAttachmentFileUnreadable {
            reason = .unreadable
        } else {
            reason = .other
        }
        PixelKit.fire(Pixel.Event.unifiedToggleInputFileValidationFailed,
                      frequency: .dailyAndCount,
                      options: .parameters(["reason": reason.rawValue, "surface": UnifiedToggleInputPixelSurface.addressBar.rawValue, "source": "file_picker"]))
        addAttachment(.invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                fileName: metadata.fileName,
                mimeType: metadata.mimeType,
                fileSizeBytes: metadata.fileSizeBytes ?? 0,
                validationMessage: validationMessage,
                sourceURL: metadata.url
            )
        ), to: draft)
    }

    private func removeUnsupportedAttachmentsForSelectedModel() {
        guard store.selectedModel != nil else { return }
        let policy = attachmentPolicy
        let unsupported = currentAttachments.filter { policy.isAttachmentSupported($0) == false }
        currentDraft.attachments.removeAll { attachment in unsupported.contains { $0.id == attachment.id } }
        isRenderingDraft = true
        defer { isRenderingDraft = false }
        unsupported.forEach { attachmentsStripView?.removeAttachment(id: $0.id) }
    }
}
