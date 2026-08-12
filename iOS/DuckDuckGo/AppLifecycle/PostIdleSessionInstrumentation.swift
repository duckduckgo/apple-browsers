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

/// Interaction state shared by the return-session and post-idle payloads.
protocol ReturnSessionInteractionData: AnyObject {
    var firstInteractionInterval: WideEvent.MeasuredInterval { get set }
    var pageEngaged: Bool { get set }
    var toggleUsed: Bool { get set }
    var backPressed: Bool { get set }
    var openingScreenChanged: Bool { get set }
    var closeTabTapped: Bool { get set }
    var burnTabTapped: Bool { get set }
}

extension ReturnSessionWideEventData: ReturnSessionInteractionData {}
extension PostIdleSessionWideEventData: ReturnSessionInteractionData {}

/// Session-scoped hooks for the return-session wide-event pixel.
///
/// Every return starts an `ios-return-session` flow; after-idle returns also start
/// the older after-idle-only `ios-post-idle-session` flow.
///
/// The caller decides which surface to fire (based on the user's After Inactivity
/// setting) and is responsible for any per-surface eligibility gating. The
/// instrumentation itself trusts the caller. Only one session may be in flight
/// at a time; calling `sessionStarted` while another session is active cancels
/// the previous one.
protocol PostIdleSessionInstrumentation: AnyObject {

    /// Stashes this return's time away; consumed by the next `sessionStarted`.
    func noteReturn(timeAwayMs: Int?)

    /// A return session began on `landedOn`. `afterIdleSurface` is nil for an ordinary return.
    func sessionStarted(landedOn: ReturnSessionWideEventData.LandedOn,
                        afterIdleSurface: PostIdleSessionWideEventData.Surface?,
                        focused: Bool)

    /// User scrolled or activated an in-page link. Idempotent within a session.
    func pageEngaged()

    /// User toggled between search and Duck.ai.
    func toggleUsed()

    /// User pressed back / cancel from the landing surface.
    func backPressed()

    /// User changed the Opening Screen option from the escape hatch's settings menu.
    func openingScreenChanged()

    /// User closed the open tab from the escape hatch's menu. Idempotent within a session.
    func closeTabTapped()

    /// User burned the open tab from the escape hatch's menu. Idempotent within a session.
    func burnTabTapped()

    /// Terminal user action ended the session (submission, return-to-page, etc.).
    func sessionEnded(reason: ReturnSessionWideEventData.StatusReason)

    /// App was backgrounded with a session still active. Completes as CANCELLED.
    func sessionCancelledByBackground()
}

final class DefaultPostIdleSessionInstrumentation: PostIdleSessionInstrumentation {

    private let wideEvent: WideEventManaging
    private let dateProvider: () -> Date
    private var returnSessionID: String?
    private var postIdleSessionID: String?
    /// Skips `updateFlow` (synchronous disk I/O) on every scroll tick after the first.
    private var pageEngagedSent = false
    private var pendingTimeAwayMs: Int?

    init(wideEvent: WideEventManaging,
         dateProvider: @escaping () -> Date = { Date() }) {
        self.wideEvent = wideEvent
        self.dateProvider = dateProvider
    }

    func noteReturn(timeAwayMs: Int?) {
        pendingTimeAwayMs = timeAwayMs
    }

    func sessionStarted(landedOn: ReturnSessionWideEventData.LandedOn,
                        afterIdleSurface: PostIdleSessionWideEventData.Surface?,
                        focused: Bool) {
        // If a session is already active, cancel it before starting a new one.
        // Quick background-foreground cycles over the idle threshold can trigger
        // this; the previous session is reported as CANCELLED so we don't lose it.
        if returnSessionID != nil || postIdleSessionID != nil {
            sessionCancelledByBackground()
        }

        // Complete any orphaned flows left in storage from a previous app lifecycle
        // (e.g., the app was killed before the session could complete). This runs
        // synchronously before the new flow is created, avoiding a race with
        // WideEventService.resume() which would otherwise complete new flows as UNKNOWN.
        completeOrphanedFlows()

        let startedAt = dateProvider()
        let returnData = ReturnSessionWideEventData(landedOn: landedOn,
                                                    afterIdle: afterIdleSurface != nil,
                                                    startedAt: startedAt,
                                                    timeAwayMs: pendingTimeAwayMs,
                                                    focused: focused)
        pendingTimeAwayMs = nil
        returnSessionID = returnData.globalData.id
        pageEngagedSent = false
        wideEvent.startFlow(returnData)

        guard let afterIdleSurface else { return }
        let postIdleData = PostIdleSessionWideEventData(surface: afterIdleSurface, startedAt: startedAt)
        postIdleSessionID = postIdleData.globalData.id
        wideEvent.startFlow(postIdleData)
    }

    func pageEngaged() {
        guard !pageEngagedSent else { return }
        pageEngagedSent = true
        recordInteraction { $0.pageEngaged = true }
    }

    func toggleUsed() {
        recordInteraction { $0.toggleUsed = true }
    }

    func backPressed() {
        recordInteraction { $0.backPressed = true }
    }

    func openingScreenChanged() {
        recordInteraction { $0.openingScreenChanged = true }
    }

    func closeTabTapped() {
        recordInteraction { $0.closeTabTapped = true }
    }

    func burnTabTapped() {
        recordInteraction { $0.burnTabTapped = true }
    }

    func sessionEnded(reason: ReturnSessionWideEventData.StatusReason) {
        let now = dateProvider()

        if let globalID = returnSessionID,
           let data = wideEvent.getFlowData(ReturnSessionWideEventData.self, globalID: globalID) {
            data.statusReason = reason
            data.sessionInterval.end = now
            markFirstInteractionIfNeeded(on: data, at: now)
            wideEvent.completeFlow(data, status: .success(reason: reason.rawValue), onComplete: { _, _ in })
        }
        returnSessionID = nil

        if let globalID = postIdleSessionID,
           let data = wideEvent.getFlowData(PostIdleSessionWideEventData.self, globalID: globalID) {
            let postIdleReason = reason.postIdleReason
            data.statusReason = postIdleReason
            data.sessionInterval.end = now
            markFirstInteractionIfNeeded(on: data, at: now)
            wideEvent.completeFlow(data, status: .success(reason: postIdleReason.rawValue), onComplete: { _, _ in })
        }
        postIdleSessionID = nil
    }

    func sessionCancelledByBackground() {
        let now = dateProvider()

        if let globalID = returnSessionID,
           let data = wideEvent.getFlowData(ReturnSessionWideEventData.self, globalID: globalID) {
            data.statusReason = .appBackgrounded
            data.sessionInterval.end = now
            wideEvent.completeFlow(data, status: .cancelled, onComplete: { _, _ in })
        }
        returnSessionID = nil

        if let globalID = postIdleSessionID,
           let data = wideEvent.getFlowData(PostIdleSessionWideEventData.self, globalID: globalID) {
            data.statusReason = .appBackgrounded
            data.sessionInterval.end = now
            wideEvent.completeFlow(data, status: .cancelled, onComplete: { _, _ in })
        }
        postIdleSessionID = nil
    }

    // MARK: - Helpers

    private func completeOrphanedFlows() {
        for orphan in wideEvent.getAllFlowData(ReturnSessionWideEventData.self) {
            wideEvent.completeFlow(
                orphan,
                status: .unknown(reason: ReturnSessionWideEventData.appTerminatedReason),
                onComplete: { _, _ in })
        }
        for orphan in wideEvent.getAllFlowData(PostIdleSessionWideEventData.self) {
            wideEvent.completeFlow(
                orphan,
                status: .unknown(reason: PostIdleSessionWideEventData.appTerminatedReason),
                onComplete: { _, _ in })
        }
    }

    private func recordInteraction(_ mutate: (any ReturnSessionInteractionData) -> Void) {
        let now = dateProvider()

        if let globalID = returnSessionID {
            wideEvent.updateFlow(globalID: globalID) { (data: inout ReturnSessionWideEventData) in
                mutate(data)
                markFirstInteractionIfNeeded(on: data, at: now)
            }
        }

        if let globalID = postIdleSessionID {
            wideEvent.updateFlow(globalID: globalID) { (data: inout PostIdleSessionWideEventData) in
                mutate(data)
                markFirstInteractionIfNeeded(on: data, at: now)
            }
        }
    }

    private func markFirstInteractionIfNeeded(on data: any ReturnSessionInteractionData, at date: Date) {
        guard data.firstInteractionInterval.end == nil else { return }
        data.firstInteractionInterval.end = date
    }
}
