//
//  NewTabPageSessionInstrumentation.swift
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

/// Visit-scoped hooks for the New Tab Page session wide event.
///
/// One visit spans the New Tab Page being on screen: `visitStarted` opens it, action
/// hooks accumulate what the user did, and `visitEnded` / `visitBackgrounded` close it.
/// Only one visit is in flight at a time. Callers are responsible for deciding when a
/// New Tab Page visit begins; the instrumentation trusts them.
///
/// Both timeouts (inactivity and overall cap) are evaluated from timestamps when the
/// next hook is called, so no timer runs for the length of a visit. A visit that has
/// gone stale is closed on the next hook and the hook itself is ignored: only a fresh
/// `visitStarted` opens another visit.
protocol NewTabPageSessionInstrumentation: AnyObject {

    /// The New Tab Page was displayed. Supersedes any visit still open.
    func visitStarted(trigger: NewTabPageSessionWideEventData.Trigger,
                      launchKeyboardMode: NewTabPageSessionWideEventData.LaunchKeyboardMode,
                      toggleEnabled: Bool)

    // MARK: - Actions
    //
    // Each hook records that the user performed that action during the visit, and
    // counts towards the visit's action total. Repeat calls are cheap and keep the
    // inactivity timeout at bay.

    func tapInputBar()
    func typeInInput()
    func switchToggleToSearch()
    func switchToggleToAiChat()
    func tapDuckaiButton()
    func hitSubmit()
    func chooseSuggestion()
    func tapFavorite()
    func tapFireButton()

    /// User tapped the button that returns to the tab they came from.
    func tapReturnToLast()

    /// User left the New Tab Page through the tab switcher's escape hatch.
    func tapTabViewerEscapeHatch()

    func tapTabViewerToolbar()
    func tapBookmarksToolbarItem()
    func tapPasswordsToolbarItem()
    func openMenu()
    func menuBookmarks()
    func menuPasswords()
    func menuChats()
    func menuDownloads()
    func menuVpn()

    /// User acted on a remote message card's call to action.
    func clickMessageCta()

    /// User dismissed a remote message card.
    func clickMessageDismiss()

    func dismissKeyboard()
    func scrollView()

    /// User tapped the back arrow in the omnibar's unified text input.
    func utiBackArrow()

    // MARK: - Terminals

    /// A user action ended the visit. `terminalAction` decides the reported outcome.
    func visitEnded(terminalAction: NewTabPageSessionWideEventData.TerminalAction)

    /// App was backgrounded with a visit still open. Completes as CANCELLED.
    func visitBackgrounded()
}

final class DefaultNewTabPageSessionInstrumentation: NewTabPageSessionInstrumentation {

    private let wideEvent: WideEventManaging
    private let dateProvider: () -> Date

    /// The live visit is kept in memory and written to storage only at start and at
    /// completion, so a visit costs one disk write regardless of how many actions it
    /// accumulates.
    private var activeVisit: NewTabPageSessionWideEventData?

    init(wideEvent: WideEventManaging,
         dateProvider: @escaping () -> Date = { Date() }) {
        self.wideEvent = wideEvent
        self.dateProvider = dateProvider
    }

    func visitStarted(trigger: NewTabPageSessionWideEventData.Trigger,
                      launchKeyboardMode: NewTabPageSessionWideEventData.LaunchKeyboardMode,
                      toggleEnabled: Bool) {
        expireActiveVisitIfNeeded()

        if let supersededVisit = activeVisit {
            // A visit still open when the next one starts has no honest terminal: nothing
            // here can tell whether the app backgrounded, the tab was replaced, or a hook
            // was missed. Counting it as either a success or a failure would skew the
            // success rate, so it is dropped instead of reported.
            wideEvent.discardFlow(supersededVisit)
            activeVisit = nil
        }

        // Anything left in storage belongs to a previous app lifecycle. Its `lastActionAt`
        // is stale by design, because live state is held in memory and only written at
        // start and at completion, so a stored record cannot say whether the user was
        // still active; a timeout terminal would be a guess. `app_terminated` is the
        // honest answer for a flow that outlived its process.
        //
        // The sweep runs synchronously before the new flow is created, avoiding a race
        // with `WideEventService.resume()` that would complete the new flow as UNKNOWN.
        for orphanedVisit in wideEvent.getAllFlowData(NewTabPageSessionWideEventData.self) {
            complete(orphanedVisit, with: .appTerminated)
        }

        let visit = NewTabPageSessionWideEventData(trigger: trigger,
                                                  launchKeyboardMode: launchKeyboardMode,
                                                  toggleEnabled: toggleEnabled,
                                                  startedAt: dateProvider())
        activeVisit = visit
        wideEvent.startFlow(visit)
    }

    // MARK: - Actions

    func tapInputBar() { recordAction { $0.tapInputBar = true } }
    func typeInInput() { recordAction { $0.typeInInput = true } }
    func switchToggleToSearch() { recordAction { $0.switchToggleToSearch = true } }
    func switchToggleToAiChat() { recordAction { $0.switchToggleToAiChat = true } }
    func tapDuckaiButton() { recordAction { $0.tapDuckaiButton = true } }
    func hitSubmit() { recordAction { $0.hitSubmit = true } }
    func chooseSuggestion() { recordAction { $0.chooseSuggestion = true } }
    func tapFavorite() { recordAction { $0.tapFavorite = true } }
    func tapFireButton() { recordAction { $0.tapFireButton = true } }
    func tapReturnToLast() { recordAction { $0.tapReturnToLast = true } }
    func tapTabViewerEscapeHatch() { recordAction { $0.tapTabViewerEscapeHatch = true } }
    func tapTabViewerToolbar() { recordAction { $0.tapTabViewerToolbar = true } }
    func tapBookmarksToolbarItem() { recordAction { $0.tapBookmarksToolbarItem = true } }
    func tapPasswordsToolbarItem() { recordAction { $0.tapPasswordsToolbarItem = true } }
    func openMenu() { recordAction { $0.openMenu = true } }
    func menuBookmarks() { recordAction { $0.menuBookmarks = true } }
    func menuPasswords() { recordAction { $0.menuPasswords = true } }
    func menuChats() { recordAction { $0.menuChats = true } }
    func menuDownloads() { recordAction { $0.menuDownloads = true } }
    func menuVpn() { recordAction { $0.menuVpn = true } }
    func clickMessageCta() { recordAction { $0.clickMessageCta = true } }
    func clickMessageDismiss() { recordAction { $0.clickMessageDismiss = true } }
    func dismissKeyboard() { recordAction { $0.dismissKeyboard = true } }
    func scrollView() { recordAction { $0.scrollView = true } }
    func utiBackArrow() { recordAction { $0.utiBackArrow = true } }

    // MARK: - Terminals

    func visitEnded(terminalAction: NewTabPageSessionWideEventData.TerminalAction) {
        // Checked first so a terminal arriving after the visit already went stale does not
        // resurrect it.
        expireActiveVisitIfNeeded()
        guard let visit = activeVisit else { return }

        let now = dateProvider()
        visit.sessionInterval.end = now
        markFirstInteractionIfNeeded(on: visit, at: now)

        complete(visit, with: terminalAction)
    }

    func visitBackgrounded() {
        expireActiveVisitIfNeeded()
        guard let visit = activeVisit else { return }

        visit.sessionInterval.end = dateProvider()
        complete(visit, with: .appBackgrounded)
    }

    // MARK: - Helpers

    private func recordAction(_ mutate: (NewTabPageSessionWideEventData) -> Void) {
        expireActiveVisitIfNeeded()
        // An action after an expiry is dropped: the visit it belonged to is already
        // reported, and only a fresh trigger opens another one.
        guard let visit = activeVisit else { return }

        let now = dateProvider()
        mutate(visit)
        visit.actionCount += 1
        visit.lastActionAt = now
        markFirstInteractionIfNeeded(on: visit, at: now)
    }

    /// Closes the active visit when either timeout has elapsed, standing in for the timers
    /// this instrumentation deliberately does not run.
    private func expireActiveVisitIfNeeded() {
        guard let visit = activeVisit else { return }

        let now = dateProvider()
        let terminalAction: NewTabPageSessionWideEventData.TerminalAction

        // Inactivity wins over the overall cap when both have elapsed: a visit that went
        // quiet was abandoned, whatever its total length.
        if now.timeIntervalSince(visit.lastActionAt) >= NewTabPageSessionWideEventData.noActionTimeout {
            terminalAction = .noActionTimeout
        } else if let startedAt = visit.sessionInterval.start,
                  now.timeIntervalSince(startedAt) >= NewTabPageSessionWideEventData.maxSessionDuration {
            terminalAction = .maxDurationExceeded
        } else {
            return
        }

        // Stamped at the last action rather than now, so the recorded duration covers the
        // visit and not the idle gap that revealed the timeout.
        visit.sessionInterval.end = visit.lastActionAt

        complete(visit, with: terminalAction)
    }

    private func complete(_ visit: NewTabPageSessionWideEventData,
                          with terminalAction: NewTabPageSessionWideEventData.TerminalAction) {
        visit.terminalAction = terminalAction
        wideEvent.completeFlow(visit, status: terminalAction.status, onComplete: { _, _ in })
        activeVisit = nil
    }

    private func markFirstInteractionIfNeeded(on visit: NewTabPageSessionWideEventData, at date: Date) {
        guard visit.firstInteractionInterval.end == nil else { return }
        visit.firstInteractionInterval.end = date
    }
}
