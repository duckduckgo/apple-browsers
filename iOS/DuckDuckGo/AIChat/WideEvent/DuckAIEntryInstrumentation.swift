//
//  DuckAIEntryInstrumentation.swift
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

import Foundation
import WideEvent

/// Hooks for the Duck.ai entry wide event. One entry runs from an entry point until the user leaves
/// Duck.ai, enters it again, or the app backgrounds; only one is in flight at a time.
protocol DuckAIEntryInstrumentation: AnyObject {

    /// An entry point fired. An entry already in flight ends as `new_entry`.
    /// Pass `chatState` when it is known up front; a tab entry otherwise reads it when its tab is first shown.
    func entryStarted(source: AIChatEntryPointSource,
                      hasPrompt: Bool,
                      surface: DuckAIEntryWideEventData.Surface,
                      chatState: DuckAIEntryWideEventData.ChatState?)

    /// The tab on screen changed, or its URL did. `nil` means no tab is on screen.
    /// A tab entry belongs to the first Duck.ai tab shown after it starts, and ends once that tab is no longer Duck.ai on screen.
    func visibleTabDidChange(_ tab: DuckAISessionTabSnapshot?)

    /// A user action that will leave Duck.ai is about to run. First trigger wins until the entry ends.
    func recordPendingExit(_ trigger: DuckAISessionWideEventData.ExitTrigger)

    /// The Duck.ai page in this tab sent a prompt.
    func promptSubmitted(tabUID: TabUID)

    /// The contextual sheet sent a prompt.
    func sheetPromptSubmitted()

    /// The contextual sheet closed. Ends a sheet entry as `left_duckai`.
    func sheetDismissed()

    /// App was backgrounded with an entry in flight. Completes as CANCELLED.
    func entryCancelledByBackground()
}

final class DefaultDuckAIEntryInstrumentation: DuckAIEntryInstrumentation {

    private struct ActiveEntry {
        let data: DuckAIEntryWideEventData
        /// The Duck.ai tab the entry belongs to; nil until it is shown, and always nil for the sheet.
        var tabUID: TabUID?
        var lastSnapshot: DuckAISessionTabSnapshot?
    }

    private let wideEvent: WideEventManaging
    /// Read per entry rather than cached, so turning the flag off remotely lands without a relaunch.
    private let isEnabled: () -> Bool
    private let now: () -> Date
    private var activeEntry: ActiveEntry?
    private var pendingExit: DuckAISessionWideEventData.ExitTrigger?

    init(wideEvent: WideEventManaging,
         isEnabled: @escaping () -> Bool = { true },
         now: @escaping () -> Date = Date.init,
         completeOrphanedFlowsOnInit: Bool = false) {
        self.wideEvent = wideEvent
        self.isEnabled = isEnabled
        self.now = now

        if completeOrphanedFlowsOnInit {
            completeOrphanedFlowsFromPreviousAppSession()
        }
    }

    func entryStarted(source: AIChatEntryPointSource,
                      hasPrompt: Bool,
                      surface: DuckAIEntryWideEventData.Surface,
                      chatState: DuckAIEntryWideEventData.ChatState?) {
        if let entry = activeEntry {
            end(entry, reason: .newEntry)
        }
        guard isEnabled() else { return }

        let data = DuckAIEntryWideEventData(source: source, hasPrompt: hasPrompt, chatState: chatState, surface: surface, startedAt: now())
        activeEntry = ActiveEntry(data: data)
        wideEvent.startFlow(data)
    }

    func visibleTabDidChange(_ tab: DuckAISessionTabSnapshot?) {
        guard let entry = activeEntry, entry.data.surface == .duckAITab else { return }

        guard let boundUID = entry.tabUID else {
            if let tab, tab.isDuckAI {
                activeEntry?.tabUID = tab.uid
                activeEntry?.lastSnapshot = tab
                if entry.data.chatState == nil {
                    entry.data.chatState = tab.chatID == nil ? .new : .existing
                    wideEvent.updateFlow(entry.data)
                }
            }
            return
        }

        if let tab, tab.uid == boundUID, tab.isDuckAI {
            // Still in Duck.ai, so an action recorded before this change didn't leave it.
            if tab != entry.lastSnapshot {
                pendingExit = nil
                activeEntry?.lastSnapshot = tab
            }
            return
        }
        end(entry, reason: .leftDuckai)
    }

    func recordPendingExit(_ trigger: DuckAISessionWideEventData.ExitTrigger) {
        guard activeEntry != nil, pendingExit == nil else { return }
        pendingExit = trigger
    }

    func promptSubmitted(tabUID: TabUID) {
        guard let entry = activeEntry, entry.data.surface == .duckAITab, entry.tabUID == tabUID else { return }
        recordPrompt(entry)
    }

    func sheetPromptSubmitted() {
        guard let entry = activeEntry, entry.data.surface == .contextualSheet else { return }
        recordPrompt(entry)
    }

    func sheetDismissed() {
        guard let entry = activeEntry, entry.data.surface == .contextualSheet else { return }
        end(entry, reason: .leftDuckai)
    }

    func entryCancelledByBackground() {
        guard let entry = activeEntry else { return }
        end(entry, reason: .appBackgrounded)
    }

    // MARK: - Helpers

    private func recordPrompt(_ entry: ActiveEntry) {
        guard !entry.data.promptSubmitted else { return }
        entry.data.promptSubmitted = true
        entry.data.firstPromptInterval.complete(at: now())
        wideEvent.updateFlow(entry.data)
    }

    private func end(_ entry: ActiveEntry, reason: DuckAIEntryWideEventData.StatusReason) {
        let trigger = pendingExit
        pendingExit = nil
        activeEntry = nil

        let data = entry.data
        data.statusReason = reason
        data.entryInterval.complete(at: now())

        switch reason {
        case .leftDuckai:
            data.exitTrigger = trigger ?? .otherNavigation
            wideEvent.completeFlow(data, status: .success(reason: reason.rawValue), onComplete: { _, _ in })
        case .newEntry:
            wideEvent.completeFlow(data, status: .success(reason: reason.rawValue), onComplete: { _, _ in })
        case .appBackgrounded:
            wideEvent.completeFlow(data, status: .cancelled, onComplete: { _, _ in })
        }
    }

    private func completeOrphanedFlowsFromPreviousAppSession() {
        for orphan in wideEvent.getAllFlowData(DuckAIEntryWideEventData.self) {
            wideEvent.completeFlow(orphan,
                                   status: .unknown(reason: DuckAIEntryWideEventData.appTerminatedReason),
                                   onComplete: { _, _ in })
        }
    }
}
