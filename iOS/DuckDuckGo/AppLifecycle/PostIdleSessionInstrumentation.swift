//
//  PostIdleSessionInstrumentation.swift
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

/// Session-scoped hooks for the post-idle wide-event pixel.
///
/// The caller decides which surface to fire (based on the user's After Inactivity
/// setting) and is responsible for any per-surface eligibility gating. The
/// instrumentation itself trusts the caller. Only one session may be in flight
/// at a time; calling `sessionStarted` while another session is active cancels
/// the previous one.
protocol PostIdleSessionInstrumentation: AnyObject {

    /// The post-idle surface (NTP or LUT) was displayed.
    func sessionStarted(surface: PostIdleSessionWideEventData.Surface)

    /// User scrolled or activated an in-page link. Idempotent within a session.
    func pageEngaged()

    /// User toggled between search and Duck.ai.
    func toggleUsed()

    /// User pressed back / cancel from the post-idle surface.
    func backPressed()

    /// User changed the Opening Screen option from the escape hatch's settings menu.
    func openingScreenChanged()

    /// User closed the open tab from the escape hatch's menu. Idempotent within a session.
    func closeTabTapped()

    /// User burned the open tab from the escape hatch's menu. Idempotent within a session.
    func burnTabTapped()

    /// Terminal user action ended the session (bar used, return-to-page, etc.).
    func sessionEnded(reason: PostIdleSessionWideEventData.StatusReason)

    /// App was backgrounded with a session still active. Completes as CANCELLED.
    func sessionCancelledByBackground()
}

final class DefaultPostIdleSessionInstrumentation: PostIdleSessionInstrumentation {

    private let wideEvent: WideEventManaging
    private let dateProvider: () -> Date
    private var activeSessionID: String?
    /// Skips `updateFlow` (synchronous disk I/O) on every scroll tick after the first.
    private var pageEngagedSent = false

    init(wideEvent: WideEventManaging,
         dateProvider: @escaping () -> Date = { Date() }) {
        self.wideEvent = wideEvent
        self.dateProvider = dateProvider
    }

    func sessionStarted(surface: PostIdleSessionWideEventData.Surface) {
        // If a session is already active, cancel it before starting a new one.
        // Quick background-foreground cycles over the idle threshold can trigger
        // this; the previous session is reported as CANCELLED so we don't lose it.
        if activeSessionID != nil {
            sessionCancelledByBackground()
        }

        // Complete any orphaned flows left in storage from a previous app lifecycle
        // (e.g., the app was killed before the session could complete). This runs
        // synchronously before the new flow is created, avoiding a race with
        // WideEventService.resume() which would otherwise complete new flows as UNKNOWN.
        completeOrphanedFlows()

        let data = PostIdleSessionWideEventData(surface: surface, startedAt: dateProvider())
        activeSessionID = data.globalData.id
        pageEngagedSent = false
        wideEvent.startFlow(data)
    }

    func pageEngaged() {
        guard !pageEngagedSent else { return }
        pageEngagedSent = true
        updateActiveSession { data in
            data.pageEngaged = true
            markFirstInteractionIfNeeded(on: data, at: dateProvider())
        }
    }

    func toggleUsed() {
        updateActiveSession { data in
            data.toggleUsed = true
            markFirstInteractionIfNeeded(on: data, at: dateProvider())
        }
    }

    func backPressed() {
        updateActiveSession { data in
            data.backPressed = true
            markFirstInteractionIfNeeded(on: data, at: dateProvider())
        }
    }

    func openingScreenChanged() {
        updateActiveSession { data in
            data.openingScreenChanged = true
            markFirstInteractionIfNeeded(on: data, at: dateProvider())
        }
    }

    func closeTabTapped() {
        updateActiveSession { data in
            data.closeTabTapped = true
            markFirstInteractionIfNeeded(on: data, at: dateProvider())
        }
    }

    func burnTabTapped() {
        updateActiveSession { data in
            data.burnTabTapped = true
            markFirstInteractionIfNeeded(on: data, at: dateProvider())
        }
    }

    func sessionEnded(reason: PostIdleSessionWideEventData.StatusReason) {
        guard let globalID = activeSessionID,
              let data = wideEvent.getFlowData(PostIdleSessionWideEventData.self, globalID: globalID) else {
            activeSessionID = nil
            return
        }

        let now = dateProvider()
        data.statusReason = reason
        data.sessionInterval.end = now
        markFirstInteractionIfNeeded(on: data, at: now)

        wideEvent.completeFlow(data, status: .success(reason: reason.rawValue), onComplete: { _, _ in })
        activeSessionID = nil
    }

    func sessionCancelledByBackground() {
        guard let globalID = activeSessionID,
              let data = wideEvent.getFlowData(PostIdleSessionWideEventData.self, globalID: globalID) else {
            activeSessionID = nil
            return
        }

        data.statusReason = .appBackgrounded
        data.sessionInterval.end = dateProvider()

        wideEvent.completeFlow(data, status: .cancelled, onComplete: { _, _ in })
        activeSessionID = nil
    }

    // MARK: - Helpers

    private func completeOrphanedFlows() {
        for orphan in wideEvent.getAllFlowData(PostIdleSessionWideEventData.self) {
            wideEvent.completeFlow(
                orphan,
                status: .unknown(reason: PostIdleSessionWideEventData.appTerminatedReason),
                onComplete: { _, _ in })
        }
    }

    private func updateActiveSession(_ mutate: (inout PostIdleSessionWideEventData) -> Void) {
        guard let globalID = activeSessionID else { return }
        wideEvent.updateFlow(globalID: globalID, update: mutate)
    }

    private func markFirstInteractionIfNeeded(on data: PostIdleSessionWideEventData, at date: Date) {
        guard data.firstInteractionInterval.end == nil else { return }
        data.firstInteractionInterval.end = date
    }
}
