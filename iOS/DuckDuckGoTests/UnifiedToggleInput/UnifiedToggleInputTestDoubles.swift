//
//  UnifiedToggleInputTestDoubles.swift
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
@testable import DuckDuckGo

@MainActor
final class MockDuckAIWideEventInstrumentation: DuckAIWideEventInstrumentation {
    private(set) var submissionStartedScopes: [DuckAIWideEventFlowScope] = []
    private(set) var submissionStartedModelIds: [String?] = []
    private(set) var tabSwitchedAwayCalls: [TabUID] = []
    private(set) var promptInterpretedAsURLScopes: [DuckAIWideEventFlowScope] = []

    func submissionStarted(scope: DuckAIWideEventFlowScope,
                           modelId: String?,
                           userTier: AIChatUserTier,
                           reasoningEffort: AIChatReasoningEffort?,
                           entryPoint: DuckAIPromptWideEventData.EntryPoint,
                           inputMode: DuckAIPromptWideEventData.InputMode,
                           fireMode: Bool,
                           isFirstPrompt: Bool,
                           frontendDeliveryPath: DuckAIPromptWideEventData.FrontendDeliveryPath,
                           hasPageContext: Bool,
                           toolsSelected: Bool,
                           attachmentsSelected: Bool) {
        submissionStartedScopes.append(scope)
        submissionStartedModelIds.append(modelId)
    }
    func promptDeliveryUpdated(scope: DuckAIWideEventFlowScope, wasQueued: Bool?, didSendBridgeMessage: Bool?) {}
    func frontendSubmissionAcknowledged(scope: DuckAIWideEventFlowScope) {}
    func chatStatusChanged(_ status: AIChatStatusValue, scope: DuckAIWideEventFlowScope) {}
    func stopGeneratingTapped(scope: DuckAIWideEventFlowScope) {}
    func tabClosedDuringGeneration(tabID: TabUID) {}
    func tabSwitchedAwayDuringGeneration(tabID: TabUID) { tabSwitchedAwayCalls.append(tabID) }
    func fireButtonClearedTabDuringGeneration(tabID: TabUID) {}
    func sheetDismissedDuringGeneration(scope: DuckAIWideEventFlowScope) {}
    func pageLoadFailed(scope: DuckAIWideEventFlowScope, error: Error) {}
    func promptInterpretedAsURL(scope: DuckAIWideEventFlowScope) { promptInterpretedAsURLScopes.append(scope) }
}
