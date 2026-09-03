//
//  DuckAISessionInstrumentation.swift
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
import PixelKit

/// What the Duck.ai session instrumentation needs to know about the tab on screen.
struct DuckAISessionTabSnapshot: Equatable {
    let uid: TabUID
    let isDuckAI: Bool
    let url: URL?
    let chatID: String?
}

/// Session-scoped hooks for the Duck.ai session wide event. One session spans a full Duck.ai tab
/// being on screen; only one is in flight at a time. Callers report what is visible, this decides.
protocol DuckAISessionInstrumentation: AnyObject {

    /// The tab on screen changed, or its URL did. `nil` means no tab is on screen.
    func visibleTabDidChange(_ tab: DuckAISessionTabSnapshot?)

    /// A user action that will leave Duck.ai is about to run. The next visible-tab change consumes it.
    /// First trigger wins, and `newTab()` records `.newTabOpened`, so record more specific triggers before it.
    func recordPendingExit(tabUID: TabUID, trigger: DuckAISessionWideEventData.ExitTrigger)

    func promptSubmitted(tabUID: TabUID)
    func newChatCreated(tabUID: TabUID)

    /// App was backgrounded with a session still active. Completes as CANCELLED.
    func sessionCancelledByBackground()
}

final class DefaultDuckAISessionInstrumentation: DuckAISessionInstrumentation {

    private struct ActiveSession {
        let data: DuckAISessionWideEventData
        var lastSnapshot: DuckAISessionTabSnapshot
        var tabUID: TabUID { lastSnapshot.uid }
    }

    private struct PendingExit {
        let tabUID: TabUID
        let trigger: DuckAISessionWideEventData.ExitTrigger
    }

    private let wideEvent: WideEventManaging
    /// Read per session rather than cached, so turning the flag off remotely lands without a relaunch.
    private let isEnabled: () -> Bool
    private var activeSession: ActiveSession?
    private var pendingExit: PendingExit?

    init(wideEvent: WideEventManaging,
         isEnabled: @escaping () -> Bool = { true },
         completeOrphanedFlowsOnInit: Bool = false) {
        self.wideEvent = wideEvent
        self.isEnabled = isEnabled

        if completeOrphanedFlowsOnInit {
            completeOrphanedFlowsFromPreviousAppSession()
        }
    }

    func visibleTabDidChange(_ tab: DuckAISessionTabSnapshot?) {
        if let session = activeSession {
            if let tab, tab.uid == session.tabUID {
                guard tab != session.lastSnapshot else { return }
                if tab.isDuckAI {
                    continueSession(with: tab, previousChatID: session.lastSnapshot.chatID)
                    return
                }
            }
            endSession(session)
        }

        guard let tab, tab.isDuckAI, isEnabled() else { return }
        startSession(with: tab)
    }

    func recordPendingExit(tabUID: TabUID, trigger: DuckAISessionWideEventData.ExitTrigger) {
        guard activeSession?.tabUID == tabUID, pendingExit == nil else { return }
        pendingExit = PendingExit(tabUID: tabUID, trigger: trigger)
    }

    func promptSubmitted(tabUID: TabUID) {
        recordStep(\.promptSubmitted, tabUID: tabUID)
    }

    func newChatCreated(tabUID: TabUID) {
        recordStep(\.newChatCreated, tabUID: tabUID)
    }

    func sessionCancelledByBackground() {
        pendingExit = nil
        guard let session = activeSession else { return }
        activeSession = nil

        session.data.statusReason = .appBackgrounded
        wideEvent.completeFlow(session.data, status: .cancelled, onComplete: { _, _ in })
    }

    // MARK: - Helpers

    private func startSession(with tab: DuckAISessionTabSnapshot) {
        pendingExit = nil
        let data = DuckAISessionWideEventData()
        activeSession = ActiveSession(data: data, lastSnapshot: tab)
        wideEvent.startFlow(data)
    }

    private func continueSession(with tab: DuckAISessionTabSnapshot, previousChatID: String?) {
        pendingExit = nil
        activeSession?.lastSnapshot = tab
        if tab.chatID != previousChatID {
            recordStep(\.chatIDChanged, tabUID: tab.uid)
        }
    }

    private func endSession(_ session: ActiveSession) {
        let trigger = pendingExit?.tabUID == session.tabUID ? pendingExit?.trigger : nil
        pendingExit = nil
        activeSession = nil

        session.data.statusReason = .leftDuckai
        session.data.exitTrigger = trigger ?? .otherNavigation
        wideEvent.completeFlow(session.data,
                               status: .success(reason: DuckAISessionWideEventData.StatusReason.leftDuckai.rawValue),
                               onComplete: { _, _ in })
    }

    private func recordStep(_ step: ReferenceWritableKeyPath<DuckAISessionWideEventData, Bool>, tabUID: TabUID) {
        guard let session = activeSession, session.tabUID == tabUID, !session.data[keyPath: step] else { return }
        session.data[keyPath: step] = true
        wideEvent.updateFlow(session.data)
    }

    private func completeOrphanedFlowsFromPreviousAppSession() {
        for orphan in wideEvent.getAllFlowData(DuckAISessionWideEventData.self) {
            wideEvent.completeFlow(orphan,
                                   status: .unknown(reason: DuckAISessionWideEventData.appTerminatedReason),
                                   onComplete: { _, _ in })
        }
    }
}
