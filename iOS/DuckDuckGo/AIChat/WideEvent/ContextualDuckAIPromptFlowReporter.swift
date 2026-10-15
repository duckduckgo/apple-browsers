//
//  ContextualDuckAIPromptFlowReporter.swift
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
import Subscription

/// The Ask about page sheet's events for the `ios-duckai-prompt` flow, whoever hosts its input.
@MainActor
protocol ContextualDuckAIPromptFlowReporting: AnyObject {
    func initialNativePromptSubmitted(hasPageContext: Bool)
    func frontendSubmissionAcknowledged()
    func chatStatusChanged(_ status: AIChatStatusValue)
    func pageLoadFailed(error: Error)
    func sheetDismissed()
}

/// Runs the sheet's prompt flow when Unified Input does not host the sheet (iPad's native input).
@MainActor
final class ContextualDuckAIPromptFlowReporter: ContextualDuckAIPromptFlowReporting {

    private let instrumentation: DuckAIWideEventInstrumentation
    private let scope = DuckAIWideEventFlowScope.contextual(UUID())
    private let isFireMode: Bool
    private var userTier: AIChatUserTier = .free

    init(instrumentation: DuckAIWideEventInstrumentation,
         isFireMode: Bool,
         subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager) {
        self.instrumentation = instrumentation
        self.isFireMode = isFireMode
        // Resolved ahead of the first prompt, which can't wait for it.
        Task { [weak self] in
            let tier = await AIChatUserTier.resolve(from: subscriptionManager)
            self?.userTier = tier
        }
    }

    func initialNativePromptSubmitted(hasPageContext: Bool) {
        instrumentation.submissionStarted(scope: scope,
                                          modelId: nil,
                                          userTier: userTier,
                                          reasoningEffort: nil,
                                          entryPoint: .contextualChat,
                                          origin: .contextualChat,
                                          inputMode: .keyboard,
                                          fireMode: isFireMode,
                                          isFirstPrompt: true,
                                          frontendDeliveryPath: .contextualNativeInput,
                                          hasPageContext: hasPageContext,
                                          toolsSelected: false,
                                          attachmentsSelected: false)
    }

    func frontendSubmissionAcknowledged() {
        instrumentation.frontendSubmissionAcknowledged(scope: scope)
    }

    func chatStatusChanged(_ status: AIChatStatusValue) {
        instrumentation.chatStatusChanged(status, scope: scope)
    }

    func pageLoadFailed(error: Error) {
        instrumentation.pageLoadFailed(scope: scope, error: error)
    }

    func sheetDismissed() {
        instrumentation.sheetDismissedDuringGeneration(scope: scope)
    }
}
