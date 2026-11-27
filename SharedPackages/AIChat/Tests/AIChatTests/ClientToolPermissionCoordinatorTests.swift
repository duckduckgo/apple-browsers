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
    @Test(.timeLimit(.minutes(1)), arguments: [ClientToolPermissionDecision.allowOnce, .always, .never, .dontAllow, .dismiss])
    func decisionsFinishMatchingCall(decision: ClientToolPermissionDecision) async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: decision)
        let result = await task.value
        switch decision {
        case .allowOnce, .allowForChat, .allowAccess, .always:
            #expect(result == .success(callId: "call", value: ["content": "page"]))
            #expect(harness.tool.calls.count == 1)
        case .never, .dontAllow:
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
    func onlyCallsThatRunReportTheirUse() async throws {
        let harness = ClientToolTestHarness()
        harness.otherTool.permissionMode = .auto

        _ = await (try harness.start(callID: "auto", name: "searchHistory")).value
        #expect(harness.source.uses == ["start searchHistory", "end"])

        let dismissed = try harness.start(callID: "dismissed")
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: .dismiss)
        _ = await dismissed.value
        #expect(harness.source.uses == ["start searchHistory", "end"])

        let allowed = try harness.start(callID: "allowed")
        await harness.source.waitForPrompts(2)
        harness.answer(harness.source.prompts[1], decision: .allowOnce)
        _ = await allowed.value
        #expect(harness.source.uses == ["start searchHistory", "end", "start readTabContent", "end"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func cancellingARunningCallEndsItsUseAsCancelled() async throws {
        let harness = ClientToolTestHarness()
        harness.tool.permissionMode = .auto
        var release: CheckedContinuation<Void, Never>?
        harness.tool.onExecute = { await withCheckedContinuation { release = $0 } }

        let task = try harness.start()
        while harness.tool.calls.isEmpty { await Task.yield() }
        task.cancel()
        _ = await task.value
        release?.resume()

        #expect(harness.source.uses == ["start readTabContent", "end cancelled"])
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

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func toolThatAsksEveryTimeIgnoresAndNeverStoresAlways() async throws {
        let harness = ClientToolTestHarness()
        harness.tool.asksEveryTime = true
        harness.permissions.storedDecisions["readTabContent"] = .allow

        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        #expect(!harness.source.prompts[0].offersAlways)
        harness.answer(harness.source.prompts[0], decision: .always)
        #expect(await first.value == .success(callId: "first", value: ["content": "page"]))
        #expect(harness.permissions.writes == 0)

        let second = try harness.start(callID: "second")
        await harness.source.waitForPrompts(2)
        harness.answer(harness.source.prompts[1], decision: .dismiss)
        _ = await second.value
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func targetChangedSinceConsentDoesNotRun() async throws {
        let harness = ClientToolTestHarness()
        harness.tool.target = "https://a.example/"

        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        #expect(harness.source.prompts[0].target == "https://a.example/")
        harness.tool.target = "https://b.example/"
        harness.answer(harness.source.prompts[0], decision: .allowOnce)

        #expect(await task.value == .failure(callId: "call", error: .notFound))
        #expect(harness.tool.calls.isEmpty)
    }
}

// MARK: - Prompt instrumentation

@MainActor
final class RecordingBrowserToolsInstrumentation: BrowserToolsInstrumentation {
    struct Prompt: Equatable {
        let tool: String
        let answer: BrowserToolPromptAnswer
        let number: Int?
        let timeToAnswer: TimeInterval
    }
    var prompts: [Prompt] = []
    var accessRequests: [BrowserToolAccessRequestOutcome] = []

    func accessRequestDidFinish(_ outcome: BrowserToolAccessRequestOutcome) {
        accessRequests.append(outcome)
    }

    func toolCallDidFinish(tool: String, response: ExecuteClientToolResponse, trace: BrowserToolCallTrace) {}

    func promptDidClose(tool: String, answer: BrowserToolPromptAnswer, promptNumberInChat: Int?, timeToAnswer: TimeInterval) {
        prompts.append(Prompt(tool: tool, answer: answer, number: promptNumberInChat, timeToAnswer: timeToAnswer))
    }
}

@MainActor
struct ClientToolPromptInstrumentationTests {

    private func start(_ harness: ClientToolTestHarness, callID: String, tool: String = "readTabContent",
                       chatID: String? = nil) throws -> Task<ExecuteClientToolResponse, Never> {
        var fields: [String: JSONValue] = ["callId": .string(callID), "capability": ["name": .string(tool), "version": 1], "input": [:]]
        fields["chatId"] = chatID.map(JSONValue.string)
        let request = try JSONDecoder().decode(ExecuteClientToolRequest.self, from: JSONEncoder().encode(JSONValue.object(fields)))
        return Task { await harness.invoker.invokeClientTool(request, context: harness.context, permissionPrompter: harness.source) }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [
        (ClientToolPermissionDecision.allowOnce, BrowserToolPromptAnswer.allowOnce), (.always, .always), (.never, .never), (.dontAllow, .dontAllow), (.dismiss, .dismiss)
    ])
    func anAnsweredPromptReportsItsAnswerAndTimeWithoutAChatNumber(decision: ClientToolPermissionDecision,
                                                                   answer: BrowserToolPromptAnswer) async throws {
        let harness = ClientToolTestHarness()
        let instrumentation = RecordingBrowserToolsInstrumentation()
        harness.coordinator.instrumentation = instrumentation
        harness.clock.advance(to: 10)
        let call = try start(harness, callID: "call")
        await harness.source.waitForPrompts(1)
        harness.clock.advance(to: 15, dispatchTimers: false)

        harness.answer(harness.source.prompts[0], decision: decision)
        _ = await call.value

        #expect(instrumentation.prompts == [.init(tool: "readTabContent", answer: answer, number: nil, timeToAnswer: 5)])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func promptsInAChatAreNumberedUntilTheGrantsAreRevoked() async throws {
        let harness = ClientToolTestHarness()
        harness.configuration.isRequestAccessEnabled = true
        let instrumentation = RecordingBrowserToolsInstrumentation()
        harness.coordinator.instrumentation = instrumentation

        let first = try start(harness, callID: "first", chatID: "chat")
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: .allowForChat)
        _ = await first.value
        _ = await (try start(harness, callID: "granted", chatID: "chat")).value
        let second = try start(harness, callID: "second", tool: "searchHistory", chatID: "chat")
        await harness.source.waitForPrompts(2)
        harness.answer(harness.source.prompts[1], decision: .never)
        _ = await second.value
        let otherChat = try start(harness, callID: "other", chatID: "other-chat")
        await harness.source.waitForPrompts(3)
        harness.answer(harness.source.prompts[2], decision: .allowOnce)
        _ = await otherChat.value
        harness.coordinator.revokeChatGrants()
        let afterRevoke = try start(harness, callID: "after", chatID: "chat")
        await harness.source.waitForPrompts(4)
        harness.answer(harness.source.prompts[3], decision: .dismiss)
        _ = await afterRevoke.value

        #expect(instrumentation.prompts.map(\.answer) == [.allowForChat, .never, .allowOnce, .dismiss])
        #expect(instrumentation.prompts.map(\.number) == [1, 2, 1, 1])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func anUnansweredPromptReportsTimeoutAndACancelledCallReportsWithdrawn() async throws {
        let harness = ClientToolTestHarness()
        let instrumentation = RecordingBrowserToolsInstrumentation()
        harness.coordinator.instrumentation = instrumentation

        let unanswered = try start(harness, callID: "unanswered")
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        harness.clock.advance(to: 121)
        _ = await unanswered.value
        let cancelled = try start(harness, callID: "cancelled")
        await harness.source.waitForPrompts(2)
        harness.clock.advance(to: 124, dispatchTimers: false)
        cancelled.cancel()
        _ = await cancelled.value

        #expect(instrumentation.prompts == [
            .init(tool: "readTabContent", answer: .timeout, number: nil, timeToAnswer: 121),
            .init(tool: "readTabContent", answer: .withdrawn, number: nil, timeToAnswer: 3)
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func aRequestAccessPromptIsNotReportedAsAToolPrompt() async throws {
        let harness = ClientToolTestHarness()
        harness.configuration.isRequestAccessEnabled = true
        let instrumentation = RecordingBrowserToolsInstrumentation()
        harness.coordinator.instrumentation = instrumentation
        var fields: [String: JSONValue] = ["callId": "access", "capability": ["name": "requestAccess", "version": 1],
                                           "input": ["capabilities": ["searchHistory"]]]
        fields["chatId"] = "chat"
        let request = try JSONDecoder().decode(ExecuteClientToolRequest.self, from: JSONEncoder().encode(JSONValue.object(fields)))

        let access = Task { await harness.invoker.invokeClientTool(request, context: harness.context, permissionPrompter: harness.source) }
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: .allowAccess(excluding: []))
        _ = await access.value

        #expect(instrumentation.prompts.isEmpty)
    }

    // MARK: requestAccess

    private func requestAccess(_ harness: ClientToolTestHarness, _ names: [String], chatID: String? = "chat",
                               context: BrowserToolCallContext? = nil) throws -> Task<ExecuteClientToolResponse, Never> {
        var fields: [String: JSONValue] = ["callId": "access", "capability": ["name": "requestAccess", "version": 1],
                                           "input": ["capabilities": .array(names.map(JSONValue.string))]]
        fields["chatId"] = chatID.map(JSONValue.string)
        let request = try JSONDecoder().decode(ExecuteClientToolRequest.self, from: JSONEncoder().encode(JSONValue.object(fields)))
        return Task { await harness.invoker.invokeClientTool(request, context: context ?? harness.context, permissionPrompter: harness.source) }
    }

    private func accessHarness() -> (ClientToolTestHarness, RecordingBrowserToolsInstrumentation) {
        let harness = ClientToolTestHarness()
        harness.configuration.isRequestAccessEnabled = true
        let instrumentation = RecordingBrowserToolsInstrumentation()
        harness.invoker.instrumentation = instrumentation
        return (harness, instrumentation)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func allowingAccessWithAToolRemovedReportsEachToolsResult() async throws {
        let (harness, instrumentation) = accessHarness()
        harness.permissions.storedDecisions["searchHistory"] = .allow

        let call = try requestAccess(harness, ["readTabContent", "searchHistory", "pinTab", "listOpenTabs"])
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: .allowAccess(excluding: []))
        _ = await call.value

        #expect(instrumentation.accessRequests == [BrowserToolAccessRequestOutcome(
            decision: .allow, requested: 4, asked: 1, removed: 0,
            results: [("readTabContent", .granted), ("searchHistory", .alreadyAllowed), ("pinTab", .unavailable), ("listOpenTabs", .unavailable)])])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func aToolTheUserTakesOutIsRemoved() async throws {
        let (harness, instrumentation) = accessHarness()

        let call = try requestAccess(harness, ["readTabContent", "searchHistory"])
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: .allowAccess(excluding: ["searchHistory"]))
        _ = await call.value

        #expect(instrumentation.accessRequests.map(\.removed) == [1])
        #expect(instrumentation.accessRequests.first?.results.map(\.result) == [.granted, .removed])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [
        (ClientToolPermissionDecision.dontAllow, BrowserToolAccessRequestOutcome.Decision.dontAllow), (.never, .dontAllow), (.dismiss, .dismiss)
    ])
    func aRefusedPromptReportsItsDecisionAndDeniesTheAskedTools(decision: ClientToolPermissionDecision,
                                                                expected: BrowserToolAccessRequestOutcome.Decision) async throws {
        let (harness, instrumentation) = accessHarness()
        harness.permissions.storedDecisions["searchHistory"] = .deny

        let call = try requestAccess(harness, ["readTabContent", "searchHistory"])
        await harness.source.waitForPrompts(1)
        harness.answer(harness.source.prompts[0], decision: decision)
        _ = await call.value

        #expect(instrumentation.accessRequests == [BrowserToolAccessRequestOutcome(
            decision: expected, requested: 2, asked: 1, removed: 0, results: [("readTabContent", .denied), ("searchHistory", .never)])])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func anUnansweredOrWithdrawnPromptIsReportedAsSuch() async throws {
        let (harness, instrumentation) = accessHarness()

        let unanswered = try requestAccess(harness, ["readTabContent"])
        await harness.source.waitForPrompts(1)
        await harness.clock.waitForRegistrations(1)
        harness.clock.advance(to: 121)
        _ = await unanswered.value
        let withdrawn = try requestAccess(harness, ["readTabContent"])
        await harness.source.waitForPrompts(2)
        harness.coordinator.cancelRequests(from: harness.source)
        _ = await withdrawn.value

        #expect(instrumentation.accessRequests.map(\.decision) == [.timeout, .withdrawn])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func noPromptInvalidUnavailableAndFireAreReportedWithoutAsking() async throws {
        let (harness, instrumentation) = accessHarness()
        harness.permissions.storedDecisions["readTabContent"] = .allow

        _ = await (try requestAccess(harness, ["readTabContent"])).value
        _ = await (try requestAccess(harness, ["readTabContent"], chatID: nil)).value
        _ = await (try requestAccess(harness, ["readTabContent"], context: BrowserToolCallContext(ownerTabID: "owner", isBurner: true))).value
        harness.configuration.isRequestAccessEnabled = false
        _ = await (try requestAccess(harness, ["readTabContent"])).value

        #expect(instrumentation.accessRequests == [
            BrowserToolAccessRequestOutcome(decision: .noPrompt, requested: 1, asked: 0, removed: 0, results: [("readTabContent", .alreadyAllowed)]),
            BrowserToolAccessRequestOutcome(decision: .invalid),
            BrowserToolAccessRequestOutcome(decision: .unavailable)
        ])
        #expect(harness.source.prompts.isEmpty)
    }
}
