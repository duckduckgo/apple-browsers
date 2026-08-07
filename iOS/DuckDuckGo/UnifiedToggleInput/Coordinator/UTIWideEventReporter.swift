//
//  UTIWideEventReporter.swift
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
import Foundation

/// Live snapshot of the state a Duck.ai submission wide-event needs, resolved at fire time so a
/// submission always records the model / tier / fire-mode / first-prompt as they are that instant.
struct UTIWideEventSubmissionInputs {
    let modelId: String?
    let userTier: AIChatUserTier
    let persistedReasoningEffort: AIChatReasoningEffort?
    let fireMode: Bool
    let hasSubmittedPrompt: Bool
    let entryPoint: DuckAIPromptWideEventData.EntryPoint
}

/// Owns the omnibar UTI's Duck.ai wide-event firing: the submission / delivery records plus the
/// generating-status and stop-generating subscriptions. Reads the flow scope and submission inputs
/// live (never captured) so every event attaches to the current tab/session at fire time.
@MainActor
final class UTIWideEventReporter {

    private let instrumentation: DuckAIWideEventInstrumentation?
    private let flowScope: () -> DuckAIWideEventFlowScope?
    private let submissionInputs: () -> UTIWideEventSubmissionInputs?
    private var cancellables = Set<AnyCancellable>()

    init(instrumentation: DuckAIWideEventInstrumentation?,
         flowScope: @escaping () -> DuckAIWideEventFlowScope?,
         submissionInputs: @escaping () -> UTIWideEventSubmissionInputs?) {
        self.instrumentation = instrumentation
        self.flowScope = flowScope
        self.submissionInputs = submissionInputs
    }

    /// The user's primary submission (voice or keyboard): opens the wide-event flow with a live
    /// snapshot of the submit-time state. `isFirstPrompt` reflects `hasSubmittedPrompt` *before* the
    /// submit path flips it — it is resolved here, at call time, never after.
    func recordSubmissionStarted(reasoningEffort: AIChatReasoningEffort?,
                                 inputMode: DuckAIPromptWideEventData.InputMode,
                                 frontendDeliveryPath: DuckAIPromptWideEventData.FrontendDeliveryPath,
                                 hasPageContext: Bool,
                                 toolsSelected: Bool,
                                 attachmentsSelected: Bool) {
        guard let scope = flowScope(), let inputs = submissionInputs() else { return }
        instrumentation?.submissionStarted(
            scope: scope,
            modelId: inputs.modelId,
            userTier: inputs.userTier,
            reasoningEffort: reasoningEffort,
            entryPoint: inputs.entryPoint,
            inputMode: inputMode,
            fireMode: inputs.fireMode,
            isFirstPrompt: !inputs.hasSubmittedPrompt,
            frontendDeliveryPath: frontendDeliveryPath,
            hasPageContext: hasPageContext,
            toolsSelected: toolsSelected,
            attachmentsSelected: attachmentsSelected
        )
    }

    func recordPromptDelivered(wasQueued: Bool?, didSendBridgeMessage: Bool?) {
        guard let scope = flowScope() else { return }
        instrumentation?.promptDeliveryUpdated(scope: scope, wasQueued: wasQueued, didSendBridgeMessage: didSendBridgeMessage)
    }

    func recordPromptInterpretedAsURL() {
        guard let scope = flowScope() else { return }
        instrumentation?.promptInterpretedAsURL(scope: scope)
    }

    /// The contextual sheet's native-input path submits its first prompt outside the UTI (no bound
    /// user script yet); this opens the flow so the JS status updates that follow have one to attach to.
    func recordExternalPromptSubmitted(entryPoint: DuckAIPromptWideEventData.EntryPoint,
                                       inputMode: DuckAIPromptWideEventData.InputMode,
                                       isFirstPrompt: Bool,
                                       hasPageContext: Bool) {
        guard let scope = flowScope(), let inputs = submissionInputs() else { return }
        instrumentation?.submissionStarted(
            scope: scope,
            modelId: inputs.modelId,
            userTier: inputs.userTier,
            reasoningEffort: inputs.persistedReasoningEffort,
            entryPoint: entryPoint,
            inputMode: inputMode,
            fireMode: inputs.fireMode,
            isFirstPrompt: isFirstPrompt,
            frontendDeliveryPath: entryPoint == .contextualChat ? .contextualNativeInput : .urlAutoSubmit,
            hasPageContext: hasPageContext,
            toolsSelected: false,
            attachmentsSelected: false
        )
    }

    func recordTabSwitchedAwayDuringGeneration(tabID: TabUID) {
        instrumentation?.tabSwitchedAwayDuringGeneration(tabID: tabID)
    }

    /// Bridges the generating-status and stop-generating publishers to the wide-event flow, reading
    /// the scope live so a status update always lands on the current tab's flow.
    func subscribe(aiChatStatus: AnyPublisher<AIChatStatusValue, Never>,
                   stopGeneratingTapped: AnyPublisher<Void, Never>) {
        aiChatStatus
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self, let scope = self.flowScope() else { return }
                self.instrumentation?.chatStatusChanged(status, scope: scope)
            }
            .store(in: &cancellables)

        stopGeneratingTapped
            .sink { [weak self] in
                guard let self, let scope = self.flowScope() else { return }
                self.instrumentation?.stopGeneratingTapped(scope: scope)
            }
            .store(in: &cancellables)
    }
}
