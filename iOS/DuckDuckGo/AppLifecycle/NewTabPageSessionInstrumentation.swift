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
    // Repeat calls are cheap, and each one holds off the inactivity timeout.

    func tapInputBar()
    func typeInInput()
    func switchToggleToSearch()
    func switchToggleToAiChat()
    func tapDuckaiButton()
    func hitSubmit()
    func chooseSuggestion()
    func tapFavorite()
    func tapFireButton()

    func tapReturnToLast()

    /// Reached through the return-to-tab card rather than the toolbar's tab button.
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

    func clickMessageCta()
    func clickMessageDismiss()
    func dismissKeyboard()
    func scrollView()

    /// The back arrow that leaves search mode, in the omnibar's unified text input.
    func utiBackArrow()

    // MARK: - Terminals

    /// A user action ended the visit. `terminalAction` decides the reported outcome.
    func visitEnded(terminalAction: NewTabPageSessionWideEventData.TerminalAction)

    /// App was backgrounded with a visit still open. Completes as CANCELLED.
    func visitBackgrounded()
}

/// Reads the wide event sample rate from the feature's remote settings, so the volume can be
/// dialled down without shipping a release. This event is projected to be the highest volume
/// wide event on either platform, so the rate needs to be adjustable in production.
enum NewTabPageSessionSampleRate {

    static let settingKey = "sampleRate"
    static let fullRate: Float = 1.0

    /// Absent, malformed or out of range settings all fall back to the full rate, so a bad
    /// remote value can never silently discard data.
    static func resolve(from settingsJSON: String?) -> Float {
        guard let settingsJSON,
              let data = settingsJSON.data(using: .utf8),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = settings[settingKey] as? NSNumber else {
            return fullRate
        }

        let rate = value.floatValue
        guard rate > 0, rate <= fullRate else { return fullRate }
        return rate
    }
}

final class DefaultNewTabPageSessionInstrumentation: NewTabPageSessionInstrumentation {

    private let wideEvent: WideEventManaging
    private let dateProvider: () -> Date

    /// Read per visit rather than cached, so turning the flag off remotely takes effect
    /// without waiting for a relaunch.
    private let isEnabled: () -> Bool

    /// Also read per visit, so a rate change lands without a relaunch.
    private let sampleRate: () -> Float

    /// Held in memory rather than read back per action, so the number of actions in a visit
    /// does not affect how often storage is touched. Storage is synchronous.
    private var activeVisit: NewTabPageSessionWideEventData?

    /// Set once a timeout threshold has elapsed. The visit stays open so its real end time can
    /// still be observed, but its outcome is fixed and further actions are ignored.
    private var lockedTerminal: NewTabPageSessionWideEventData.TerminalAction?

    init(wideEvent: WideEventManaging,
         dateProvider: @escaping () -> Date = { Date() },
         isEnabled: @escaping () -> Bool = { true },
         sampleRate: @escaping () -> Float = { NewTabPageSessionSampleRate.fullRate }) {
        self.wideEvent = wideEvent
        self.dateProvider = dateProvider
        self.isEnabled = isEnabled
        self.sampleRate = sampleRate
    }

    func visitStarted(trigger: NewTabPageSessionWideEventData.Trigger,
                      launchKeyboardMode: NewTabPageSessionWideEventData.LaunchKeyboardMode,
                      toggleEnabled: Bool) {
        // The only gate needed: with no visit open, every action and terminal already
        // no-ops on its `activeVisit` guard.
        guard isEnabled() else { return }

        lockTerminalIfTimedOut()

        if let previousVisit = activeVisit {
            if let lockedTerminal {
                // Timed out earlier and is only now leaving the screen, so this is its real
                // end time.
                previousVisit.sessionInterval.end = dateProvider()
                complete(previousVisit, with: lockedTerminal)
            } else {
                // Still active when the next visit starts, so nothing here can tell whether
                // the tab was replaced or a hook was missed. Reporting it either way would
                // skew the success rate.
                wideEvent.discardFlow(previousVisit)
                activeVisit = nil
            }
        }

        // Anything left in storage outlived its process. Its timestamps are stale because
        // live state is held in memory, so a timeout terminal would be a guess.
        //
        // Swept here rather than from `completionDecision`, which the launch cleanup task
        // calls concurrently with view controller construction and would race a new flow.
        for orphanedVisit in wideEvent.getAllFlowData(NewTabPageSessionWideEventData.self) {
            complete(orphanedVisit, with: .appTerminated)
        }

        let visit = NewTabPageSessionWideEventData(trigger: trigger,
                                                  launchKeyboardMode: launchKeyboardMode,
                                                  toggleEnabled: toggleEnabled,
                                                  startedAt: dateProvider(),
                                                  globalData: WideEventGlobalData(sampleRate: sampleRate()))
        activeVisit = visit
        // The framework consults the sample rate only here. A visit the sampler drops still
        // runs locally, and its later calls no-op.
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
        lockTerminalIfTimedOut()
        guard let visit = activeVisit else { return }

        let now = dateProvider()
        // A timed out visit keeps its timeout outcome. The user action that closed it came
        // after we had already declared it abandoned.
        let outcome = lockedTerminal ?? terminalAction

        visit.sessionInterval.end = now
        if lockedTerminal == nil {
            markFirstInteractionIfNeeded(on: visit, at: now)
        }

        complete(visit, with: outcome)
    }

    func visitBackgrounded() {
        lockTerminalIfTimedOut()
        guard let visit = activeVisit else { return }

        visit.sessionInterval.end = dateProvider()
        complete(visit, with: lockedTerminal ?? .appBackgrounded)
    }

    // MARK: - Helpers

    private func recordAction(_ mutate: (NewTabPageSessionWideEventData) -> Void) {
        lockTerminalIfTimedOut()
        // Actions after a timeout are dropped: the visit is already classed as abandoned and
        // only a fresh trigger opens another one.
        guard let visit = activeVisit, lockedTerminal == nil else { return }

        let now = dateProvider()
        mutate(visit)
        visit.actionCount += 1
        visit.lastActionAt = now
        markFirstInteractionIfNeeded(on: visit, at: now)
    }

    /// Fixes the outcome of a stale visit without ending it, standing in for the timers this
    /// instrumentation deliberately does not run.
    ///
    /// The visit stays open so that whatever actually removes the New Tab Page from the
    /// screen decides when it ended. Completing here would report the time to the threshold
    /// rather than how long the surface was really on screen.
    private func lockTerminalIfTimedOut() {
        guard let visit = activeVisit, lockedTerminal == nil else { return }

        let now = dateProvider()

        // Inactivity wins over the overall cap when both have elapsed: a visit that went
        // quiet was abandoned, whatever its total length.
        if now.timeIntervalSince(visit.lastActionAt) >= NewTabPageSessionWideEventData.noActionTimeout {
            lockedTerminal = .noActionTimeout
        } else if let startedAt = visit.sessionInterval.start,
                  now.timeIntervalSince(startedAt) >= NewTabPageSessionWideEventData.maxSessionDuration {
            lockedTerminal = .maxDurationExceeded
        }
    }

    private func complete(_ visit: NewTabPageSessionWideEventData,
                          with terminalAction: NewTabPageSessionWideEventData.TerminalAction) {
        visit.terminalAction = terminalAction
        wideEvent.completeFlow(visit, status: terminalAction.status, onComplete: { _, _ in })
        activeVisit = nil
        lockedTerminal = nil
    }

    private func markFirstInteractionIfNeeded(on visit: NewTabPageSessionWideEventData, at date: Date) {
        guard visit.firstInteractionInterval.end == nil else { return }
        visit.firstInteractionInterval.end = date
    }
}
