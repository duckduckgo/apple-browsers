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
    @Test(.timeLimit(.minutes(1)), arguments: [ClientToolPermissionDecision.allowOnce, .always, .never, .dismiss])
    func decisionsFinishMatchingCall(decision: ClientToolPermissionDecision) async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: decision)
        let result = await task.value
        switch decision {
        case .allowOnce, .always:
            #expect(result == .success(callId: "call", value: ["content": "page"]))
            #expect(harness.tool.calls.count == 1)
        case .never:
            #expect(result == .failure(callId: "call", error: .denied))
            #expect(harness.tool.calls.isEmpty)
        case .dismiss:
            #expect(result == .failure(callId: "call", error: .cancelled))
            #expect(harness.tool.calls.isEmpty)
        }
        #expect(harness.permissions.writes == ([.always, .never].contains(decision) ? 1 : 0))
        #expect(harness.source.withdrawn.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func onlyCallsThatRunWithoutAskingAreIndicated() async throws {
        let harness = ClientToolTestHarness()
        harness.otherTool.permissionMode = .auto

        _ = await (try harness.start(callID: "auto", name: "searchHistory")).value
        #expect(harness.source.indicated == ["searchHistory"])

        let asked = try harness.start(callID: "asked")
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: .always)
        _ = await asked.value
        #expect(harness.source.indicated == ["searchHistory"])

        _ = await (try harness.start(callID: "allowed")).value
        #expect(harness.source.indicated == ["searchHistory", "readTabContent"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [ClientToolPermissionDecision.always, .never])
    func queuedCallsReusePersistentDecision(decision: ClientToolPermissionDecision) async throws {
        let harness = ClientToolTestHarness()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        let second = try harness.start(callID: "second")
        await harness.clock.waitForRegistrations(2)
        #expect(harness.source.prompts.count == 1)
        harness.answer(harness.source.prompts[0], decision: decision)
        let firstResult = await first.value
        let secondResult = await second.value
        if decision == .always {
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
    @Test(.timeLimit(.minutes(1)), arguments: [ClientToolPermissionDecision.allowOnce, .dismiss])
    func transientDecisionPromptsNextCallInOrder(decision: ClientToolPermissionDecision) async throws {
        let harness = ClientToolTestHarness()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        let second = try harness.start(callID: "second")
        await harness.clock.waitForRegistrations(2)
        let third = try harness.start(callID: "third")
        await harness.clock.waitForRegistrations(3)
        harness.answer(harness.source.prompts[0], decision: decision)
        await harness.source.waitForPrompts(2)
        #expect(harness.source.prompts[1].callID == "second")
        harness.answer(harness.source.prompts[1], decision: .allowOnce)
        await harness.source.waitForPrompts(3)
        #expect(harness.source.prompts[2].callID == "third")
        harness.answer(harness.source.prompts[2], decision: .allowOnce)
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
        harness.answer(harness.source.prompts[1], decision: .allowOnce)
        #expect(await second.value == .success(callId: "other", value: ["content": "page"]))
        #expect(harness.tool.calls.isEmpty)
        harness.answer(harness.source.prompts[0], decision: .dismiss)
        _ = await first.value
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func oneToolPromptsOnceAtATimeAcrossChats() async throws {
        let harness = ClientToolTestHarness()
        let otherSource = ClientToolTestSource()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        let second = try harness.start(callID: "second", source: otherSource)
        await harness.clock.waitForRegistrations(2)
        #expect(otherSource.prompts.isEmpty)

        harness.answer(harness.source.prompts[0], decision: .dismiss)
        #expect(await first.value == .failure(callId: "first", error: .cancelled))
        await otherSource.waitForPrompts(1)
        harness.answer(otherSource.prompts[0], decision: .allowOnce, source: otherSource)
        #expect(await second.value == .success(callId: "second", value: ["content": "page"]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func mismatchesAndDuplicatesCannotPersistOrCompleteAnotherCall() async throws {
        let harness = ClientToolTestHarness()
        let otherSource = ClientToolTestSource()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        let prompt = harness.source.prompts[0]
        harness.answer(prompt, decision: .always, source: otherSource)
        harness.answer(prompt, decision: .always, callID: "wrong")
        harness.answer(prompt, decision: .always, requestID: "wrong")
        #expect(harness.permissions.writes == 0)
        #expect(harness.tool.calls.isEmpty)
        harness.answer(prompt, decision: .allowOnce)
        harness.answer(prompt, decision: .never)
        #expect(await task.value == .success(callId: "call", value: ["content": "page"]))
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func queueTimeCountsTowardDeadlineAndAnUnansweredPromptIsDenied() async throws {
        let harness = ClientToolTestHarness()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        harness.clock.advance(to: 30)
        let second = try harness.start(callID: "second")
        await harness.clock.waitForRegistrations(2)
        harness.clock.advance(to: 119)
        harness.answer(harness.source.prompts[0], decision: .dismiss)
        await harness.source.waitForPrompts(2)
        harness.clock.advance(to: 150)
        #expect(await first.value == .failure(callId: "first", error: .cancelled))
        #expect(await second.value == .failure(callId: "second", error: .denied))
        #expect(harness.source.withdrawn == [harness.source.prompts[1].requestID])
        harness.answer(harness.source.prompts[1], decision: .always)
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
        harness.answer(harness.source.prompts[0], decision: .always)
        #expect(await first.value == .failure(callId: "first", error: .denied))
        #expect(await second.value == .failure(callId: "second", error: .denied))
        #expect(harness.source.prompts.count == 1)
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func acceptedPermissionDoesNotExpireBeforeExecutionResumes() async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: .allowOnce)
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
    func taskCancellationWithdrawsPromptAndIgnoresLateAnswer() async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        task.cancel()
        #expect(await task.value == .failure(callId: "call", error: .cancelled))
        #expect(harness.source.withdrawn == [harness.source.prompts[0].requestID])
        harness.answer(harness.source.prompts[0], decision: .always)
        #expect(harness.permissions.writes == 0)
        #expect(harness.tool.calls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func cancellationAfterConsentPreventsExecution(cancelTask: Bool) async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: .allowOnce)
        if cancelTask { task.cancel() } else { harness.coordinator.cancelRequests(from: harness.source) }
        #expect(await task.value == .failure(callId: "call", error: .cancelled))
        #expect(harness.tool.calls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func chatGoneWithdrawsItsPromptAndPromotesAnotherChat() async throws {
        let harness = ClientToolTestHarness()
        let otherSource = ClientToolTestSource()
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        let second = try harness.start(callID: "second")
        await harness.clock.waitForRegistrations(2)
        let third = try harness.start(callID: "third", source: otherSource)
        await harness.clock.waitForRegistrations(3)
        harness.coordinator.cancelRequests(from: harness.source)
        #expect(harness.source.prompts.count == 1)
        #expect(harness.source.withdrawn == [harness.source.prompts[0].requestID])
        await otherSource.waitForPrompts(1)
        harness.answer(otherSource.prompts[0], decision: .allowOnce, source: otherSource)
        #expect(await first.value == .failure(callId: "first", error: .cancelled))
        #expect(await second.value == .failure(callId: "second", error: .cancelled))
        #expect(await third.value == .success(callId: "third", value: ["content": "page"]))
        let reused = try harness.start(callID: "newDocument")
        await harness.source.waitForPrompts(2)
        harness.answer(harness.source.prompts[1], decision: .allowOnce)
        #expect(await reused.value == .success(callId: "newDocument", value: ["content": "page"]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func synchronousAnswerSurvivesFalseDeliveryResult() async throws {
        let harness = ClientToolTestHarness()
        harness.source.onPush = { prompt in
            harness.answer(prompt, decision: .allowOnce)
            return false
        }
        let request = try harness.request()
        let result = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPrompter: harness.source)
        #expect(result == .success(callId: "call", value: ["content": "page"]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func promptThatCannotBeShownCancelsWaitingCall() async throws {
        let harness = ClientToolTestHarness()
        harness.source.onPush = { _ in false }
        let request = try harness.request()
        let result = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPrompter: harness.source)
        #expect(result == .failure(callId: "call", error: .cancelled))
        #expect(harness.tool.calls.isEmpty)
        #expect(harness.source.withdrawn.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: zip([JSONValue.object([:]), ["tabId": "owner"], ["tabId": "other"]], [false, false, true]))
    func promptSaysWhetherTheCallTargetsAnotherTab(input: JSONValue, targetsOtherTab: Bool) async throws {
        let harness = ClientToolTestHarness()
        let request = try harness.request(input: input)
        let task = Task { await harness.invoker.invokeClientTool(request, context: harness.context, permissionPrompter: harness.source) }
        await harness.source.waitForPrompts(1)
        #expect(harness.source.prompts[0].targetsOtherTab == targetsOtherTab)
        harness.answer(harness.source.prompts[0], decision: .dismiss)
        _ = await task.value
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func prompterCanCancelReentrantlyWhilePresenting() async throws {
        let harness = ClientToolTestHarness()
        harness.source.onPush = { _ in
            harness.coordinator.cancelRequests(from: harness.source)
            return true
        }
        let request = try harness.request()
        let result = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPrompter: harness.source)
        #expect(result == .failure(callId: "call", error: .cancelled))
        #expect(harness.tool.calls.isEmpty)
    }
}
