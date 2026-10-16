//
//  AIChatInitialPromptDelivery.swift
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

/// A prepared, recipient-owned prompt. Script replacement shares the same single-use value.
@MainActor
final class AIChatInitialPromptDelivery {
    enum ConsumptionResult: Equatable {
        case consumed
        case timedOut
        case cancelled
    }

    private var prompt: AIChatNativePrompt?
    private var onConsumed: (() -> Void)?
    private let consumptionGate = AIChatFrontendReadinessGate()
    private let consumptionTimeout: TimeInterval
    private let evictionProtectionDeadline: Date
    private let now: () -> Date
    private var isCancelled = false
    private var didTimeOut = false

    init(prompt: AIChatNativePrompt,
         consumptionTimeout: TimeInterval = 5,
         evictionProtectionDuration: TimeInterval = 30,
         now: @escaping () -> Date = Date.init,
         onConsumed: @escaping () -> Void) {
        self.prompt = prompt
        self.consumptionTimeout = consumptionTimeout
        self.evictionProtectionDeadline = now().addingTimeInterval(evictionProtectionDuration)
        self.now = now
        self.onConsumed = onConsumed
    }

    /// The prompt lives only in the recipient's controller, so evicting it loses the prompt. The protection
    /// is bounded so a page that never pulls the prompt doesn't pin its tab in the cache.
    var protectsRecipientFromEviction: Bool {
        prompt != nil && now() < evictionProtectionDeadline
    }

    func consume() -> AIChatNativePrompt? {
        guard let prompt else { return nil }
        self.prompt = nil
        let onConsumed = onConsumed
        self.onConsumed = nil
        consumptionGate.markReady()
        onConsumed?()
        return prompt
    }

    /// Only subsequent pushes wait for the initial pull; the pull itself never waits.
    func waitUntilConsumed() async -> ConsumptionResult {
        guard !isCancelled, !Task.isCancelled else { return .cancelled }
        guard !didTimeOut else { return .timedOut }
        guard !consumptionGate.isReady else { return .consumed }
        let completionSignalled = await consumptionGate.waitUntilReady(timeout: consumptionTimeout)
        if isCancelled || Task.isCancelled { return .cancelled }
        if didTimeOut { return .timedOut }
        if completionSignalled || consumptionGate.isReady { return .consumed }
        didTimeOut = true
        prompt = nil
        onConsumed = nil
        consumptionGate.reset()
        return .timedOut
    }

    func cancel() {
        isCancelled = true
        prompt = nil
        onConsumed = nil
        consumptionGate.reset()
    }
}

/// Owned by the source input's tab until a complete prompt can be handed to its recipient.
@MainActor
final class AIChatInitialPromptPreparation {
    private var task: Task<Void, Never>?
    private let request: MultiTabAttachmentRequest
    private var completion: ((AIChatInitialPromptDelivery?) -> Void)?

    init(prompt: AIChatNativePrompt, request: MultiTabAttachmentRequest,
         completion: @escaping (AIChatInitialPromptDelivery?) -> Void) {
        self.request = request
        self.completion = completion
        task = Task { @MainActor [weak self] in
            let contexts = await request.contexts()
            guard !Task.isCancelled else { return }
            let validated = request.validate(contexts)
            let payload = AIChatNativePrompt(platform: prompt.platform, tool: prompt.tool,
                                             pageContext: validated.isEmpty ? nil : .multiple(validated),
                                             selections: prompt.selections, termsAccepted: prompt.termsAccepted)
            let didDispatch = request.didDispatch
            let result = MultiTabAttachmentRequest.SubmissionResult(
                totalTabCount: validated.count, additionalTabCount: validated.filter { $0.tabId != nil }.count)
            let delivery = AIChatInitialPromptDelivery(prompt: payload) { didDispatch(result) }
            request.didConsume()
            self?.finish(delivery)
        }
    }

    deinit {
        task?.cancel()
        let request = request
        Task { @MainActor in request.cancel() }
    }

    func cancel() {
        task?.cancel()
        finish(nil)
    }

    private func finish(_ delivery: AIChatInitialPromptDelivery?) {
        guard let completion else { return }
        self.completion = nil
        task = nil
        request.cancel()
        completion(delivery)
    }
}
