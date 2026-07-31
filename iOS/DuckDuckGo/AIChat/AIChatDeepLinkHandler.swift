//
//  AIChatDeepLinkHandler.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Core
import AIChat
import Subscription
import PrivacyConfig
import UIKit

protocol AIChatDeepLinkPresenting: UIViewController {
    /// Whether shared attachments can be handed to the unified input as an editable draft. False
    /// when Duck.ai opens in the modal sheet (no unified input), which keeps the auto-submit lane.
    var supportsAIChatShareDraftDelivery: Bool { get }
    func openAIVoiceChatFromDeepLink()
    func stageAIChatShareDraft(_ draft: AIChatShareDraft)
    func openAIChat(
        _ query: String?,
        autoSend: Bool,
        payload: Any?,
        flowType: AIChatOnboardingFlowType,
        tools: [AIChatRAGTool]?,
        modelId: String?,
        reasoningEffort: AIChatReasoningEffort?,
        images: [AIChatNativePrompt.NativePromptImage]?,
        files: [AIChatNativePrompt.NativePromptFile]?,
        fromDeepLink: Bool
    )
}

/// "Ask Duck.ai" share content staged for injection into the unified input as an editable draft.
struct AIChatShareDraft {

    struct Image {
        let image: UIImage
        let fileName: String
    }

    static let attachmentSource = "share_extension"

    let text: String
    let images: [Image]
    let files: [AIChatFileAttachment]
}

/// What the unified input could not take from a share draft, so the caller can report it.
struct AIChatShareDraftOutcome {
    let rejectedImageCount: Int
    let rejectedFileCount: Int
}

extension AIChatDeepLinkPresenting {

    func openAIChat(fromDeepLink: Bool) {
        openAIChat(
            nil,
            autoSend: false,
            payload: nil,
            flowType: .default,
            tools: nil,
            modelId: nil,
            reasoningEffort: nil,
            images: nil,
            files: nil,
            fromDeepLink: fromDeepLink
        )
    }

    /// Opens AI Chat with content handed over by the "Ask Duck.ai" action extension, prefilled but never auto-submitted.
    func openAIChatFromShare(prompt: String,
                             modelId: String?,
                             images: [AIChatNativePrompt.NativePromptImage]?,
                             files: [AIChatNativePrompt.NativePromptFile]?) {
        openAIChat(
            prompt,
            autoSend: false,
            payload: nil,
            flowType: .default,
            tools: nil,
            modelId: modelId,
            reasoningEffort: nil,
            images: images,
            files: files,
            fromDeepLink: true
        )
    }

}

struct AIChatDeepLinkHandler {

    /// The two lanes the "Ask Duck.ai" action extension uses to hand shared content to the app.
    enum SharePayloadLink: Equatable {
        case inline(prompt: String)
        case token(String)
    }

    private enum Constants {
        static let promptKey = "prompt"
        static let payloadTokenKey = "payloadToken"
        static let typeKey = "type"
        static let reasonKey = "reason"
        static let skippedKey = "skipped"
        static let textType = "text"
        static let attachmentsType = "attachments"
        static let mixedType = "mixed"
        static let payloadUnreadableReason = "payload_unreadable"
        static let imageRejectedReason = "image_unsupported"
        static let fileRejectedReason = "file_unsupported"
        static let modeKey = "mode"
        static let draftMode = "draft"
        static let modelsFetchTimeout: TimeInterval = 5
    }

    private let featureFlagger: FeatureFlagger
    private let aiChatSettings: AIChatSettingsProvider
    private let appSettings: AppSettings

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings) {
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
        self.appSettings = appSettings
    }

    /// Handles AI Chat deep links (text and voice), dismissing any presented modal first.
    func handleDeepLink(_ url: URL, on mainViewController: AIChatDeepLinkPresenting, voiceMode: Bool = false) {
        if voiceMode {
            fireAIVoiceChatPixel(url)
        } else {
            firePixel(url)
        }

        if !voiceMode, let link = Self.sharePayloadLink(from: url) {
            if isShareDeliveryEnabled {
                handleSharePayloadDeepLink(link, on: mainViewController)
                return
            }
            Pixel.fire(pixel: .aiChatShareExtensionDegraded)
        }

        if !voiceMode {
            guard !isAIChatAlreadyPresented(on: mainViewController) else {
                return
            }
        }

        mainViewController.dismiss(animated: true) {
            if voiceMode {
                mainViewController.openAIVoiceChatFromDeepLink()
            } else {
                mainViewController.openAIChat(fromDeepLink: true)
            }
        }
    }

    // MARK: - Share payload delivery

    /// Reads the "Ask Duck.ai" share lane out of a deep link, preferring the token lane when both are present.
    static func sharePayloadLink(from url: URL) -> SharePayloadLink? {
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        if let token = queryItems.first(where: { $0.name == Constants.payloadTokenKey })?.value, !token.isEmpty {
            return .token(token)
        }
        if let prompt = queryItems.first(where: { $0.name == Constants.promptKey })?.value, !prompt.isEmpty {
            return .inline(prompt: prompt)
        }
        return nil
    }

    private var isShareDeliveryEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatTextActions) && aiChatSettings.isAIChatEnabled
    }

    /// A share always carries content, so it delivers unconditionally rather than bailing out on an already-presented chat.
    private func handleSharePayloadDeepLink(_ link: SharePayloadLink, on mainViewController: AIChatDeepLinkPresenting) {
        mainViewController.dismiss(animated: true) {
            switch link {
            case .inline(let prompt):
                var parameters = [Constants.typeKey: Constants.textType]
                if mainViewController.supportsAIChatShareDraftDelivery {
                    parameters[Constants.modeKey] = Constants.draftMode
                    mainViewController.openAIChat(fromDeepLink: true)
                    mainViewController.stageAIChatShareDraft(AIChatShareDraft(text: prompt, images: [], files: []))
                } else {
                    mainViewController.openAIChatFromShare(prompt: prompt, modelId: nil, images: nil, files: nil)
                }
                Pixel.fire(pixel: .aiChatShareExtensionDelivered, withAdditionalParameters: parameters)
            case .token(let token):
                self.deliverPayload(token: token, on: mainViewController)
            }
        }
    }

    private func deliverPayload(token: String, on mainViewController: AIChatDeepLinkPresenting) {
        guard let loaded = AIChatShareInbox.loadPayload(token: token) else {
            Pixel.fire(pixel: .aiChatShareExtensionRejected,
                       withAdditionalParameters: [Constants.reasonKey: Constants.payloadUnreadableReason])
            ActionMessageView.present(
                message: UserText.aiChatShareCouldNotLoad,
                presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom)
            )
            mainViewController.openAIChat(fromDeepLink: true)
            return
        }

        let payload = loaded.payload
        let read = Self.readItems(payload.items, in: loaded.directory)
        AIChatShareInbox.deletePayload(token: token)

        let deliveryType = Self.deliveryType(prompt: payload.prompt, items: payload.items)
        var parameters = [Constants.typeKey: deliveryType]
        if read.skippedCount > 0 {
            parameters[Constants.skippedKey] = String(read.skippedCount)
        }

        guard mainViewController.supportsAIChatShareDraftDelivery else {
            deliverPromptPayload(read: read, prompt: payload.prompt ?? "", parameters: parameters, on: mainViewController)
            return
        }

        parameters[Constants.modeKey] = Constants.draftMode
        mainViewController.openAIChat(fromDeepLink: true)
        mainViewController.stageAIChatShareDraft(Self.draft(prompt: payload.prompt ?? "", items: read.items))
        Pixel.fire(pixel: .aiChatShareExtensionDelivered, withAdditionalParameters: parameters)
    }

    /// Reports what the unified input refused once the draft has been injected.
    static func reportShareDraftOutcome(_ outcome: AIChatShareDraftOutcome) {
        if outcome.rejectedImageCount > 0 {
            Pixel.fire(pixel: .aiChatShareExtensionRejected,
                       withAdditionalParameters: [Constants.reasonKey: Constants.imageRejectedReason])
        }
        if outcome.rejectedFileCount > 0 {
            Pixel.fire(pixel: .aiChatShareExtensionRejected,
                       withAdditionalParameters: [Constants.reasonKey: Constants.fileRejectedReason])
        }
    }

    /// Fallback for the modal Duck.ai presentation (no unified input): prefills the web input, never auto-submits.
    private func deliverPromptPayload(read: ReadItems,
                                      prompt: String,
                                      parameters: [String: String],
                                      on mainViewController: AIChatDeepLinkPresenting) {
        let attachments = Self.nativePromptAttachments(for: read.items)
        Task { @MainActor in
            let modelId = await self.autoSwitchedModelId(for: read.items.map(\.item))

            mainViewController.openAIChatFromShare(
                prompt: prompt,
                modelId: modelId,
                images: attachments.images.isEmpty ? nil : attachments.images,
                files: attachments.files.isEmpty ? nil : attachments.files
            )
            Pixel.fire(pixel: .aiChatShareExtensionDelivered, withAdditionalParameters: parameters)
        }
    }

    struct ReadItem {
        let item: AIChatSharePayload.Item
        let data: Data
    }

    struct ReadItems {
        var items: [ReadItem] = []
        var skippedCount: Int = 0
    }

    /// Reads the staged bytes for each manifest item, rejecting paths that escape the payload
    /// directory and items whose on-disk size exceeds `limit`.
    static func readItems(_ items: [AIChatSharePayload.Item],
                          in directory: URL,
                          limit: Int = AIChatShareInbox.maximumItemByteCount) -> ReadItems {
        var read = ReadItems()
        for item in items {
            let url = directory.appendingPathComponent(item.relativePath)
            guard !item.relativePath.contains("/"), item.relativePath != "..",
                  let byteCount = Self.byteCount(ofFileAt: url), byteCount <= limit,
                  let data = try? Data(contentsOf: url) else {
                read.skippedCount += 1
                continue
            }
            read.items.append(ReadItem(item: item, data: data))
        }
        return read
    }

    private static func byteCount(ofFileAt url: URL) -> Int? {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            return size
        }
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    static func draft(prompt: String, items: [ReadItem]) -> AIChatShareDraft {
        var images = [AIChatShareDraft.Image]()
        var files = [AIChatFileAttachment]()
        for read in items {
            switch read.item.kind {
            case .image:
                guard let image = UIImage(data: read.data) else { continue }
                images.append(AIChatShareDraft.Image(image: image, fileName: read.item.fileName))
            case .file:
                files.append(UnifiedToggleInputAttachmentPresenter.makeFileAttachment(
                    data: read.data,
                    fileName: read.item.fileName,
                    mimeType: read.item.mimeType
                ))
            }
        }
        return AIChatShareDraft(text: prompt, images: images, files: files)
    }

    private struct SharedAttachments {
        var images: [AIChatNativePrompt.NativePromptImage] = []
        var files: [AIChatNativePrompt.NativePromptFile] = []
    }

    private static func nativePromptAttachments(for items: [ReadItem]) -> SharedAttachments {
        var attachments = SharedAttachments()
        for read in items {
            let encoded = read.data.base64EncodedString()
            switch read.item.kind {
            case .image:
                attachments.images.append(.init(data: encoded, format: Self.imageFormat(for: read.item.mimeType)))
            case .file:
                attachments.files.append(.init(data: encoded, fileName: read.item.fileName, mimeType: read.item.mimeType))
            }
        }
        return attachments
    }

    /// Duck.ai expects a bare image format ("png"), not the MIME type the extension staged the file with.
    static func imageFormat(for mimeType: String) -> String {
        mimeType.components(separatedBy: "/").last ?? mimeType
    }

    static func deliveryType(prompt: String?, items: [AIChatSharePayload.Item]) -> String {
        guard !items.isEmpty else { return Constants.textType }
        let hasPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasPrompt ? Constants.mixedType : Constants.attachmentsType
    }

    // MARK: - Model auto-switch

    /// Picks the first accessible model that can take every shared attachment, or nil to keep the current selection.
    @MainActor
    private func autoSwitchedModelId(for items: [AIChatSharePayload.Item]) async -> String? {
        let needsImage = items.contains { $0.kind == .image }
        let fileMimeTypes = Set(items.filter { $0.kind == .file }.map(\.mimeType))
        guard needsImage || !fileMimeTypes.isEmpty else { return nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.modelsFetchTimeout
        let modelsService = AIChatModelsService(
            baseURL: aiChatModelsBaseURL(forChatURL: aiChatSettings.aiChatURL),
            session: URLSession(configuration: configuration)
        )
        let store = UTIModelStore(
            modelsService: modelsService,
            preferences: AIChatPreferencesPersistor(),
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager
        )

        guard let response = try? await modelsService.fetchModels() else { return nil }
        let subscriptionState = await store.resolveSubscriptionState()
        store.models = UTIModelStore.resolveModels(from: response.models, userTier: subscriptionState.userTier)

        guard let pick = Self.model(in: store.models, needsImage: needsImage, fileMimeTypes: fileMimeTypes),
              pick.id != store.persistedModelId else {
            return nil
        }
        return pick.id
    }

    static func model(in models: [AIChatModel], needsImage: Bool, fileMimeTypes: Set<String>) -> AIChatModel? {
        models.first { Self.model($0, supports: needsImage, fileMimeTypes: fileMimeTypes) }
    }

    static func model(_ model: AIChatModel, supports needsImage: Bool, fileMimeTypes: Set<String>) -> Bool {
        guard model.entityHasAccess else { return false }
        guard !needsImage || model.supportsImageUpload else { return false }
        return fileMimeTypes.allSatisfy(model.supportedFileTypes.contains)
    }

    /// Checks if the AIChatViewController is already presented
    private func isAIChatAlreadyPresented(on mainViewController: AIChatDeepLinkPresenting) -> Bool {
        if let presentedVC = mainViewController.presentedViewController as? RoundedPageSheetContainerViewController,
           presentedVC.contentViewController is AIChatViewController {
            return true
        }
        return false
    }

    private func fireAIVoiceChatPixel(_ url: URL) {
        if let source = url.getParameter(named: WidgetSourceType.sourceKey) {
            Pixel.fire(pixel: .voiceEntryPointTapped, withAdditionalParameters: [PixelParameters.source: source])
        }
    }

    func firePixel(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let queryItems = components.queryItems
        if let sourceItem = queryItems?.first(where: { $0.name == WidgetSourceType.sourceKey }) {
            switch sourceItem.value {
            case WidgetSourceType.quickActions.rawValue:
                DailyPixel.fireDailyAndCount(pixel: .openAIChatFromWidgetQuickAction)
            case WidgetSourceType.favorite.rawValue:
                DailyPixel.fireDailyAndCount(pixel: .openAIChatFromWidgetFavorite)
            case WidgetSourceType.lockscreenComplication.rawValue:
                DailyPixel.fireDailyAndCount(pixel: .openAIChatFromWidgetLockScreenComplication)
            case WidgetSourceType.controlCenter.rawValue:
                DailyPixel.fireDailyAndCount(pixel: .openAIChatFromWidgetControlCenter)
            default:
                break
            }
        }
    }
}
