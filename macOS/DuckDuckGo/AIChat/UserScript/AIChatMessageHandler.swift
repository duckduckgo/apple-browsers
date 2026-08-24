//
//  AIChatMessageHandler.swift
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

import AIChat
import Common
import Foundation
import FoundationExtensions
import PrivacyConfig
import UserScript

enum AIChatMessageType {
    case nativeHandoffData
    case nativePrompt
    case chatRestorationData
    case pageContext
}

protocol AIChatMessageHandling {
    /// Builds the native config for one webview. `isSidebar` identifies the requesting surface
    /// (sidebar / detached floating window vs. the full-page duck.ai tab) so per-surface
    /// capabilities like the tab picker can resolve against the right feature flag.
    func getNativeConfigValues(isFireWindow: Bool, isSidebar: Bool) -> AIChatNativeConfigValues
    func getDataForMessageType(_ type: AIChatMessageType) -> Encodable?
    func setData(_ data: Any?, forMessageType type: AIChatMessageType)

    /// Selection context is a list (not a single slot), so it has dedicated accessors rather than
    /// going through `AIChatMessageType`. `appendSelectionContext` stores a pushed selection so a
    /// later `getSelectionContexts` pull can return it; `clearSelectionContexts` resets on submit.
    func appendSelectionContext(_ selection: AIChatSelectionContextData)
    func getSelectionContexts() -> [AIChatSelectionContextData]
    func clearSelectionContexts()
}

final class AIChatMessageHandler: AIChatMessageHandling {
    private let featureFlagger: FeatureFlagger
    private let promptHandler: any AIChatConsumableDataHandling
    private let payloadHandler: AIChatPayloadHandler
    private let chatRestorationDataHandler: AIChatRestorationDataHandler
    private let pageContextHandler: AIChatPageContextHandler
    private let selectionContextHandler: AIChatSelectionContextHandler
    private let isNativeStorageBridgeAvailable: Bool
    private let installDateProvider: () -> Date?
    private let installTypeProvider: () -> AIChatInstallType

    init(featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
         promptHandler: any AIChatConsumableDataHandling = AIChatPromptHandler.shared,
         payloadHandler: AIChatPayloadHandler = AIChatPayloadHandler(),
         chatRestorationDataHandler: AIChatRestorationDataHandler = AIChatRestorationDataHandler(),
         pageContextHandler: AIChatPageContextHandler = AIChatPageContextHandler(),
         selectionContextHandler: AIChatSelectionContextHandler = AIChatSelectionContextHandler(),
         isNativeStorageBridgeAvailable: Bool = false,
         installDateProvider: @escaping () -> Date? = { LocalStatisticsStore().installDate },
         installTypeProvider: @escaping () -> AIChatInstallType = {
             // App Store builds can't detect reinstalls, so report `.unknown` rather than misreporting `.new`.
             guard StandardApplicationBuildType().isSparkleBuild else { return .unknown }
             let isReturning = DefaultReinstallUserDetection(
                keyValueStore: Application.appDelegate.keyValueStore).isReinstallingUser
             return isReturning ? .returning : .new
         }) {
        self.featureFlagger = featureFlagger
        self.promptHandler = promptHandler
        self.payloadHandler = payloadHandler
        self.chatRestorationDataHandler = chatRestorationDataHandler
        self.pageContextHandler = pageContextHandler
        self.selectionContextHandler = selectionContextHandler
        self.isNativeStorageBridgeAvailable = isNativeStorageBridgeAvailable
        self.installDateProvider = installDateProvider
        self.installTypeProvider = installTypeProvider
    }

    func getDataForMessageType(_ type: AIChatMessageType) -> Encodable? {
        switch type {
        case .nativeHandoffData:
            return getNativeHandoffData()
        case .nativePrompt:
            return getAIChatNativePrompt()
        case .chatRestorationData:
            return getAIChatRestorationData()
        case .pageContext:
            return getPageContext()
        }
    }

    func setData(_ data: Any?, forMessageType type: AIChatMessageType) {
        switch type {
        case .nativeHandoffData:
            setNativeHandoffData(data as? AIChatPayload)
        case .chatRestorationData:
            setAIChatRestorationData(data as? AIChatRestorationData)
        case .pageContext:
            setPageContext(data as? AIChatPageContextData)
        default:
            break
        }
    }

    func appendSelectionContext(_ selection: AIChatSelectionContextData) {
        selectionContextHandler.append(selection)
    }

    func getSelectionContexts() -> [AIChatSelectionContextData] {
        selectionContextHandler.getAll()
    }

    func clearSelectionContexts() {
        selectionContextHandler.reset()
    }
}

// MARK: - Messages
extension AIChatMessageHandler {
    /// `isSidebar` defaults to the full-page surface for direct (e.g. test) callers; the
    /// user-script call site always passes the surface resolved from the requesting webview.
    func getNativeConfigValues(isFireWindow: Bool, isSidebar: Bool = false) -> AIChatNativeConfigValues {
        let appVersion = AppVersion.shared.versionAndBuildNumber
        let defaults = AIChatNativeConfigValues.defaultValues
        return AIChatNativeConfigValues(
            isAIChatHandoffEnabled: true,
            supportsClosingAIChat: true,
            supportsOpeningSettings: true,
            supportsNativePrompt: true,
            supportsStandaloneMigration: featureFlagger.isFeatureOn(.standaloneMigration),
            supportsNativeChatInput: false,
            supportsURLChatIDRestoration: true,
            supportsFullChatRestoration: true,
            supportsPageContext: featureFlagger.isFeatureOn(.aiChatPageContext),
            supportsAIChatFullMode: false,
            supportsAIChatContextualMode: false,
            appVersion: appVersion,
            supportsHomePageEntryPoint: defaults.supportsHomePageEntryPoint,
            supportsOpenAIChatLink: defaults.supportsOpenAIChatLink,
            supportsAIChatSync: featureFlagger.isFeatureOn(.aiChatSync) && !isFireWindow,
            supportsMultipleContexts: featureFlagger.isFeatureOn(.aiChatPageContext) && featureFlagger.isFeatureOn(.aiChatMultiplePageContexts),
            // Tab attachment is gated per surface: the sidebar (and its detached floating window)
            // by `aiChatSidebarAttachMoreTabs`, the full-page duck.ai tab by `aiChatAttachMoreTabs`.
            supportsTabPicker: featureFlagger.isFeatureOn(.aiChatPageContext)
                && featureFlagger.isFeatureOn(isSidebar ? .aiChatSidebarAttachMoreTabs : .aiChatAttachMoreTabs),
            supportsNativeStorage: featureFlagger.isFeatureOn(.aiChatNativeStorage) && isNativeStorageBridgeAvailable,
            supportsSuggestions: featureFlagger.isFeatureOn(.aiChatPageContext) && featureFlagger.isFeatureOn(.sidebarSuggestedPrompts),
            supportsNativeVoicePermissionHandler: featureFlagger.isFeatureOn(.aiChatNativeVoicePermissionFlow),
            supportsNativeDictationPermissionHandler: true,
            installType: installTypeProvider(),
            installAge: AIChatNativeConfigValues.installAgeBucket(installDate: installDateProvider()),
            attachmentLimits: featureFlagger.isFeatureOn(.aiChatTabAttachmentLimit)
                ? AIChatNativeAttachmentLimits(tabs: .init(maxAttached: AIChatOmnibarController.maxTabAttachments))
                : nil
        )
    }

    private func getNativeHandoffData() -> Encodable? {
        guard let payload = payloadHandler.consumeData() else { return nil }
        return AIChatNativeHandoffData.defaultValuesWithPayload(payload)
    }

    private func setNativeHandoffData(_ payload: AIChatPayload?) {
        guard let payload else {
            payloadHandler.reset()
            return
        }

        payloadHandler.setData(payload)
    }

    private func getAIChatNativePrompt() -> Encodable? {
        guard let prompt = promptHandler.consumeData() as? AIChatNativePrompt else {
            return nil
        }

        return prompt
    }

    private func getAIChatRestorationData() -> Encodable? {
        chatRestorationDataHandler.consumeData()
    }

    private func setAIChatRestorationData(_ data: AIChatRestorationData?) {
        guard let data else {
            chatRestorationDataHandler.reset()
            return
        }

        chatRestorationDataHandler.setData(data)
    }

    private func getPageContext() -> Encodable? {
        pageContextHandler.consumeData()
    }

    private func setPageContext(_ data: AIChatPageContextData?) {
        guard let data else {
            pageContextHandler.reset()
            return
        }

        pageContextHandler.setData(data)
    }
}
