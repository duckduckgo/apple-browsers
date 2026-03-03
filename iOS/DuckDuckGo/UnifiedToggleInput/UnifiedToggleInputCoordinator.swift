//
//  UnifiedToggleInputCoordinator.swift
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
import Combine
import os.log
import UIKit

// MARK: - State Types

enum InputTextState {
    case empty
    case prefilledSelected
    case userTyped
}

enum InputDisplayState {
    case hidden
    case collapsed
    case expanded
}

enum UnifiedToggleInputIntent {
    case showCollapsed
    case showExpanded
    case hide
}

// MARK: - Coordinator

/// Pure state machine managing the unified toggle input lifecycle and FE bridge via `AIChatInputBoxHandling`.
/// Drives the view controller through `UnifiedToggleInputViewControllerDelegate` and emits
/// `UnifiedToggleInputIntent`s for MainVC to manage container-level layout (visibility, keyboard constraints).
///
/// Does not access the view hierarchy directly — all UI manipulation goes through the view controller.
final class UnifiedToggleInputCoordinator: AIChatInputBoxHandling {

    // MARK: - AIChatInputBoxHandling

    let didPressFireButton = PassthroughSubject<Void, Never>()
    let didPressNewChatButton = PassthroughSubject<Void, Never>()
    let didSubmitPrompt = PassthroughSubject<String, Never>()
    let didSubmitQuery = PassthroughSubject<String, Never>()
    let didPressStopGeneratingButton = PassthroughSubject<Void, Never>()

    var aiChatStatusPublisher: Published<AIChatStatusValue>.Publisher { $aiChatStatus }
    var aiChatInputBoxVisibilityPublisher: Published<AIChatInputBoxVisibility>.Publisher { $aiChatInputBoxVisibility }

    @Published var aiChatStatus: AIChatStatusValue = .unknown
    @Published var aiChatInputBoxVisibility: AIChatInputBoxVisibility = .unknown

    // MARK: - Properties

    /// The managed view controller. Access for installation only — query coordinator properties for state.
    private(set) var viewController: UnifiedToggleInputViewController
    weak var delegate: UnifiedToggleInputDelegate?

    private(set) var displayState: InputDisplayState = .hidden
    private(set) var textState: InputTextState = .empty
    private(set) var inputMode: TextEntryMode = .aiChat

    var currentText: String { viewController.text }
    var hasActiveChat: Bool { boundUserScript != nil }

    private weak var boundUserScript: AIChatUserScript?

    private let intentSubject = PassthroughSubject<UnifiedToggleInputIntent, Never>()
    var intentPublisher: AnyPublisher<UnifiedToggleInputIntent, Never> {
        intentSubject.eraseToAnyPublisher()
    }

    private let textChangeSubject = PassthroughSubject<String, Never>()
    var textChangePublisher: AnyPublisher<String, Never> {
        textChangeSubject.eraseToAnyPublisher()
    }

    // MARK: - Model Picker

    private let modelsService: AIChatModelsProviding
    private var preferences: AIChatPreferencesPersisting
    private var models: [AIChatModel] = []
    private var modelsFetchTask: Task<Void, Never>?

    private var selectedModelId: String? {
        preferences.selectedModelId ?? models.first(where: { $0.entityHasAccess })?.id
    }

    private var selectedModelSupportsImageUpload: Bool {
        guard !models.isEmpty else { return true }
        return models.first(where: { $0.id == (selectedModelId ?? "") })?.supportsImageUpload ?? true
    }

    // MARK: - Attachments

    private(set) var pendingAttachments: [AIChatImageAttachment] = []

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor()
    ) {
        self.modelsService = modelsService
        self.preferences = preferences
        viewController = UnifiedToggleInputViewController()
        viewController.delegate = self
        observeAIChatStatus()
        fetchModels()
    }

    // MARK: - Tab Binding

    func bindToTab(_ userScript: AIChatUserScript) {
        guard boundUserScript !== userScript else { return }
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = userScript
        userScript.inputBoxHandler = self
    }

    func unbind() {
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = nil
        resetInputState()
    }

    // MARK: - Display State Management

    func showCollapsed() {
        displayState = .collapsed
        viewController.setExpanded(false, animated: false)
        viewController.deactivateInput()
        intentSubject.send(.showCollapsed)
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat) {
        displayState = .expanded
        self.inputMode = inputMode
        viewController.setInputMode(inputMode, animated: false)

        if let prefilledText, !prefilledText.isEmpty {
            viewController.text = prefilledText
            textState = .prefilledSelected
        }

        viewController.setExpanded(true, animated: false)
        intentSubject.send(.showExpanded)
        viewController.activateInput()

        if textState == .prefilledSelected {
            DispatchQueue.main.async { [weak self] in
                self?.viewController.selectAllText()
            }
        }
    }

    func hide() {
        displayState = .hidden
        viewController.deactivateInput()
        viewController.setExpanded(false, animated: false)
        intentSubject.send(.hide)
    }

    // MARK: - Attachment Management

    func addAttachment(_ attachment: AIChatImageAttachment) {
        guard pendingAttachments.count < 4 else { return }
        pendingAttachments.append(attachment)
        viewController.setAttachments(pendingAttachments)
        viewController.updateAttachButtonVisibility(supportsImageUpload: selectedModelSupportsImageUpload && pendingAttachments.count < 4)
    }

    // MARK: - Private

    private func observeAIChatStatus() {
        $aiChatStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                let isStreaming = status == .loading || status == .streaming
                self?.viewController.setStopMode(isStreaming)
            }
            .store(in: &cancellables)
    }

    private func fetchModels() {
        modelsFetchTask?.cancel()
        modelsFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let remoteModels = try await modelsService.fetchModels()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.models = remoteModels.map { AIChatModel(remoteModel: $0) }
                    self.updateModelChip()
                    self.viewController.setModelMenu(self.makeModelMenu())
                    self.viewController.updateAttachButtonVisibility(supportsImageUpload: self.selectedModelSupportsImageUpload && self.pendingAttachments.count < 4)
                }
            } catch {
                Logger.aiChat.error("Failed to fetch models: \(error)")
            }
        }
    }

    private func updateModelChip() {
        let name = models.first(where: { $0.id == (selectedModelId ?? "") })?.name ?? selectedModelId ?? ""
        viewController.setModelChipName(name)
    }

    private func makeModelMenu() -> UIMenu {
        let actions = models.map { model in
            let isSelected = model.id == (selectedModelId ?? "")
            let action = UIAction(
                title: model.name,
                image: model.menuIcon,
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                self.preferences.selectedModelId = model.id
                self.updateModelChip()
                self.viewController.setModelMenu(self.makeModelMenu())
                self.viewController.updateAttachButtonVisibility(supportsImageUpload: self.selectedModelSupportsImageUpload && self.pendingAttachments.count < 4)
            }
            return action
        }
        return UIMenu(children: actions)
    }

    private func nativePromptImages(from attachments: [AIChatImageAttachment]) -> [AIChatNativePrompt.NativePromptImage]? {
        guard !attachments.isEmpty else { return nil }
        let images = attachments.compactMap { attachment -> AIChatNativePrompt.NativePromptImage? in
            let resizedImage = Self.resizeIfNeeded(attachment.image, maxDimension: 512)
            guard let data = resizedImage.pngData() else { return nil }
            return AIChatNativePrompt.NativePromptImage(data: data.base64EncodedString(), format: "png")
        }
        return images.isEmpty ? nil : images
    }

    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size

        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        let aspectRatio = size.width / size.height
        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func resetInputState() {
        viewController.text = ""
        textState = .empty
        aiChatStatus = .unknown
        aiChatInputBoxVisibility = .unknown
        pendingAttachments.removeAll()
        viewController.setAttachments([])
        viewController.updateAttachButtonVisibility(supportsImageUpload: selectedModelSupportsImageUpload && pendingAttachments.count < 4)
    }
}

// MARK: - UnifiedToggleInputViewControllerDelegate

extension UnifiedToggleInputCoordinator: UnifiedToggleInputViewControllerDelegate {

    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController) {
        showExpanded(inputMode: .aiChat)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
        vc.text = ""
        textState = .empty

        switch mode {
        case .search:
            delegate?.unifiedToggleInputDidSubmitQuery(text)
            didSubmitQuery.send(text)
        case .aiChat:
            showCollapsed()
            if let script = boundUserScript {
                let images = nativePromptImages(from: pendingAttachments)
                script.submitPrompt(text, images: images, modelId: selectedModelId)
                pendingAttachments.removeAll()
                viewController.setAttachments([])
                viewController.updateAttachButtonVisibility(supportsImageUpload: selectedModelSupportsImageUpload && pendingAttachments.count < 4)
            } else {
                delegate?.unifiedToggleInputDidSubmitPrompt(text)
                pendingAttachments.removeAll()
                viewController.setAttachments([])
                viewController.updateAttachButtonVisibility(supportsImageUpload: selectedModelSupportsImageUpload && pendingAttachments.count < 4)
            }
        }
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String) {
        textState = text.isEmpty ? .empty : .userTyped
        textChangeSubject.send(text)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode) {
        inputMode = mode
    }

    func unifiedToggleInputVCDidTapVoice(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidRequestVoiceSearch()
    }

    func unifiedToggleInputVCDidTapStopGenerating(_ vc: UnifiedToggleInputViewController) {
        didPressStopGeneratingButton.send(())
    }

    func unifiedToggleInputVCDidTapAttach(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidRequestImageAttachment(self)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachmentWithId id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
        viewController.setAttachments(pendingAttachments)
        viewController.updateAttachButtonVisibility(supportsImageUpload: selectedModelSupportsImageUpload && pendingAttachments.count < 4)
    }
}
