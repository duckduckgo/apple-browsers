//
//  UTIAttachmentController.swift
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

/// Owns the omnibar UTI's attachment surface: the add / remove / clear write path, the invalid-file
/// recovery lifecycle (`invalidAttachmentRecoveryTasks`), the validation-banner state, the attach
/// button presentation + menu, submit-time validation, and the paste-to-attach flow. Owns the
/// `UnifiedToggleInputAttachmentPresenter` (pickers) and `UnifiedToggleInputPasteHandler` (paste
/// orchestration); rebuilds the shared `UTIAttachmentPolicy` and reads model capabilities live off
/// the coordinator (never captured), reaching it only through `Environment`, the view mutations in
/// `ViewSurface`, and the `Callbacks`. The attachment array itself stays on the view controller and
/// per-tab persistence stays coordinator-side (via `onDraftChanged`).
@MainActor
final class UTIAttachmentController {

    /// The attachment-bar reads + mutations the controller drives on the input view.
    struct ViewSurface {
        let currentAttachments: () -> [UnifiedToggleInputAttachment]
        let isGenerating: () -> Bool
        let addAttachment: (UnifiedToggleInputAttachment) -> Void
        let removeAttachment: (UUID) -> Void
        let removeAllAttachments: () -> Void
        let replaceAttachment: (UUID, UnifiedToggleInputAttachment) -> Void
        let showValidationError: (String) -> Void
        let clearValidationError: () -> Void
        let setImageButtonHidden: (Bool) -> Void
        let setImageButtonEnabled: (Bool) -> Void
        let setAttachmentMenu: (UIMenu?) -> Void
    }

    /// Coordinator / model state read live at call time (never captured). `policy` is rebuilt per read
    /// so it always reflects the current model + pending attachments.
    struct Environment {
        let policy: () -> UTIAttachmentPolicy
        let inputMode: () -> TextEntryMode
        /// True while the native input is editing an existing message. Editing supports removing
        /// attachments only, so the add-attachment control is hidden.
        let isEditing: () -> Bool
        let pixelSurface: () -> UnifiedToggleInputPixelSurface
        let isContextualChatState: () -> Bool
        let supportsImageUpload: () -> Bool
        let supportedFileTypes: () -> [String]
        let hasSelectedModel: () -> Bool
        let attachmentLimits: () -> AIChatAttachmentTierLimits?
        let currentTabUID: () -> TabUID?
        let isPageContextAttachable: () -> Bool?
        let pageContextAttachHandler: () -> (() -> Void)?
        let presenterViewController: () -> UIViewController?
    }

    /// Coordinator-owned effects an attachment mutation triggers.
    struct Callbacks {
        let onDraftChanged: () -> Void
        let onExpandIfNeeded: () -> Void
        let updateFloatingReturnKey: () -> Void
    }

    let pasteHandler = UnifiedToggleInputPasteHandler()

    private let pixelReporter: UTIPixelReporter
    private let view: ViewSurface
    private let environment: Environment
    private let callbacks: Callbacks
    private let presenter = UnifiedToggleInputAttachmentPresenter()

    private var invalidAttachmentRecoveryTasks: [UUID: Task<Void, Never>] = [:]
    /// A limit/rejection banner not tied to a specific attachment (image-over-limit, paste rejection). Held so an async attachment/model re-sync can't clear it — `syncValidationError` falls back to this.
    private var transientValidationMessage: String?
    /// Bumped on New Chat so an in-flight paste from the previous conversation is dropped even within the same tab.
    private var pasteConversationToken = UUID()

    init(pixelReporter: UTIPixelReporter,
         view: ViewSurface,
         environment: Environment,
         callbacks: Callbacks) {
        self.pixelReporter = pixelReporter
        self.view = view
        self.environment = environment
        self.callbacks = callbacks
        wirePresenter()
        pasteHandler.delegate = self
    }

    private func wirePresenter() {
        presenter.pixelSurfaceProvider = { [weak self] in
            self?.environment.pixelSurface() ?? .addressBar
        }
        presenter.onExpandIfNeeded = { [weak self] in
            self?.callbacks.onExpandIfNeeded()
        }
        presenter.onImagePicked = { [weak self] image, fileName in
            self?.addImageAttachment(image: image, fileName: fileName)
        }
        presenter.onFilePicked = { [weak self] attachment, metadata in
            self?.addFileAttachment(attachment, sourceURL: metadata.url)
        }
        presenter.onFileValidationFailed = { [weak self] message, metadata in
            guard let self else { return }
            let reason: UTIAttachmentPolicy.FileValidationFailureReason
            if let metadataError = self.environment.policy()
                .fileMetadataValidationError(mimeType: metadata.mimeType, fileSizeBytes: metadata.fileSizeBytes) {
                reason = metadataError.reason
            } else if message == UserText.aiChatAttachmentFileUnreadable {
                reason = .unreadable
            } else {
                reason = .other
            }
            self.pixelReporter.reportFileValidationFailed(reason: reason, source: "file_picker")
            self.addInvalidFileAttachment(metadata: metadata, validationMessage: message)
        }
        presenter.fileMetadataValidationMessage = { [weak self] metadata in
            self?.environment.policy().fileMetadataValidationError(mimeType: metadata.mimeType, fileSizeBytes: metadata.fileSizeBytes)?.message
        }
    }

    // MARK: - Image / file limits

    var allowedFileUTTypes: [UTType] {
        environment.supportedFileTypes().compactMap(Self.contentType(for:))
    }

    private var canPresentFilePicker: Bool {
        environment.policy().canAttachFiles && !allowedFileUTTypes.isEmpty
    }

    // MARK: - Write model

    func addImageAttachment(image: UIImage, fileName: String) {
        guard environment.policy().canAttachImages else { return }
        let attachment = UnifiedToggleInputAttachment.image(AIChatImageAttachment(image: image, fileName: fileName))
        view.addAttachment(attachment)
        callbacks.onDraftChanged()
        clearValidationErrorIfPossible()
        updateAttachButtonPresentation()
    }

    func addFileAttachment(_ fileAttachment: AIChatFileAttachment, sourceURL: URL? = nil, source: String = "file_picker") {
        if let validationError = environment.policy().fileValidationError(for: fileAttachment) {
            pixelReporter.reportFileValidationFailed(reason: validationError.reason, source: source)
            view.addAttachment(.invalidFile(
                UnifiedToggleInputInvalidFileAttachment(
                    id: fileAttachment.id,
                    fileName: fileAttachment.fileName,
                    mimeType: fileAttachment.mimeType,
                    fileSizeBytes: fileAttachment.fileSizeBytes,
                    validationMessage: validationError.message,
                    sourceURL: sourceURL
                )
            ))
            presentValidationError(validationError.message)
            callbacks.onDraftChanged()
            updateAttachButtonPresentation()
            return
        }

        pixelReporter.reportFileAttached(source: source)
        view.addAttachment(.file(fileAttachment))
        callbacks.onDraftChanged()
        clearValidationErrorIfPossible()
        updateAttachButtonPresentation()
    }

    func removeAttachment(id: UUID) {
        invalidAttachmentRecoveryTasks[id]?.cancel()
        invalidAttachmentRecoveryTasks[id] = nil
        view.removeAttachment(id)
        transientValidationMessage = nil
        callbacks.onDraftChanged()
        syncValidationErrorForCurrentMode()
        updateAttachButtonPresentation()
    }

    func clearAttachments() {
        transientValidationMessage = nil
        guard !view.currentAttachments().isEmpty else {
            view.clearValidationError()
            updateAttachButtonPresentation()
            return
        }
        cancelRecoveryTasks()
        view.removeAllAttachments()
        view.clearValidationError()
        callbacks.onDraftChanged()
        updateAttachButtonPresentation()
    }

    /// Repopulates the bar from a tab's persisted attachments (tab activation). Drops any in-flight
    /// recovery + the transient banner (which belonged to the previous tab's live paste).
    func replaceAllAttachments(with attachments: [UnifiedToggleInputAttachment]) {
        cancelRecoveryTasks()
        view.removeAllAttachments()
        attachments.forEach(view.addAttachment)
        transientValidationMessage = nil
        syncValidationErrorForCurrentMode()
    }

    func resetPasteConversation() {
        pasteConversationToken = UUID()
    }

    private func addInvalidFileAttachment(
        metadata: UnifiedToggleInputAttachmentPresenter.FileMetadata,
        validationMessage: String
    ) {
        view.addAttachment(.invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                fileName: metadata.fileName,
                mimeType: metadata.mimeType,
                fileSizeBytes: metadata.fileSizeBytes ?? 0,
                validationMessage: validationMessage,
                sourceURL: metadata.url
            )
        ))
        callbacks.onDraftChanged()
        updateAttachButtonPresentation()
        presentValidationError(validationMessage)
    }

    // MARK: - Invalid-attachment recovery

    func revalidateInvalidAttachmentsForSelectedModel() {
        var didChange = false

        for attachment in view.currentAttachments() {
            guard case .invalidFile(let invalidAttachment) = attachment else { continue }
            didChange = revalidateInvalidAttachment(invalidAttachment) || didChange
        }

        guard didChange else { return }
        finishRevalidation()
    }

    @discardableResult
    private func revalidateInvalidAttachment(_ attachment: UnifiedToggleInputInvalidFileAttachment) -> Bool {
        if let validationMessage = metadataValidationMessage(for: attachment) {
            invalidAttachmentRecoveryTasks[attachment.id]?.cancel()
            invalidAttachmentRecoveryTasks[attachment.id] = nil
            return replaceInvalidAttachment(attachment, validationMessage: validationMessage)
        }

        guard attachment.sourceURL != nil else {
            return false
        }

        recoverInvalidAttachmentFromSourceURL(attachment)
        return false
    }

    private func recoverInvalidAttachmentFromSourceURL(_ attachment: UnifiedToggleInputInvalidFileAttachment) {
        guard invalidAttachmentRecoveryTasks[attachment.id] == nil,
              let metadata = fileMetadata(for: attachment) else { return }

        let attachmentID = attachment.id
        invalidAttachmentRecoveryTasks[attachmentID] = Task.detached(priority: .userInitiated) { [weak self] in
            let fileAttachment = UnifiedToggleInputAttachmentPresenter.recoverFileAttachment(from: metadata, id: attachmentID)
            guard !Task.isCancelled else { return }
            await self?.completeInvalidAttachmentRecovery(id: attachmentID, fileAttachment: fileAttachment)
        }
    }

    private func completeInvalidAttachmentRecovery(id: UUID, fileAttachment: AIChatFileAttachment?) {
        invalidAttachmentRecoveryTasks[id] = nil
        guard let attachment = view.currentAttachments().first(where: { $0.id == id }),
              case .invalidFile(let invalidAttachment) = attachment else { return }

        let didChange: Bool
        if let validationMessage = metadataValidationMessage(for: invalidAttachment) {
            didChange = replaceInvalidAttachment(invalidAttachment, validationMessage: validationMessage)
        } else if let fileAttachment {
            didChange = applyRecoveredFileAttachment(fileAttachment, for: invalidAttachment)
        } else {
            didChange = replaceInvalidAttachment(invalidAttachment, validationMessage: UserText.aiChatAttachmentFileUnreadable)
        }

        guard didChange else { return }
        finishRevalidation()
    }

    @discardableResult
    private func applyRecoveredFileAttachment(
        _ fileAttachment: AIChatFileAttachment,
        for attachment: UnifiedToggleInputInvalidFileAttachment
    ) -> Bool {
        if let validationMessage = environment.policy().fileValidationMessage(for: fileAttachment) {
            return replaceInvalidAttachment(attachment, validationMessage: validationMessage)
        }

        view.replaceAttachment(attachment.id, .file(fileAttachment))
        return true
    }

    @discardableResult
    private func replaceInvalidAttachment(
        _ attachment: UnifiedToggleInputInvalidFileAttachment,
        validationMessage: String
    ) -> Bool {
        guard validationMessage != attachment.validationMessage else { return false }
        view.replaceAttachment(
            attachment.id,
            invalidFileAttachment(from: attachment, validationMessage: validationMessage)
        )
        return true
    }

    private func finishRevalidation() {
        callbacks.onDraftChanged()
        updateAttachButtonPresentation()
        callbacks.updateFloatingReturnKey()
        syncValidationErrorForCurrentMode()
    }

    private func invalidFileAttachment(
        from attachment: UnifiedToggleInputInvalidFileAttachment,
        validationMessage: String
    ) -> UnifiedToggleInputAttachment {
        .invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                id: attachment.id,
                fileName: attachment.fileName,
                mimeType: attachment.mimeType,
                fileSizeBytes: attachment.fileSizeBytes,
                validationMessage: validationMessage,
                sourceURL: attachment.sourceURL
            )
        )
    }

    private func metadataValidationMessage(for attachment: UnifiedToggleInputInvalidFileAttachment) -> String? {
        environment.policy().fileMetadataValidationError(
            mimeType: attachment.mimeType,
            fileSizeBytes: attachment.fileSizeBytes > 0 ? attachment.fileSizeBytes : nil
        )?.message
    }

    private func fileMetadata(for attachment: UnifiedToggleInputInvalidFileAttachment) -> UnifiedToggleInputAttachmentPresenter.FileMetadata? {
        guard let sourceURL = attachment.sourceURL else { return nil }
        return UnifiedToggleInputAttachmentPresenter.FileMetadata(
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            fileSizeBytes: attachment.fileSizeBytes > 0 ? attachment.fileSizeBytes : nil,
            url: sourceURL
        )
    }

    func cancelRecoveryTasks() {
        invalidAttachmentRecoveryTasks.values.forEach { $0.cancel() }
        invalidAttachmentRecoveryTasks.removeAll()
    }

    func removeUnsupportedAttachmentsForSelectedModel() {
        guard environment.hasSelectedModel() else { return }
        let policy = environment.policy()
        let unsupportedAttachments = view.currentAttachments().filter { attachment in
            policy.isAttachmentSupported(attachment) == false
        }
        unsupportedAttachments.forEach { attachment in
            invalidAttachmentRecoveryTasks[attachment.id]?.cancel()
            invalidAttachmentRecoveryTasks[attachment.id] = nil
            view.removeAttachment(attachment.id)
        }
        revalidateInvalidAttachmentsForSelectedModel()
        syncValidationErrorForCurrentMode()
    }

    // MARK: - Attach button + menu

    func makeAttachmentMenu() -> UIMenu? {
        // Disable "Ask about page" for non-attachable pages (blocklisted media / special page).
        let canAttachPageContext = environment.isContextualChatState() && (environment.isPageContextAttachable() ?? true)
        let pageContextActionHandler = canAttachPageContext ? environment.pageContextAttachHandler() : nil
        let policy = environment.policy()
        return presenter.makeAttachmentMenu(
            presenterProvider: { [weak self] in
                self?.environment.presenterViewController()
            },
            photoSelectionLimit: policy.canAttachImages ? policy.remainingImagesForPicker : 0,
            canAttachFile: canPresentFilePicker,
            allowedFileTypes: allowedFileUTTypes,
            showsPageContextAction: environment.isContextualChatState(),
            pageContextActionHandler: pageContextActionHandler
        )
    }

    func updateAttachButtonPresentation() {
        // Editing an existing message only allows removing attachments, so hide the add control.
        if environment.isEditing() {
            view.setImageButtonHidden(true)
            view.setImageButtonEnabled(false)
            view.setAttachmentMenu(nil)
            return
        }
        let policy = environment.policy()
        let supportsPageContextAttachment = environment.isContextualChatState() && environment.pageContextAttachHandler() != nil && (environment.isPageContextAttachable() ?? true)
        let supportsAttachments = environment.supportsImageUpload() || !allowedFileUTTypes.isEmpty || supportsPageContextAttachment
        let hasAvailableAttachmentAction = policy.canAttachImages || canPresentFilePicker || supportsPageContextAttachment
        let canAttachMore = hasAvailableAttachmentAction && !view.isGenerating()
        view.setImageButtonHidden(!supportsAttachments)
        view.setImageButtonEnabled(canAttachMore)
        view.setAttachmentMenu(supportsAttachments && canAttachMore ? makeAttachmentMenu() : nil)
    }

    // MARK: - Validation banner

    func presentValidationError(_ message: String) {
        view.showValidationError(message)
    }

    /// Shows a limit/rejection banner that survives async re-syncs, unlike an attachment-derived one which `syncValidationError` recomputes from the current attachments.
    private func presentTransientValidationError(_ message: String) {
        transientValidationMessage = message
        view.showValidationError(message)
    }

    func submissionValidationMessage(for text: String, mode: TextEntryMode) -> String? {
        guard mode == .aiChat else { return nil }

        let policy = environment.policy()
        if let validationMessage = policy.imageSubmissionValidationMessage() {
            return validationMessage
        }

        if let validationMessage = policy.fileSubmissionValidationMessage() {
            return validationMessage
        }

        return policy.promptValidationMessage(for: text)
    }

    private func syncValidationError() {
        if let validationMessage = view.currentAttachments().compactMap(\.validationMessage).first ?? transientValidationMessage {
            view.showValidationError(validationMessage)
        } else {
            view.clearValidationError()
        }
    }

    func syncValidationErrorForCurrentMode() {
        guard environment.inputMode() == .aiChat else {
            transientValidationMessage = nil
            view.clearValidationError()
            return
        }

        syncValidationError()
    }

    func clearValidationErrorIfPossible() {
        guard view.currentAttachments().contains(where: \.isInvalid) == false else { return }
        transientValidationMessage = nil
        view.clearValidationError()
    }

    private static func contentType(for mimeType: String) -> UTType? {
        UTType(mimeType: mimeType)
    }
}

// MARK: - Paste-to-Attach

extension UTIAttachmentController: UnifiedToggleInputPasteDelegate {

    /// Keys off model capability (not remaining room) so an over-limit paste is consumed and reported here rather than falling through to UIKit's inline-image insert. Text types are excluded so a copied string always pastes as text (text files remain picker-only); files are only offered when the model's attachment limits are known, so the loader can preflight sizes.
    var pasteAttachmentSupport: UnifiedToggleInputPasteSupport {
        let policy = environment.policy()
        let limits = environment.attachmentLimits()
        let fileTypes = limits == nil ? [] : allowedFileUTTypes.filter { !$0.conforms(to: .text) }
        return UnifiedToggleInputPasteSupport(
            isEnabled: environment.inputMode() == .aiChat && !view.isGenerating(),
            acceptsImages: environment.supportsImageUpload(),
            fileTypes: fileTypes,
            maxImageCount: environment.supportsImageUpload() ? policy.remainingImagesForPicker : nil,
            maxFileSizeBytes: limits.map { $0.files.maxFileSizeMB * 1_048_576 },
            remainingFileCount: fileTypes.isEmpty ? nil : policy.remainingFilesInConversation,
            remainingTotalFileBytes: fileTypes.isEmpty ? nil : policy.remainingFileSizeBytes
        )
    }

    /// Identifies the tab AND the conversation, so a paste in flight is dropped if the user starts a New Chat in the same tab (not just on a tab switch).
    var pasteContextIdentity: String? {
        "\(environment.currentTabUID() ?? "-"):\(pasteConversationToken.uuidString)"
    }

    func imageCapacityMessage() -> String? {
        environment.policy().imageCapacityValidationMessage()
    }

    func pasteWillBeginExpandingIfNeeded() {
        callbacks.onExpandIfNeeded()
    }

    @discardableResult
    func addPastedImage(_ image: UIImage, fileName: String) -> Bool {
        guard environment.policy().canAttachImages else { return false }
        addImageAttachment(image: image, fileName: fileName)
        pixelReporter.reportImageAttached(source: "paste")
        return true
    }

    func addPastedFile(_ file: AIChatFileAttachment) {
        addFileAttachment(file, source: "paste")
    }

    /// Reports a load-time-rejected paste as an error banner (no chip, no revalidation) using the reason the loader recorded, so the message and pixel reflect why it was actually rejected.
    func reportRejectedPaste(reason: PasteRejectionReason) {
        let files = environment.attachmentLimits()?.files
        let message: String
        let pixelReason: String
        switch reason {
        case .fileTooLarge:
            message = UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: files?.maxFileSizeMB ?? 0)
            pixelReason = "size_exceeded"
        case .filesExceedTotalSize:
            let maxTotalMB = files.map { Int(ceil(Double($0.maxTotalFileSizeBytes) / 1_048_576)) } ?? 0
            message = UserText.aiChatAttachmentFilesExceedTotalSizeLimit(maxTotalFileSizeMB: maxTotalMB)
            pixelReason = "size_exceeded"
        case .fileCountLimit:
            message = UserText.aiChatAttachmentFileCountLimit(maxFilesPerConversation: files?.maxPerConversation ?? 0)
            pixelReason = "count_exceeded"
        }
        pixelReporter.reportFileValidationFailed(reason: pixelReason, source: "paste")
        presentTransientValidationError(message)
    }

    func presentPasteError(_ message: String) {
        presentTransientValidationError(message)
    }
}
