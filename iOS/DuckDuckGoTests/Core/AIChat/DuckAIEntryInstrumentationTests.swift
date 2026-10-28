//
//  DuckAIEntryInstrumentationTests.swift
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

@Suite("Duck.ai Entry Instrumentation")
final class DuckAIEntryInstrumentationTests {

    private static let chatTab: TabUID = "chat-tab"
    private static let otherTab: TabUID = "other-tab"

    private var clock = Date(timeIntervalSince1970: 1_000)
    private let wideEvent = WideEventMock()

    private func makeSUT(isEnabled: Bool = true,
                         completeOrphanedFlowsOnInit: Bool = false) -> DefaultDuckAIEntryInstrumentation {
        DefaultDuckAIEntryInstrumentation(wideEvent: wideEvent,
                                          isEnabled: { isEnabled },
                                          now: { [unowned self] in clock },
                                          completeOrphanedFlowsOnInit: completeOrphanedFlowsOnInit)
    }

    private func advance(seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    private func duckAI(_ uid: TabUID, chatID: String? = nil) -> DuckAISessionTabSnapshot {
        DuckAISessionTabSnapshot(uid: uid, isDuckAI: true, url: URL(string: "https://duck.ai/chat"), chatID: chatID)
    }

    private func web(_ uid: TabUID) -> DuckAISessionTabSnapshot {
        DuckAISessionTabSnapshot(uid: uid, isDuckAI: false, url: URL(string: "https://example.com"), chatID: nil)
    }

    private func startTabEntry(_ sut: DefaultDuckAIEntryInstrumentation, source: AIChatEntryPointSource = .addressBarPrompt) {
        sut.entryStarted(source: source, hasPrompt: true, surface: .duckAITab, chatState: nil)
    }

    private func startSheetEntry(_ sut: DefaultDuckAIEntryInstrumentation) {
        sut.entryStarted(source: .contextualChat, hasPrompt: false, surface: .contextualSheet, chatState: .existing)
    }

    private var started: [DuckAIEntryWideEventData] {
        wideEvent.started.compactMap { $0 as? DuckAIEntryWideEventData }
    }

    private var completions: [(DuckAIEntryWideEventData, WideEventStatus)] {
        wideEvent.completions.compactMap { data, status in
            (data as? DuckAIEntryWideEventData).map { ($0, status) }
        }
    }

    // MARK: - Starting

    @available(iOS 16, *)
    @Test("An entry point starts an entry with its context", .timeLimit(.minutes(1)))
    func entryPointStartsEntry() {
        let sut = makeSUT()
        sut.entryStarted(source: .chatHistoryOpenChat, hasPrompt: false, surface: .duckAITab, chatState: nil)

        #expect(started.count == 1)
        #expect(started.first?.source == "chat_history_open_chat")
        #expect(started.first?.hasPrompt == false)
        #expect(started.first?.chatState == nil)
        #expect(started.first?.surface == .duckAITab)
        #expect(completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("A tab entry reads its chat state when its Duck.ai tab is first shown",
          .timeLimit(.minutes(1)),
          arguments: [(nil, DuckAIEntryWideEventData.ChatState.new), ("abc", .existing)] as [(String?, DuckAIEntryWideEventData.ChatState)])
    func tabEntryReadsChatStateOnFirstShow(chatID: String?, expected: DuckAIEntryWideEventData.ChatState) {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.visibleTabDidChange(web(Self.otherTab))
        #expect(started.first?.chatState == nil)

        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: chatID))
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: chatID == nil ? "later" : nil))
        #expect(started.first?.chatState == expected)
    }

    @available(iOS 16, *)
    @Test("A sheet entry keeps the chat state it started with", .timeLimit(.minutes(1)))
    func sheetEntryKeepsItsChatState() {
        let sut = makeSUT()
        startSheetEntry(sut)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        #expect(started.first?.chatState == .existing)
    }

    @available(iOS 16, *)
    @Test("When the flag is off then no entry starts", .timeLimit(.minutes(1)))
    func flagOffStartsNothing() {
        let sut = makeSUT(isEnabled: false)
        startTabEntry(sut)
        #expect(started.isEmpty)
    }

    @available(iOS 16, *)
    @Test("A second entry point ends the first as new_entry and starts another", .timeLimit(.minutes(1)))
    func secondEntryEndsFirstAsNewEntry() {
        let sut = makeSUT()
        startTabEntry(sut, source: .addressBarPrompt)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(.newTabOpened, tabUID: Self.chatTab)
        advance(seconds: 2)
        startTabEntry(sut, source: .duckAINewChat)

        #expect(started.map(\.source) == ["address_bar_prompt", "duck_ai_new_chat"])
        #expect(completions.count == 1)
        #expect(completions.first?.0.statusReason == .newEntry)
        #expect(completions.first?.0.jsonParameters()["feature.data.ext.exit_trigger"] == nil)
        #expect(completions.first?.0.jsonParameters()["feature.data.ext.time_in_duckai_ms_bucketed"] as? String == "1000")
        guard case .success(let reason) = completions.first?.1 else {
            Issue.record("Expected SUCCESS")
            return
        }
        #expect(reason == "new_entry")
    }

    // MARK: - Leaving a tab entry

    @available(iOS 16, *)
    @Test("Screens shown before the Duck.ai tab loads don't end the entry", .timeLimit(.minutes(1)))
    func screensBeforeDuckAITabDontEnd() {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.visibleTabDidChange(web(Self.otherTab))
        sut.visibleTabDidChange(nil)
        #expect(completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Changing chats in the same Duck.ai tab doesn't end the entry", .timeLimit(.minutes(1)))
    func chatChangeInSameTabDoesntEnd() {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc"))
        #expect(completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Leaving the Duck.ai tab ends the entry with the recorded trigger", .timeLimit(.minutes(1)))
    func leavingEndsWithRecordedTrigger() {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(.tabSwitched, tabUID: Self.chatTab)
        sut.recordPendingExit(.newTabOpened, tabUID: Self.chatTab)
        sut.visibleTabDidChange(duckAI(Self.otherTab))

        #expect(completions.count == 1)
        #expect(completions.first?.0.statusReason == .leftDuckai)
        #expect(completions.first?.0.exitTrigger == .tabSwitched)
        guard case .success(let reason) = completions.first?.1 else {
            Issue.record("Expected SUCCESS")
            return
        }
        #expect(reason == "left_duckai")
    }

    @available(iOS 16, *)
    @Test("Leaving without a recorded action reports other_navigation", .timeLimit(.minutes(1)))
    func leavingWithoutActionIsOtherNavigation() {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.visibleTabDidChange(web(Self.chatTab))
        #expect(completions.first?.0.exitTrigger == .otherNavigation)
    }

    @available(iOS 16, *)
    @Test("An action that stayed in Duck.ai doesn't become the exit trigger", .timeLimit(.minutes(1)))
    func actionThatStayedIsDiscarded() {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(.searchStarted, tabUID: Self.chatTab)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        #expect(completions.isEmpty)

        sut.visibleTabDidChange(duckAI(Self.chatTab, chatID: "abc"))
        sut.visibleTabDidChange(web(Self.chatTab))
        #expect(completions.first?.0.exitTrigger == .otherNavigation)
    }

    // MARK: - Prompts

    @available(iOS 16, *)
    @Test("The first prompt in the entry's tab is recorded with its time", .timeLimit(.minutes(1)))
    func firstPromptIsRecordedWithTime() {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        advance(seconds: 12)
        sut.promptSubmitted(tabUID: Self.chatTab)
        advance(seconds: 60)
        sut.promptSubmitted(tabUID: Self.chatTab)
        sut.visibleTabDidChange(nil)

        let params = completions.first?.0.jsonParameters()
        #expect(params?["feature.data.ext.prompt_submitted"] as? Bool == true)
        #expect(params?["feature.data.ext.time_to_first_prompt_ms_bucketed"] as? String == "10000")
        #expect(params?["feature.data.ext.time_in_duckai_ms_bucketed"] as? String == "60000")
        #expect(wideEvent.updates.count == 2)
    }

    @available(iOS 16, *)
    @Test("A prompt from another tab is ignored", .timeLimit(.minutes(1)))
    func promptFromAnotherTabIsIgnored() {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.promptSubmitted(tabUID: Self.otherTab)
        sut.sheetPromptSubmitted()
        sut.visibleTabDidChange(nil)

        let params = completions.first?.0.jsonParameters()
        #expect(params?["feature.data.ext.prompt_submitted"] as? Bool == false)
        #expect(params?["feature.data.ext.time_to_first_prompt_ms_bucketed"] == nil)
    }

    // MARK: - Contextual sheet

    @available(iOS 16, *)
    @Test("A sheet entry records its prompt and ends when the sheet closes", .timeLimit(.minutes(1)))
    func sheetEntryEndsOnDismiss() {
        let sut = makeSUT()
        startSheetEntry(sut)
        sut.visibleTabDidChange(web(Self.otherTab))
        sut.promptSubmitted(tabUID: Self.otherTab)
        advance(seconds: 3)
        sut.sheetPromptSubmitted()
        #expect(completions.isEmpty)

        sut.sheetDismissed(exitTrigger: nil)
        #expect(completions.count == 1)
        #expect(completions.first?.0.surface == .contextualSheet)
        #expect(completions.first?.0.statusReason == .leftDuckai)
        #expect(completions.first?.0.exitTrigger == .backOrClose)
        #expect(completions.first?.0.jsonParameters()["feature.data.ext.time_to_first_prompt_ms_bucketed"] as? String == "1000")
    }

    @available(iOS 16, *)
    @Test("A sheet closed by another action reports that action", .timeLimit(.minutes(1)))
    func sheetClosedByActionReportsIt() {
        let sut = makeSUT()
        startSheetEntry(sut)
        sut.recordPendingExit(.tabSwitched, tabUID: Self.otherTab)
        sut.sheetDismissed(exitTrigger: nil)
        #expect(completions.first?.0.exitTrigger == .tabSwitched)
    }

    @available(iOS 16, *)
    @Test("A deleted chat closes the sheet entry as chat_deleted, over any earlier action", .timeLimit(.minutes(1)))
    func deletedChatClosesSheetAsChatDeleted() {
        let sut = makeSUT()
        startSheetEntry(sut)
        sut.recordPendingExit(.searchStarted, tabUID: Self.otherTab)
        sut.sheetDismissed(exitTrigger: .chatDeleted)
        #expect(completions.first?.0.exitTrigger == .chatDeleted)
    }

    @available(iOS 16, *)
    @Test("An action followed by a new page under the open sheet doesn't become its exit trigger", .timeLimit(.minutes(1)))
    func pageChangeUnderSheetDiscardsAction() {
        let sut = makeSUT()
        startSheetEntry(sut)
        sut.visibleTabDidChange(web(Self.otherTab))
        sut.recordPendingExit(.searchStarted, tabUID: Self.otherTab)
        sut.visibleTabDidChange(web(Self.otherTab))
        sut.visibleTabDidChange(DuckAISessionTabSnapshot(uid: Self.otherTab, isDuckAI: false, url: URL(string: "https://duckduckgo.com/?q=a"), chatID: nil))
        sut.sheetDismissed(exitTrigger: nil)
        #expect(completions.first?.0.exitTrigger == .backOrClose)
    }

    @available(iOS 16, *)
    @Test("Switching tabs with the sheet open keeps the recorded action", .timeLimit(.minutes(1)))
    func tabSwitchUnderSheetKeepsAction() {
        let sut = makeSUT()
        startSheetEntry(sut)
        sut.visibleTabDidChange(web(Self.otherTab))
        sut.recordPendingExit(.tabSwitched, tabUID: Self.otherTab)
        sut.visibleTabDidChange(web(Self.chatTab))
        sut.sheetDismissed(exitTrigger: nil)
        #expect(completions.first?.0.exitTrigger == .tabSwitched)
    }

    @available(iOS 16, *)
    @Test("A tab entry ignores actions on other tabs or before its tab is shown", .timeLimit(.minutes(1)))
    func tabEntryIgnoresForeignActions() {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.recordPendingExit(.searchStarted, tabUID: Self.otherTab)
        sut.visibleTabDidChange(duckAI(Self.chatTab))
        sut.recordPendingExit(.newTabOpened, tabUID: Self.otherTab)
        sut.visibleTabDidChange(web(Self.chatTab))
        #expect(completions.first?.0.exitTrigger == .otherNavigation)
    }

    @available(iOS 16, *)
    @Test("Dismissing a sheet doesn't end a tab entry", .timeLimit(.minutes(1)))
    func sheetDismissDoesntEndTabEntry() {
        let sut = makeSUT()
        startTabEntry(sut)
        sut.sheetDismissed(exitTrigger: nil)
        #expect(completions.isEmpty)
    }

    // MARK: - Background and termination

    @available(iOS 16, *)
    @Test("Backgrounding cancels the entry", .timeLimit(.minutes(1)))
    func backgroundingCancels() {
        let sut = makeSUT()
        startSheetEntry(sut)
        sut.entryCancelledByBackground()
        sut.entryCancelledByBackground()

        #expect(completions.count == 1)
        #expect(completions.first?.0.statusReason == .appBackgrounded)
        guard case .cancelled = completions.first?.1 else {
            Issue.record("Expected CANCELLED")
            return
        }
    }

    @available(iOS 16, *)
    @Test("Entries left over from a previous launch complete as app_terminated", .timeLimit(.minutes(1)))
    func leftoverEntriesCompleteAsTerminated() {
        let orphan = DuckAIEntryWideEventData(source: .serp, hasPrompt: false, chatState: nil, surface: .duckAITab)
        wideEvent.startFlow(orphan)
        _ = makeSUT(completeOrphanedFlowsOnInit: true)

        #expect(completions.count == 1)
        #expect(completions.first?.0.jsonParameters()["feature.data.ext.time_in_duckai_ms_bucketed"] == nil)
        guard case .unknown(let reason) = completions.first?.1 else {
            Issue.record("Expected UNKNOWN")
            return
        }
        #expect(reason == "app_terminated")
    }
}
