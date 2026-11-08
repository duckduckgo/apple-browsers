//
//  ClientToolPermissionCoordinatorTests.swift
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

import Foundation
import Testing
@testable import AIChat

@MainActor
struct ClientToolPermissionCoordinatorTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: ["allow", "always", "never", "decline", "cancel", "futureDecision"])
    func decisionsFinishMatchingCall(decision: String) async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        try harness.answer(harness.source.prompts[0], decision: decision)
        let result = await task.value
        switch decision {
        case "allow", "always":
            #expect(result == .success(callId: "call", value: ["content": "page"]))
            #expect(harness.tool.calls.count == 1)
        case "never", "decline":
            #expect(result == .failure(callId: "call", error: .denied))
            #expect(harness.tool.calls.isEmpty)
        default:
            #expect(result == .failure(callId: "call", error: .cancelled))
            #expect(harness.tool.calls.isEmpty)
        }
        #expect(harness.permissions.writes == (["always", "never"].contains(decision) ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: ["always", "never"])
    func queuedCallsReusePersistentDecision(decision: String) async throws {
        let harness = ClientToolTestHarness()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        let second = try harness.start(callID: "second")
        await harness.clock.waitForRegistrations(2)
        #expect(harness.source.prompts.count == 1)
        try harness.answer(harness.source.prompts[0], decision: decision)
        let firstResult = await first.value
        let secondResult = await second.value
        if decision == "always" {
            #expect(firstResult == .success(callId: "first", value: ["content": "page"]))
            #expect(secondResult == .success(callId: "second", value: ["content": "page"]))
        } else {
            #expect(firstResult == .failure(callId: "first", error: .denied))
            #expect(secondResult == .failure(callId: "second", error: .denied))
        }
        #expect(harness.source.prompts.count == 1)
        #expect(harness.permissions.writes == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: ["allow", "decline", "cancel"])
    func transientDecisionPromptsNextCallInOrder(decision: String) async throws {
        let harness = ClientToolTestHarness()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        let second = try harness.start(callID: "second")
        await harness.clock.waitForRegistrations(2)
        let third = try harness.start(callID: "third")
        await harness.clock.waitForRegistrations(3)
        try harness.answer(harness.source.prompts[0], decision: decision)
        await harness.source.waitForPrompts(2)
        #expect(harness.source.prompts[1].callId == "second")
        try harness.answer(harness.source.prompts[1], decision: "allow")
        await harness.source.waitForPrompts(3)
        #expect(harness.source.prompts[2].callId == "third")
        try harness.answer(harness.source.prompts[2], decision: "allow")
        _ = await first.value
        #expect(await second.value == .success(callId: "second", value: ["content": "page"]))
        #expect(await third.value == .success(callId: "third", value: ["content": "page"]))
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func toolsHaveIndependentPermissionQueues() async throws {
        let harness = ClientToolTestHarness()
        let first = try harness.start()
        await harness.source.waitForPrompts(1)
        let second = try harness.start(callID: "other", name: "searchHistory")
        await harness.source.waitForPrompts(2)
        try harness.answer(harness.source.prompts[1], decision: "allow")
        #expect(await second.value == .success(callId: "other", value: ["content": "page"]))
        #expect(harness.tool.calls.isEmpty)
        try harness.answer(harness.source.prompts[0], decision: "cancel")
        _ = await first.value
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func chatsHaveIndependentPermissionQueuesForTheSameTool() async throws {
        let harness = ClientToolTestHarness()
        let otherSource = ClientToolTestSource()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        let second = try harness.start(callID: "second", source: otherSource)

        await otherSource.waitForPrompts(1)
        try harness.answer(otherSource.prompts[0], decision: "allow", source: otherSource)
        #expect(await second.value == .success(callId: "second", value: ["content": "page"]))
        try harness.answer(harness.source.prompts[0], decision: "cancel")
        #expect(await first.value == .failure(callId: "first", error: .cancelled))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func mismatchesAndDuplicatesCannotPersistOrCompleteAnotherCall() async throws {
        let harness = ClientToolTestHarness()
        let otherSource = ClientToolTestSource()
        let first = try harness.start()
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        let second = try harness.start(source: otherSource)
        await harness.clock.waitForRegistrations(2)
        await otherSource.waitForPrompts(1)
        let prompt = harness.source.prompts[0]
        try harness.answer(prompt, decision: "always", source: otherSource)
        try harness.answer(prompt, decision: "always", callID: "wrong")
        try harness.answer(prompt, decision: "always", requestID: "wrong")
        #expect(harness.permissions.writes == 0)
        try harness.answer(prompt, decision: "allow")
        #expect(otherSource.prompts[0].requestId != prompt.requestId)
        try harness.answer(prompt, decision: "never")
        try harness.answer(otherSource.prompts[0], decision: "always")
        #expect(harness.permissions.writes == 0)
        try harness.answer(otherSource.prompts[0], decision: "allow", source: otherSource)
        #expect(await first.value == .success(callId: "call", value: ["content": "page"]))
        #expect(await second.value == .success(callId: "call", value: ["content": "page"]))
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func queueTimeCountsTowardDeadline() async throws {
        let harness = ClientToolTestHarness()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        harness.clock.advance(to: 30)
        let second = try harness.start(callID: "second")
        await harness.clock.waitForRegistrations(2)
        harness.clock.advance(to: 119)
        try harness.answer(harness.source.prompts[0], decision: "decline")
        await harness.source.waitForPrompts(2)
        harness.clock.advance(to: 150)
        #expect(await first.value == .failure(callId: "first", error: .denied))
        #expect(await second.value == .failure(callId: "second", error: .cancelled))
        try harness.answer(harness.source.prompts[1], decision: "always")
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func lateAnswerAndPromotionCheckTimeBeforeTimerDispatch() async throws {
        let harness = ClientToolTestHarness()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        let second = try harness.start(callID: "second")
        await harness.clock.waitForRegistrations(2)
        harness.clock.advance(to: 120, dispatchTimers: false)
        try harness.answer(harness.source.prompts[0], decision: "always")
        #expect(await first.value == .failure(callId: "first", error: .cancelled))
        #expect(await second.value == .failure(callId: "second", error: .cancelled))
        #expect(harness.source.prompts.count == 1)
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func acceptedPermissionDoesNotExpireBeforeExecutionResumes() async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        try harness.answer(harness.source.prompts[0], decision: "allow")
        harness.clock.advance(to: 121, dispatchTimers: false)
        #expect(await task.value == .success(callId: "call", value: ["content": "page"]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func taskCancellationBeforeRegistrationDoesNotPrompt() async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        task.cancel()
        #expect(await task.value == .failure(callId: "call", error: .cancelled))
        #expect(harness.source.prompts.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func taskCancellationPreventsImmediatePersistentAnswer() async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        task.cancel()
        try harness.answer(harness.source.prompts[0], decision: "always")
        #expect(await task.value == .failure(callId: "call", error: .cancelled))
        #expect(harness.permissions.writes == 0)
        #expect(harness.tool.calls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func cancellationAfterConsentPreventsExecution(cancelTask: Bool) async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        try harness.answer(harness.source.prompts[0], decision: "allow")
        if cancelTask { task.cancel() } else { harness.coordinator.cancelRequests(from: harness.source) }
        #expect(await task.value == .failure(callId: "call", error: .cancelled))
        #expect(harness.tool.calls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sourceCancellationOnlyRemovesThatSourcesQueue() async throws {
        let harness = ClientToolTestHarness()
        let otherSource = ClientToolTestSource()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        let second = try harness.start(callID: "second")
        await harness.clock.waitForRegistrations(2)
        let third = try harness.start(callID: "third", source: otherSource)
        await harness.clock.waitForRegistrations(3)
        await otherSource.waitForPrompts(1)
        harness.coordinator.cancelRequests(from: harness.source)
        #expect(harness.source.prompts.count == 1)
        try harness.answer(otherSource.prompts[0], decision: "allow", source: otherSource)
        #expect(await first.value == .failure(callId: "first", error: .cancelled))
        #expect(await second.value == .failure(callId: "second", error: .cancelled))
        #expect(await third.value == .success(callId: "third", value: ["content": "page"]))
        let reused = try harness.start(callID: "newDocument")
        await harness.source.waitForPrompts(2)
        try harness.answer(harness.source.prompts[1], decision: "allow")
        #expect(await reused.value == .success(callId: "newDocument", value: ["content": "page"]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func synchronousAnswerSurvivesFalseDeliveryResult() async throws {
        let harness = ClientToolTestHarness()
        harness.source.onPush = { prompt in
            try? harness.answer(prompt, decision: "allow")
            return false
        }
        let request = try harness.request()
        let result = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: harness.source)
        #expect(result == .success(callId: "call", value: ["content": "page"]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func failedDeliveryCancelsWaitingCall() async throws {
        let harness = ClientToolTestHarness()
        harness.source.onPush = { _ in false }
        let request = try harness.request()
        let result = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: harness.source)
        #expect(result == .failure(callId: "call", error: .cancelled))
        #expect(harness.tool.calls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sourceCanCancelReentrantlyWhilePushing() async throws {
        let harness = ClientToolTestHarness()
        harness.source.onPush = { _ in
            harness.coordinator.cancelRequests(from: harness.source)
            return true
        }
        let request = try harness.request()
        let result = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: harness.source)
        #expect(result == .failure(callId: "call", error: .cancelled))
        #expect(harness.tool.calls.isEmpty)
    }
}
