//
//  DaxPetAttachments.swift
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
import AppKit
import NaturalLanguage
import Subscription
import UniformTypeIdentifiers

/// Something dropped on Dax, as read off the pasteboard.
enum DaxPetDroppedItem: Equatable {
    case text(String)
    case link(URL)
    case file(URL)

    /// Files first, then a link, then plain text: a dragged file also carries its path as text.
    static func items(from pasteboard: NSPasteboard) -> [DaxPetDroppedItem] {
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !fileURLs.isEmpty {
            return fileURLs.map { .file($0) }
        }
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first, !url.isFileURL {
            return [.link(url)]
        }
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return [.text(text)]
        }
        return []
    }
}

/// What Dax carries along with a prompt.
enum DaxPetAttachment: Identifiable {
    case text(id: UUID = UUID(), String)
    case link(id: UUID = UUID(), URL)
    case image(AIChatImageAttachment)
    case file(AIChatFileAttachment)

    var id: UUID {
        switch self {
        case .text(let id, _), .link(let id, _): return id
        case .image(let image): return image.id
        case .file(let file): return file.id
        }
    }

    var name: String {
        switch self {
        case .text(_, let text): return String(text.prefix(40))
        case .link(_, let url): return url.host ?? url.absoluteString
        case .image(let image): return image.fileName
        case .file(let file): return file.fileName
        }
    }
}

/// What a drop is, as far as the on-device model can tell.
enum DaxPetDropKind: Equatable {
    case article
    case code
    case message
    case other
}

/// The request Dax guesses the user wants for a drop, offered as the prompt field's hint and sent if they
/// just press Return.
enum DaxPetDropAction: Equatable {
    case summarize
    case translate
    case explainCode
    case reply
    case describeImage

    /// Text this long is worth summarizing even without the on-device model's opinion.
    static let summarizableLength = 400
    /// Shorter text is too little to tell its language from.
    static let recognizableLength = 20

    var prompt: String {
        switch self {
        case .summarize: return UserText.daxPetActionSummarize
        case .translate:
            let code = Self.userLanguageCode
            return UserText.daxPetActionTranslate(into: Locale.current.localizedString(forLanguageCode: code) ?? code)
        case .explainCode: return UserText.daxPetActionExplainCode
        case .reply: return UserText.daxPetActionReply
        case .describeImage: return UserText.daxPetActionDescribeImage
        }
    }

    static var userLanguageCode: String {
        if #available(macOS 13, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        return Locale.current.languageCode ?? "en"
    }

    /// Images are described and text in another language translated. Otherwise the on-device model's
    /// `kind` decides when it has one, and documents, links and long text are summarized.
    static func guess(for attachments: [DaxPetAttachment], kind: DaxPetDropKind?) -> DaxPetDropAction? {
        guard !attachments.isEmpty else { return nil }
        if attachments.allSatisfy({ if case .image = $0 { true } else { false } }) {
            return .describeImage
        }
        if isInAnotherLanguage(attachments) {
            return .translate
        }
        switch kind {
        case .article: return .summarize
        case .code: return .explainCode
        case .message: return .reply
        case .other, nil: break
        }
        let isSummarizable = attachments.contains { attachment in
            switch attachment {
            case .file, .link: return true
            case .text(_, let text): return text.count >= summarizableLength
            case .image: return false
            }
        }
        return isSummarizable ? .summarize : nil
    }

    /// Recognized on the device by the NaturalLanguage framework, and only when it's sure.
    private static func isInAnotherLanguage(_ attachments: [DaxPetAttachment]) -> Bool {
        let text = attachments.compactMap { if case .text(_, let text) = $0 { text } else { nil } }.joined(separator: "\n")
        guard text.count >= recognizableLength else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first, confidence >= 0.8 else { return false }
        return language.rawValue.prefix(2) != userLanguageCode.prefix(2)
    }
}

/// The selected Duck.ai model and the user's attachment limits, which decide what Dax may take.
struct DaxPetAttachmentCapabilities {
    let model: AIChatModel?
    let limits: AIChatAttachmentTierLimits?

    static let unknown = DaxPetAttachmentCapabilities(model: nil, limits: nil)

    @MainActor
    func validator(pendingImageCount: Int, pendingFiles: [AIChatAttachmentValidator.FileDescriptor]) -> AIChatAttachmentValidator {
        AIChatAttachmentValidator(limits: limits,
                                  model: model,
                                  pendingImageCount: pendingImageCount,
                                  pendingFiles: pendingFiles,
                                  messages: AIChatOmnibarController.attachmentValidatorMessages)
    }
}

@MainActor
protocol DaxPetAttachmentCapabilitiesProviding {
    func capabilities() async -> DaxPetAttachmentCapabilities
}

/// Reads the models and limits as the address bar does, for the model the user picked there.
@MainActor
final class DaxPetAttachmentCapabilitiesProvider: DaxPetAttachmentCapabilitiesProviding {

    private let modelsService: AIChatModelsProviding
    private let subscriptionManager: any SubscriptionManager
    private let preferences: AIChatPreferencesPersisting

    init(subscriptionManager: any SubscriptionManager, preferences: AIChatPreferencesPersisting, modelsService: AIChatModelsProviding? = nil) {
        self.subscriptionManager = subscriptionManager
        self.preferences = preferences
        self.modelsService = modelsService ?? AIChatModelsService(accessTokenProvider: subscriptionManager)
    }

    func capabilities() async -> DaxPetAttachmentCapabilities {
        guard let response = try? await modelsService.fetchModels() else { return .unknown }
        let tier = await userTier()
        let models = response.models.map { AIChatModel(remoteModel: $0, userTier: tier) }
        let model = models.first { $0.id == preferences.selectedModelId && $0.entityHasAccess }
            ?? models.first { $0.entityHasAccess }
        return DaxPetAttachmentCapabilities(model: model, limits: response.attachmentLimits?.limits(for: tier))
    }

    private func userTier() async -> AIChatUserTier {
        guard let subscription = try? await subscriptionManager.getSubscription(forceRefresh: false), subscription.isActive else {
            return .free
        }
        switch subscription.tier {
        case .plus: return .plus
        case .pro: return .pro
        case .none: return .free
        }
    }
}

@MainActor
enum DaxPetAttachmentLoader {

    /// Turns dropped items into attachments the model accepts, next to those already taken. Plain text
    /// files are read in as text; the first refusal is explained in `rejection`.
    static func load(_ items: [DaxPetDroppedItem],
                     adding existing: [DaxPetAttachment],
                     capabilities: DaxPetAttachmentCapabilities) -> (accepted: [DaxPetAttachment], rejection: String?) {
        var accepted: [DaxPetAttachment] = []
        var rejection: String?
        var imageCount = existing.filter { if case .image = $0 { true } else { false } }.count
        var files = existing.compactMap { if case .file(let file) = $0 { AIChatAttachmentValidator.FileDescriptor(file) } else { nil } }

        for item in items {
            switch item {
            case .text(let text):
                accepted.append(.text(text))
            case .link(let url):
                accepted.append(.link(url))
            case .file(let url):
                let type = UTType(filenameExtension: url.pathExtension.lowercased())
                if type?.conforms(to: .image) == true {
                    let validator = capabilities.validator(pendingImageCount: imageCount, pendingFiles: files)
                    guard validator.canAttachImages, let image = NSImage(contentsOf: url) else {
                        rejection = rejection ?? imageRejection(validator)
                        continue
                    }
                    accepted.append(.image(AIChatImageAttachment(image: image, fileName: url.lastPathComponent, fileURL: url)))
                    imageCount += 1
                } else if type?.conforms(to: .plainText) == true, let text = try? String(contentsOf: url, encoding: .utf8) {
                    accepted.append(.text(text))
                } else if let file = AIChatOmnibarContainerViewController.makeFileAttachment(from: url) {
                    let descriptor = AIChatAttachmentValidator.FileDescriptor(file)
                    if let error = capabilities.validator(pendingImageCount: imageCount, pendingFiles: files).fileValidationError(for: descriptor) {
                        rejection = rejection ?? error.message
                        continue
                    }
                    accepted.append(.file(file))
                    files.append(descriptor)
                } else {
                    rejection = rejection ?? UserText.aiChatAttachmentFileUnreadable
                }
            }
        }
        return (accepted, rejection)
    }

    private static func imageRejection(_ validator: AIChatAttachmentValidator) -> String {
        guard validator.model?.supportsImageUpload == true else { return UserText.aiChatAttachmentUnsupportedFileType }
        let maxPerTurn = validator.limits?.images.maxPerTurn ?? AIChatOmnibarController.fallbackMaxImageAttachments
        return UserText.aiChatAttachmentImageTurnLimit(maxImagesPerTurn: maxPerTurn)
    }

    /// The prompt Duck.ai receives: dropped text and links follow the question, images and files travel
    /// as attachments for the model they were checked against.
    static func prompt(_ question: String,
                       attachments: [DaxPetAttachment],
                       capabilities: DaxPetAttachmentCapabilities) -> (query: String, payload: AIChatNativePrompt?) {
        guard !attachments.isEmpty else { return (question, nil) }
        var context: [String] = []
        var images: [AIChatImageAttachment] = []
        var files: [AIChatFileAttachment] = []
        for attachment in attachments {
            switch attachment {
            case .text(_, let text): context.append(text)
            case .link(_, let url): context.append(url.absoluteString)
            case .image(let image): images.append(image)
            case .file(let file): files.append(file)
            }
        }
        let query = ([question] + context).joined(separator: "\n\n")
        let nativeImages = AIChatOmnibarController.nativePromptImages(from: images,
                                                                      supportedFormats: capabilities.model?.supportedImageFormats ?? [])
        let nativeFiles = files.isEmpty ? nil : files.map {
            AIChatNativePrompt.NativePromptFile(data: $0.data.base64EncodedString(), fileName: $0.fileName, mimeType: $0.mimeType)
        }
        guard nativeImages != nil || nativeFiles != nil else { return (query, nil) }
        let payload = AIChatNativePrompt.queryPrompt(query,
                                                     autoSubmit: true,
                                                     attachments: AIChatPromptAttachments(images: nativeImages, files: nativeFiles),
                                                     modelId: capabilities.model?.id)
        return (query, payload)
    }
}
