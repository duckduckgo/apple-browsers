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

/// One frontend request and its response. Context collection remains owned by the submission task.
@MainActor
final class AIChatInitialPromptDelivery {
    private static let frontendResponseTimeout: TimeInterval = 5

    private let frontendRequestGate = AIChatFrontendReadinessGate()
    private let frontendSubmissionGate = AIChatFrontendReadinessGate()
    private var pendingResponse: CheckedContinuation<AIChatNativePrompt?, Never>?
    private var hasReceivedRequest = false
    private var isCancelled = false

    var hasPendingResponse: Bool { pendingResponse != nil }
    var canAcceptRequest: Bool { !hasReceivedRequest && !isCancelled }

    deinit {
        pendingResponse?.resume(returning: nil)
    }

    // MARK: - Submission task

    func waitUntilRequested() async -> Bool {
        guard !isCancelled else { return false }
        return await frontendRequestGate.waitUntilReady(timeout: Self.frontendResponseTimeout)
    }

    func reply(with prompt: AIChatNativePrompt) -> Bool {
        guard !isCancelled, let response = pendingResponse else { return false }
        pendingResponse = nil
        response.resume(returning: prompt)
        return true
    }

    /// Keep subsequent prompts queued until the frontend has submitted this first one.
    func waitUntilSubmitted() async -> Bool {
        guard !isCancelled else { return false }
        return await frontendSubmissionGate.waitUntilReady(timeout: Self.frontendResponseTimeout)
    }

    // MARK: - Frontend callbacks

    func waitForPrompt() async -> AIChatNativePrompt? {
        guard canAcceptRequest, !Task.isCancelled else { return nil }
        hasReceivedRequest = true
        return await withCheckedContinuation { response in
            pendingResponse = response
            frontendRequestGate.markReady()
        }
    }

    func confirmSubmission() {
        guard !isCancelled else { return }
        frontendSubmissionGate.markReady()
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        let response = pendingResponse
        pendingResponse = nil
        response?.resume(returning: nil)
        frontendRequestGate.reset()
        frontendSubmissionGate.reset()
    }
}
