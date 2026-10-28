//
//  AIChatOpeningRequest.swift
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

struct AIChatOpeningPromptInfo: Equatable {
    let hasContent: Bool
    let autoSubmit: Bool
    // Address-bar attribution counts query content, excluding page contexts and selections.
    let hasAutoSubmittedQuery: Bool

    var hasAutoSubmittedPrompt: Bool { hasContent && autoSubmit }

    init(query: String?, autoSubmit: Bool, hasAttachments: Bool) {
        hasContent = query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || hasAttachments
        self.autoSubmit = autoSubmit
        hasAutoSubmittedQuery = hasContent && autoSubmit
    }

    init(prompt: AIChatNativePrompt) {
        let hasPageContext: Bool
        switch prompt.pageContext {
        case .single:
            hasPageContext = true
        case .multiple(let contexts):
            hasPageContext = !contexts.isEmpty
        case nil:
            hasPageContext = false
        }
        let queryInfo: AIChatOpeningPromptInfo
        switch prompt.tool {
        case .query(let query):
            queryInfo = Self(query: query.prompt, autoSubmit: query.autoSubmit,
                             hasAttachments: !query.attachments.isEmpty)
        case .summary(let summary):
            queryInfo = Self(query: summary.text, autoSubmit: false, hasAttachments: false)
        case .translation(let translation):
            queryInfo = Self(query: translation.text, autoSubmit: false, hasAttachments: false)
        case nil:
            queryInfo = Self(query: nil, autoSubmit: false, hasAttachments: false)
        }
        hasContent = queryInfo.hasContent || hasPageContext || prompt.selections?.isEmpty == false
        autoSubmit = queryInfo.autoSubmit
        hasAutoSubmittedQuery = queryInfo.hasAutoSubmittedPrompt
    }
}

@MainActor
struct AIChatOpeningRequest {
    struct Query {
        // Keep the original optional query: URL construction distinguishes nil from an empty string.
        let query: String?
        let autoSend: Bool
        let flowType: AIChatOnboardingFlowType
        let tools: [AIChatRAGTool]?
        let nativePrompt: AIChatNativePrompt
        let nativePromptFlow: DuckAIPromptFlowStart?

        init(query: String?, autoSend: Bool, flowType: AIChatOnboardingFlowType, tools: [AIChatRAGTool]?,
             modelId: String?, reasoningEffort: AIChatReasoningEffort?,
             attachments: AIChatPromptAttachments, termsAccepted: Bool, nativePromptFlow: DuckAIPromptFlowStart? = nil) {
            self.query = query
            self.autoSend = autoSend
            self.flowType = flowType
            self.tools = tools
            self.nativePromptFlow = nativePromptFlow
            nativePrompt = .queryPrompt(query ?? "", autoSubmit: autoSend, toolChoice: tools?.map(\.rawValue),
                                        attachments: attachments, modelId: modelId, reasoningEffort: reasoningEffort)
                .withTermsAccepted(termsAccepted)
        }

        var promptInfo: AIChatOpeningPromptInfo { AIChatOpeningPromptInfo(prompt: nativePrompt) }

        var sharedPrompt: AIChatNativePrompt? { promptInfo.hasContent ? nativePrompt : nil }

        func url(using handler: AIChatContentHandling) -> URL {
            handler.buildQueryURL(query: query, autoSend: autoSend, flowType: flowType, tools: tools)
        }
    }

    struct PreparedContext {
        let tabsModel: TabsModelManaging
        let shouldPresent: Bool
        let selectedModelID: String?
        let selectedReasoningMode: AIChatReasoningMode?
        let promptModelID: String?
    }

    enum Prompt {
        case sharedHandler(Query, reportsNewTab: Bool?, fromDeepLink: Bool)
        case tabSession(AIChatInitialPromptDelivery, PreparedContext)
    }

    let url: URL
    let payload: Any?
    let source: AIChatEntryPointSource
    let opensNewTab: Bool
    let prompt: Prompt
    /// The user started by speaking, e.g. voice search sent to Duck.ai.
    var isVoice = false

    var promptInfo: AIChatOpeningPromptInfo {
        switch prompt {
        case .sharedHandler(let query, _, _): return query.promptInfo
        case .tabSession(let delivery, _): return delivery.promptInfo
        }
    }

    var reportsNewTab: Bool {
        // Callers that already created a blank tab can override reporting without opening another one.
        if case .sharedHandler(_, let reportsNewTab, _) = prompt { return reportsNewTab ?? opensNewTab }
        return opensNewTab
    }

    var hasEntryPrompt: Bool {
        if case .sharedHandler(let query, _, _) = prompt { return query.query?.isEmpty == false }
        return true
    }

    var shouldPresent: Bool {
        if case .tabSession(_, let context) = prompt { return context.shouldPresent }
        return true
    }

    var shouldMeasureOpening: Bool {
        if case .sharedHandler(_, _, let fromDeepLink) = prompt { return !opensNewTab || !fromDeepLink }
        return shouldPresent
    }

    var modelID: String? {
        switch prompt {
        case .sharedHandler(let query, _, _):
            guard case .query(let nativeQuery)? = query.nativePrompt.tool else { return nil }
            return nativeQuery.modelId
        case .tabSession(_, let context):
            return context.promptModelID
        }
    }
}
