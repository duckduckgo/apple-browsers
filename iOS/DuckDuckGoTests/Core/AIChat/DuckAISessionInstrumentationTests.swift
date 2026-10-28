//
//  DuckAISessionInstrumentationTests.swift
//  DuckDuckGoTests
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
@_spi(Testing) import WideEvent
@testable import DuckDuckGo

@Suite("Duck.ai Session Instrumentation")
struct DuckAISessionInstrumentationTests {

    private static let chatTab: TabUID = "chat-tab"
    private static let otherChatTab: TabUID = "other-chat-tab"
    private static let webTab: TabUID = "web-tab"

    private func makeSUT(isEnabled: Bool = true,
                         completeOrphanedFlowsOnInit: Bool = false,
                         seededFlows: [DuckAISessionWideEventData] = []) -> (DefaultDuckAISessionInstrumentation, WideEventMock) {
        let wideEvent = WideEventMock()
        seededFlows.forEach { wideEvent.startFlow($0) }
        let sut = DefaultDuckAISessionInstrumentation(wideEvent: wideEvent,
                                                      isEnabled: { isEnabled },
                                                      completeOrphanedFlowsOnInit: completeOrphanedFlowsOnInit)
        return (sut, wideEvent)
    }

    private func duckAI(_ uid: TabUID, chatID: String? = nil, path: String = "") -> DuckAISessionTabSnapshot {
        var components = URLComponents(string: "https://duckduckgo.com/\(path)?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4")!
        if let chatID {
            components.queryItems?.append(URLQueryItem(name: "chatID", value: chatID))
        }
        return DuckAISessionTabSnapshot(uid: uid, isDuckAI: true, url: components.url, chatID: chatID)
    }

    private func web(_ uid: TabUID) -> DuckAISessionTabSnapshot {
        DuckAISessionTabSnapshot(uid: uid, isDuckAI: false, url: URL(string: "https://example.com")!, chatID: nil)
    }

    private func started(_ wideEvent: WideEventMock) -> [DuckAISessionWideEventData] {
        wideEvent.started.compactMap { $0 as? DuckAISessionWideEventData }
    }

    private func updates(_ wideEvent: WideEventMock) -> [DuckAISessionWideEventData] {
        wideEvent.updates.compactMap { $0 as? DuckAISessionWideEventData }
    }

    private func completions(_ wideEvent: WideEventMock) -> [(DuckAISessionWideEventData, WideEventStatus)] {
        wideEvent.completions.compactMap { data, status in
            (data as? DuckAISessionWideEventData).map { ($0, status) }
        }
    }

    // MARK: - Starting

    @available(iOS 16, *)
    @Test("When a Duck.ai tab becomes visible then a session starts", .timeLimit(.minutes(1)))
    func whenDuckAITabBecomesVisibleThenSessionStarts() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        #expect(started(wideEvent).count == 1)
        #expect(completions(wideEvent).isEmpty)
    }

    @available(iOS 16, *)
    @Test("When the same snapshot is reported again then nothing happens", .timeLimit(.minutes(1)))
    func whenSameSnapshotRepeatsThenNothingHappens() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc"))
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc"))
        #expect(started(wideEvent).count == 1)
        #expect(updates(wideEvent).isEmpty)
        #expect(completions(wideEvent).isEmpty)
    }

    @available(iOS 16, *)
    @Test("When a web tab becomes visible with no session then nothing starts", .timeLimit(.minutes(1)))
    func whenWebTabVisibleWithoutSessionThenNothingStarts() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(web(Self.webTab))
        #expect(started(wideEvent).isEmpty)
    }

    @available(iOS 16, *)
    @Test("When the feature is disabled then no session starts", .timeLimit(.minutes(1)))
    func whenDisabledThenNothingStarts() {
        let (sut, wideEvent) = makeSUT(isEnabled: false)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        #expect(started(wideEvent).isEmpty)
    }

    // MARK: - Ending

    @available(iOS 16, *)
    @Test("When another tab becomes visible with no pending exit then the session ends as other_navigation", .timeLimit(.minutes(1)))
    func whenAnotherTabVisibleWithoutPendingExitThenOtherNavigation() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.visibleTabDidChange(web(Self.webTab))

        let completed = completions(wideEvent)
        #expect(completed.count == 1)
        #expect(completed.first?.1 == .success(reason: "left_duckai"))
        #expect(completed.first?.0.statusReason == .leftDuckai)
        #expect(completed.first?.0.exitTrigger == .otherNavigation)
    }

    @available(iOS 16, *)
    @Test("When a pending exit was recorded then it becomes the exit trigger", .timeLimit(.minutes(1)))
    func whenPendingExitRecordedThenItIsUsed() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(tabUID: Self.chatTab, trigger: .tabSwitched)
        sut.visibleTabDidChange(web(Self.webTab))
        #expect(completions(wideEvent).first?.0.exitTrigger == .tabSwitched)
    }

    @available(iOS 16, *)
    @Test("When a pending exit is recorded for another tab then it is ignored", .timeLimit(.minutes(1)))
    func whenPendingExitForOtherTabThenIgnored() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(tabUID: Self.webTab, trigger: .tabSwitched)
        sut.visibleTabDidChange(web(Self.webTab))
        #expect(completions(wideEvent).first?.0.exitTrigger == .otherNavigation)
    }

    @available(iOS 16, *)
    @Test("When two pending exits are recorded then the first one wins", .timeLimit(.minutes(1)))
    func whenTwoPendingExitsThenFirstWins() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(tabUID: Self.chatTab, trigger: .searchStarted)
        sut.recordPendingExit(tabUID: Self.chatTab, trigger: .newTabOpened)
        sut.visibleTabDidChange(web(Self.webTab))
        #expect(completions(wideEvent).first?.0.exitTrigger == .searchStarted)
    }

    @available(iOS 16, *)
    @Test("When the same tab stays on Duck.ai after a pending exit then the exit is cleared and the session continues", .timeLimit(.minutes(1)))
    func whenSameTabStaysOnDuckAIThenPendingExitIsCleared() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "one"))
        sut.recordPendingExit(tabUID: Self.chatTab, trigger: .backOrClose)
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "two"))
        #expect(completions(wideEvent).isEmpty)

        sut.visibleTabDidChange(web(Self.webTab))
        #expect(completions(wideEvent).first?.0.exitTrigger == .otherNavigation)
    }

    @available(iOS 16, *)
    @Test("When the same tab navigates to a non-Duck.ai page then the session ends", .timeLimit(.minutes(1)))
    func whenSameTabLeavesDuckAIThenSessionEnds() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(tabUID: Self.chatTab, trigger: .searchStarted)
        sut.visibleTabDidChange(web(Self.chatTab))

        let completed = completions(wideEvent)
        #expect(completed.count == 1)
        #expect(completed.first?.0.exitTrigger == .searchStarted)
        #expect(started(wideEvent).count == 1)
    }

    @available(iOS 16, *)
    @Test("When switching between two Duck.ai tabs then the old session ends and a new one starts", .timeLimit(.minutes(1)))
    func whenSwitchingBetweenDuckAITabsThenOldEndsAndNewStarts() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(tabUID: Self.chatTab, trigger: .tabSwitched)
        sut.visibleTabDidChange(duckAI(Self.otherChatTab))

        #expect(completions(wideEvent).count == 1)
        #expect(completions(wideEvent).first?.0.exitTrigger == .tabSwitched)
        #expect(started(wideEvent).count == 2)
    }

    @available(iOS 16, *)
    @Test("When no tab is visible then the session ends", .timeLimit(.minutes(1)))
    func whenNoTabVisibleThenSessionEnds() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.visibleTabDidChange(nil)
        #expect(completions(wideEvent).count == 1)
        #expect(completions(wideEvent).first?.0.exitTrigger == .otherNavigation)
    }

    @available(iOS 16, *)
    @Test("When a session ended then a later Duck.ai tab starts a new session", .timeLimit(.minutes(1)))
    func whenSessionEndedThenNewSessionCanStart() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.visibleTabDidChange(web(Self.webTab))
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        #expect(started(wideEvent).count == 2)
        #expect(completions(wideEvent).count == 1)
    }

    // MARK: - Background

    @available(iOS 16, *)
    @Test("When the app backgrounds with a session then it completes as CANCELLED app_backgrounded", .timeLimit(.minutes(1)))
    func whenBackgroundedThenCancelledWithAppBackgrounded() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(tabUID: Self.chatTab, trigger: .tabSwitched)
        sut.sessionCancelledByBackground()

        let completed = completions(wideEvent)
        #expect(completed.count == 1)
        #expect(completed.first?.1 == .cancelled)
        #expect(completed.first?.0.statusReason == .appBackgrounded)
        #expect(completed.first?.0.exitTrigger == nil)
    }

    @available(iOS 16, *)
    @Test("When the app backgrounds then a stale pending exit does not leak into the next session", .timeLimit(.minutes(1)))
    func whenBackgroundedThenPendingExitIsCleared() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(tabUID: Self.chatTab, trigger: .tabSwitched)
        sut.sessionCancelledByBackground()

        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.visibleTabDidChange(web(Self.webTab))
        #expect(completions(wideEvent).last?.0.exitTrigger == .otherNavigation)
    }

    @available(iOS 16, *)
    @Test("When the app backgrounds with no session then nothing completes", .timeLimit(.minutes(1)))
    func whenBackgroundedWithoutSessionThenNothingCompletes() {
        let (sut, wideEvent) = makeSUT()
        sut.sessionCancelledByBackground()
        #expect(completions(wideEvent).isEmpty)
    }

    // MARK: - Orphans

    @available(iOS 16, *)
    @Test("When constructed with orphaned flows then they complete as UNKNOWN app_terminated", .timeLimit(.minutes(1)))
    func whenOrphansExistAtInitThenCompletedAsAppTerminated() {
        let orphan = DuckAISessionWideEventData(promptSubmitted: true)
        let (_, wideEvent) = makeSUT(completeOrphanedFlowsOnInit: true, seededFlows: [orphan])

        let completed = completions(wideEvent)
        #expect(completed.count == 1)
        #expect(completed.first?.1 == .unknown(reason: "app_terminated"))
        #expect(completed.first?.0.promptSubmitted == true)
    }

    @available(iOS 16, *)
    @Test("When constructed without the orphan sweep then persisted flows are left alone", .timeLimit(.minutes(1)))
    func whenNoOrphanSweepThenPersistedFlowsUntouched() {
        let (_, wideEvent) = makeSUT(completeOrphanedFlowsOnInit: false, seededFlows: [DuckAISessionWideEventData()])
        #expect(completions(wideEvent).isEmpty)
    }

    // MARK: - Steps

    @available(iOS 16, *)
    @Test("When a prompt is submitted then the step is recorded once", .timeLimit(.minutes(1)))
    func whenPromptSubmittedThenStepRecordedOnce() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.promptSubmitted(tabUID: Self.chatTab)
        sut.promptSubmitted(tabUID: Self.chatTab)

        #expect(updates(wideEvent).count == 1)
        #expect(started(wideEvent).first?.promptSubmitted == true)
    }

    @available(iOS 16, *)
    @Test("When a prompt is submitted in another tab then it is ignored", .timeLimit(.minutes(1)))
    func whenPromptSubmittedInOtherTabThenIgnored() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.promptSubmitted(tabUID: Self.otherChatTab)
        #expect(updates(wideEvent).isEmpty)
        #expect(started(wideEvent).first?.promptSubmitted == false)
    }

    @available(iOS 16, *)
    @Test("When a prompt is submitted with no session then nothing is recorded", .timeLimit(.minutes(1)))
    func whenPromptSubmittedWithoutSessionThenIgnored() {
        let (sut, wideEvent) = makeSUT()
        sut.promptSubmitted(tabUID: Self.chatTab)
        #expect(updates(wideEvent).isEmpty)
    }

    @available(iOS 16, *)
    @Test("When a new chat is created then the step is recorded", .timeLimit(.minutes(1)))
    func whenNewChatCreatedThenStepRecorded() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.newChatCreated(tabUID: Self.chatTab)
        #expect(started(wideEvent).first?.newChatCreated == true)
        #expect(updates(wideEvent).count == 1)
    }

    @available(iOS 16, *)
    @Test("When the session starts with a chat ID then that baseline is not a change", .timeLimit(.minutes(1)))
    func whenSessionStartsWithChatIDThenNotCounted() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc"))
        #expect(started(wideEvent).first?.chatIDChanged == false)
        #expect(updates(wideEvent).isEmpty)
    }

    @available(iOS 16, *)
    @Test("When the chat ID goes from missing to present then chat_id_changed is recorded", .timeLimit(.minutes(1)))
    func whenChatIDAppearsThenChangeRecorded() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc"))
        #expect(started(wideEvent).first?.chatIDChanged == true)
    }

    @available(iOS 16, *)
    @Test("When the chat ID changes to another value then chat_id_changed is recorded", .timeLimit(.minutes(1)))
    func whenChatIDChangesThenChangeRecorded() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc"))
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "def"))
        #expect(started(wideEvent).first?.chatIDChanged == true)
        #expect(completions(wideEvent).isEmpty)
    }

    @available(iOS 16, *)
    @Test("When the URL changes but the chat ID does not then no step is recorded", .timeLimit(.minutes(1)))
    func whenURLChangesWithoutChatIDChangeThenNoStep() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc"))
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc", path: "settings"))
        #expect(started(wideEvent).first?.chatIDChanged == false)
        #expect(updates(wideEvent).isEmpty)
    }

    @available(iOS 16, *)
    @Test("When steps were recorded then they are present on the completed flow", .timeLimit(.minutes(1)))
    func whenStepsRecordedThenPresentOnCompletion() {
        let (sut, wideEvent) = makeSUT()
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.promptSubmitted(tabUID: Self.chatTab)
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc"))
        sut.visibleTabDidChange(web(Self.webTab))

        let data = completions(wideEvent).first?.0
        #expect(data?.promptSubmitted == true)
        #expect(data?.chatIDChanged == true)
        #expect(data?.newChatCreated == false)
    }
}
