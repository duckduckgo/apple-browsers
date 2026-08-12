//
//  NewTabPageSessionInstrumentationTests.swift
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
import Testing
import PixelKit
import PixelKitTestingUtilities
@testable import DuckDuckGo

@Suite("New Tab Page Session Instrumentation")
struct NewTabPageSessionInstrumentationTests {

    private final class MockClock {
        var now: Date
        init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.now = start }
        func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func makeSUT(isEnabled: Bool = true) -> (DefaultNewTabPageSessionInstrumentation, WideEventMock, MockClock) {
        let wideEvent = WideEventMock()
        let clock = MockClock()
        let sut = DefaultNewTabPageSessionInstrumentation(
            wideEvent: wideEvent,
            dateProvider: { clock.now },
            isEnabled: { isEnabled }
        )
        return (sut, wideEvent, clock)
    }

    @available(iOS 16, *)
    @Test("Remote sample rate is read, and bad values fall back to the full rate", .timeLimit(.minutes(1)))
    func sampleRateResolution() {
        #expect(NewTabPageSessionSampleRate.resolve(from: #"{"sampleRate": 0.3}"#) == 0.3)
        #expect(NewTabPageSessionSampleRate.resolve(from: #"{"sampleRate": 1}"#) == 1.0)

        // Anything unusable means full rate, so a bad remote value cannot silently discard data.
        #expect(NewTabPageSessionSampleRate.resolve(from: nil) == 1.0)
        #expect(NewTabPageSessionSampleRate.resolve(from: "") == 1.0)
        #expect(NewTabPageSessionSampleRate.resolve(from: "not json") == 1.0)
        #expect(NewTabPageSessionSampleRate.resolve(from: #"{"other": 0.3}"#) == 1.0)
        #expect(NewTabPageSessionSampleRate.resolve(from: #"{"sampleRate": 0}"#) == 1.0)
        #expect(NewTabPageSessionSampleRate.resolve(from: #"{"sampleRate": 1.5}"#) == 1.0)
        #expect(NewTabPageSessionSampleRate.resolve(from: #"{"sampleRate": -0.2}"#) == 1.0)
    }

    @available(iOS 16, *)
    @Test("Sample rate reaches the started visit", .timeLimit(.minutes(1)))
    func sampleRateIsAppliedToVisit() {
        let wideEvent = WideEventMock()
        let sut = DefaultNewTabPageSessionInstrumentation(wideEvent: wideEvent, sampleRate: { 0.25 })

        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .down, toggleEnabled: true)

        let visit = wideEvent.started.last as? NewTabPageSessionWideEventData
        #expect(visit?.globalData.sampleRate == 0.25)
    }

    @available(iOS 16, *)
    @Test("Nothing is recorded while the feature flag is off", .timeLimit(.minutes(1)))
    func disabledByFeatureFlagRecordsNothing() {
        let (sut, wideEvent, _) = makeSUT(isEnabled: false)

        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .down, toggleEnabled: true)
        sut.tapInputBar()
        sut.hitSubmit()
        sut.visitEnded(terminalAction: .loadSerp)
        sut.visitBackgrounded()

        #expect(wideEvent.started.isEmpty)
        #expect(wideEvent.updates.isEmpty)
        #expect(wideEvent.completions.isEmpty)
        #expect(wideEvent.discarded.isEmpty)
    }

    /// The instrumentation keeps the live visit in memory and never calls `updateFlow`, so
    /// the object handed to `startFlow` is the one being mutated.
    private func activeVisit(_ wideEvent: WideEventMock) -> NewTabPageSessionWideEventData? {
        wideEvent.started.compactMap { $0 as? NewTabPageSessionWideEventData }.last
    }

    private func lastCompletion(_ wideEvent: WideEventMock) -> (NewTabPageSessionWideEventData, WideEventStatus)? {
        guard let last = wideEvent.completions.last,
              let data = last.0 as? NewTabPageSessionWideEventData else { return nil }
        return (data, last.1)
    }

    private struct ActionCase {
        let name: String
        let invoke: (NewTabPageSessionInstrumentation) -> Void
        let flag: KeyPath<NewTabPageSessionWideEventData, Bool>
    }

    private func actionCases() -> [ActionCase] {
        [
            ActionCase(name: "tapInputBar", invoke: { $0.tapInputBar() }, flag: \.tapInputBar),
            ActionCase(name: "typeInInput", invoke: { $0.typeInInput() }, flag: \.typeInInput),
            ActionCase(name: "switchToggleToSearch", invoke: { $0.switchToggleToSearch() }, flag: \.switchToggleToSearch),
            ActionCase(name: "switchToggleToAiChat", invoke: { $0.switchToggleToAiChat() }, flag: \.switchToggleToAiChat),
            ActionCase(name: "tapDuckaiButton", invoke: { $0.tapDuckaiButton() }, flag: \.tapDuckaiButton),
            ActionCase(name: "hitSubmit", invoke: { $0.hitSubmit() }, flag: \.hitSubmit),
            ActionCase(name: "chooseSuggestion", invoke: { $0.chooseSuggestion() }, flag: \.chooseSuggestion),
            ActionCase(name: "tapFavorite", invoke: { $0.tapFavorite() }, flag: \.tapFavorite),
            ActionCase(name: "tapFireButton", invoke: { $0.tapFireButton() }, flag: \.tapFireButton),
            ActionCase(name: "tapReturnToLast", invoke: { $0.tapReturnToLast() }, flag: \.tapReturnToLast),
            ActionCase(name: "tapTabViewerEscapeHatch", invoke: { $0.tapTabViewerEscapeHatch() }, flag: \.tapTabViewerEscapeHatch),
            ActionCase(name: "tapTabViewerToolbar", invoke: { $0.tapTabViewerToolbar() }, flag: \.tapTabViewerToolbar),
            ActionCase(name: "tapBookmarksToolbarItem", invoke: { $0.tapBookmarksToolbarItem() }, flag: \.tapBookmarksToolbarItem),
            ActionCase(name: "tapPasswordsToolbarItem", invoke: { $0.tapPasswordsToolbarItem() }, flag: \.tapPasswordsToolbarItem),
            ActionCase(name: "openMenu", invoke: { $0.openMenu() }, flag: \.openMenu),
            ActionCase(name: "menuBookmarks", invoke: { $0.menuBookmarks() }, flag: \.menuBookmarks),
            ActionCase(name: "menuPasswords", invoke: { $0.menuPasswords() }, flag: \.menuPasswords),
            ActionCase(name: "menuChats", invoke: { $0.menuChats() }, flag: \.menuChats),
            ActionCase(name: "menuDownloads", invoke: { $0.menuDownloads() }, flag: \.menuDownloads),
            ActionCase(name: "menuVpn", invoke: { $0.menuVpn() }, flag: \.menuVpn),
            ActionCase(name: "clickMessageCta", invoke: { $0.clickMessageCta() }, flag: \.clickMessageCta),
            ActionCase(name: "clickMessageDismiss", invoke: { $0.clickMessageDismiss() }, flag: \.clickMessageDismiss),
            ActionCase(name: "dismissKeyboard", invoke: { $0.dismissKeyboard() }, flag: \.dismissKeyboard),
            ActionCase(name: "scrollView", invoke: { $0.scrollView() }, flag: \.scrollView),
            ActionCase(name: "utiBackArrow", invoke: { $0.utiBackArrow() }, flag: \.utiBackArrow),
        ]
    }

    // MARK: - No active visit

    @available(iOS 16, *)
    @Test("When no active visit then every action is a no-op", .timeLimit(.minutes(1)))
    func actionsWithoutActiveVisitAreNoops() {
        let (sut, wideEvent, _) = makeSUT()

        for action in actionCases() {
            action.invoke(sut)
        }

        #expect(wideEvent.started.isEmpty)
        #expect(wideEvent.updates.isEmpty)
        #expect(wideEvent.completions.isEmpty)
        #expect(wideEvent.discarded.isEmpty)
    }

    @available(iOS 16, *)
    @Test("When no active visit then visitEnded is a no-op", .timeLimit(.minutes(1)))
    func visitEndedWithoutActiveVisitIsNoop() {
        let (sut, wideEvent, _) = makeSUT()
        sut.visitEnded(terminalAction: .loadSerp)
        #expect(wideEvent.completions.isEmpty)
        #expect(wideEvent.started.isEmpty)
    }

    @available(iOS 16, *)
    @Test("When no active visit then visitBackgrounded is a no-op", .timeLimit(.minutes(1)))
    func visitBackgroundedWithoutActiveVisitIsNoop() {
        let (sut, wideEvent, _) = makeSUT()
        sut.visitBackgrounded()
        #expect(wideEvent.completions.isEmpty)
        #expect(wideEvent.started.isEmpty)
    }

    // MARK: - visitStarted

    @available(iOS 16, *)
    @Test("visitStarted starts one flow carrying trigger, keyboard mode and toggle state", .timeLimit(.minutes(1)))
    func visitStartedStartsFlowWithContext() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .newTabOpened, launchKeyboardMode: .up, toggleEnabled: true)

        #expect(wideEvent.started.count == 1)
        let started = activeVisit(wideEvent)
        #expect(started?.trigger == .newTabOpened)
        #expect(started?.launchKeyboardMode == .up)
        #expect(started?.toggleEnabled == true)
        #expect(started?.sessionInterval.start == clock.now)
        #expect(started?.lastActionAt == clock.now)
        #expect(started?.actionCount == 0)
        #expect(started?.terminalAction == nil)
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, *)
    @Test("visitStarted with app_open and keyboard down carries those values", .timeLimit(.minutes(1)))
    func visitStartedAppOpenKeyboardDown() {
        let (sut, wideEvent, _) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .down, toggleEnabled: false)

        let started = activeVisit(wideEvent)
        #expect(started?.trigger == .appOpen)
        #expect(started?.launchKeyboardMode == .down)
        #expect(started?.toggleEnabled == false)
    }

    // MARK: - Actions

    @available(iOS 16, *)
    @Test("Each action sets its own flag and counts once", .timeLimit(.minutes(1)))
    func eachActionSetsItsOwnFlag() {
        for action in actionCases() {
            let (sut, wideEvent, _) = makeSUT()
            sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .down, toggleEnabled: false)

            action.invoke(sut)

            guard let visit = activeVisit(wideEvent) else {
                Issue.record("Expected an active visit for \(action.name)")
                continue
            }
            if !visit[keyPath: action.flag] {
                Issue.record("\(action.name) did not set its flag")
            }
            #expect(visit.actionCount == 1)
        }
    }

    @available(iOS 16, *)
    @Test("An action marks first interaction and refreshes lastActionAt", .timeLimit(.minutes(1)))
    func actionMarksFirstInteraction() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .down, toggleEnabled: false)

        clock.advance(by: 1.5)
        sut.tapInputBar()

        let visit = activeVisit(wideEvent)
        #expect(visit?.firstInteractionInterval.end == clock.now)
        #expect(visit?.lastActionAt == clock.now)
    }

    @available(iOS 16, *)
    @Test("First interaction is marked only once across several actions", .timeLimit(.minutes(1)))
    func firstInteractionMarkedOnlyOnce() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .down, toggleEnabled: false)

        clock.advance(by: 0.5)
        let firstStamp = clock.now
        sut.tapInputBar()

        clock.advance(by: 2)
        sut.typeInInput()

        let visit = activeVisit(wideEvent)
        #expect(visit?.firstInteractionInterval.end == firstStamp)
        #expect(visit?.lastActionAt == clock.now)
        #expect(visit?.actionCount == 2)
    }

    @available(iOS 16, *)
    @Test("Actions do not write to storage", .timeLimit(.minutes(1)))
    func actionsDoNotWriteToStorage() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .down, toggleEnabled: false)

        clock.advance(by: 1)
        sut.scrollView()
        clock.advance(by: 1)
        sut.scrollView()

        #expect(wideEvent.updates.isEmpty)
        #expect(wideEvent.started.count == 1)
    }

    // MARK: - Terminals

    @available(iOS 16, *)
    @Test("visitEnded with a loading action completes as SUCCESS and records the terminal", .timeLimit(.minutes(1)))
    func visitEndedCompletesAsSuccess() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: 3)
        sut.hitSubmit()
        clock.advance(by: 1)
        sut.visitEnded(terminalAction: .loadSerp)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.terminalAction == .loadSerp)
        #expect(completion.0.sessionInterval.end == clock.now)
        #expect(completion.1 == .success(reason: nil))
        #expect(wideEvent.completions.count == 1)
    }

    @available(iOS 16, *)
    @Test("visitEnded marks first interaction when no action preceded it", .timeLimit(.minutes(1)))
    func visitEndedMarksFirstInteractionIfNotSet() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: 2)
        sut.visitEnded(terminalAction: .selectOtherTab)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.firstInteractionInterval.end == clock.now)
    }

    @available(iOS 16, *)
    @Test("visitEnded preserves an earlier first-interaction timestamp", .timeLimit(.minutes(1)))
    func visitEndedPreservesEarlierFirstInteraction() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: 0.5)
        let firstStamp = clock.now
        sut.tapFavorite()
        clock.advance(by: 2)
        sut.visitEnded(terminalAction: .loadWebsite)

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.firstInteractionInterval.end == firstStamp)
    }

    @available(iOS 16, *)
    @Test("visitEnded clears the active visit", .timeLimit(.minutes(1)))
    func visitEndedClearsActiveVisit() {
        let (sut, wideEvent, _) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)
        sut.visitEnded(terminalAction: .loadDuckai)

        sut.tapInputBar()
        sut.visitEnded(terminalAction: .loadSerp)
        sut.visitBackgrounded()

        #expect(wideEvent.completions.count == 1)
        #expect(lastCompletion(wideEvent)?.0.terminalAction == .loadDuckai)
    }

    @available(iOS 16, *)
    @Test("visitBackgrounded completes as CANCELLED with app_backgrounded", .timeLimit(.minutes(1)))
    func visitBackgroundedCompletesAsCancelled() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: 4)
        sut.visitBackgrounded()

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.terminalAction == .appBackgrounded)
        #expect(completion.0.sessionInterval.end == clock.now)
        #expect(completion.1 == .cancelled)
        #expect(wideEvent.completions.count == 1)
    }

    // MARK: - Inactivity timeout

    @available(iOS 16, *)
    @Test("An action after the inactivity timeout is dropped without ending the visit", .timeLimit(.minutes(1)))
    func inactivityTimeoutDropsActionWithoutEndingVisit() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: NewTabPageSessionWideEventData.noActionTimeout)
        sut.tapInputBar()

        // The visit is classed as abandoned but is still on screen, so nothing is sent yet.
        #expect(wideEvent.completions.isEmpty)

        sut.visitBackgrounded()

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(wideEvent.completions.count == 1)
        #expect(completion.0.terminalAction == .noActionTimeout)
        #expect(completion.1 == .failure)
        // The action that revealed the timeout belongs to no visit.
        #expect(completion.0.tapInputBar == false)
        #expect(completion.0.actionCount == 0)
        #expect(wideEvent.started.count == 1)
    }

    @available(iOS 16, *)
    @Test("A terminal after the inactivity timeout does not resurrect the visit", .timeLimit(.minutes(1)))
    func terminalAfterInactivityTimeoutDoesNotResurrectVisit() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: 45)
        sut.visitEnded(terminalAction: .loadSerp)

        #expect(wideEvent.completions.count == 1)
        #expect(lastCompletion(wideEvent)?.0.terminalAction == .noActionTimeout)
    }

    @available(iOS 16, *)
    @Test("A timeout fixes the outcome but the real exit fixes the duration", .timeLimit(.minutes(1)))
    func timeoutFixesOutcomeAndRealExitFixesDuration() {
        let (sut, wideEvent, clock) = makeSUT()
        let startStamp = clock.now
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: 5)
        sut.tapInputBar()

        // Well past the inactivity threshold. The visit is now classed as abandoned, but it
        // is still on screen, so nothing is reported yet.
        clock.advance(by: 300)
        #expect(wideEvent.completions.isEmpty)

        // Actions after the timeout are ignored, and do not end the visit either.
        sut.tapFavorite()
        #expect(wideEvent.completions.isEmpty)

        clock.advance(by: 55)
        sut.visitBackgrounded()

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.terminalAction == .noActionTimeout)
        #expect(completion.0.tapFavorite == false)
        // The full time the surface was on screen, not the 30 seconds to the threshold.
        #expect(completion.0.sessionInterval.end == startStamp.addingTimeInterval(360))
        #expect(completion.0.sessionInterval.durationMilliseconds == 360_000)
    }

    @available(iOS 16, *)
    @Test("A visit abandoned without any action still reports its duration", .timeLimit(.minutes(1)))
    func abandonedVisitReportsDuration() {
        let (sut, wideEvent, clock) = makeSUT()
        let startStamp = clock.now
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: 90)
        sut.visitBackgrounded()

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(completion.0.terminalAction == .noActionTimeout)
        #expect(completion.0.sessionInterval.end == startStamp.addingTimeInterval(90))
        #expect(completion.0.sessionInterval.durationMilliseconds == 90_000)
    }

    @available(iOS 16, *)
    @Test("Repeated actions keep refreshing lastActionAt so no inactivity timeout fires", .timeLimit(.minutes(1)))
    func repeatedActionsKeepVisitAlive() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        // 5 x 20s stays under the 30s inactivity gap and under the 120s cap.
        for _ in 1...5 {
            clock.advance(by: 20)
            sut.typeInInput()
        }

        #expect(wideEvent.completions.isEmpty)
        let visit = activeVisit(wideEvent)
        #expect(visit?.actionCount == 5)
        #expect(visit?.lastActionAt == clock.now)
        #expect(visit?.typeInInput == true)
    }

    // MARK: - Max duration

    @available(iOS 16, *)
    @Test("A visit active past the max duration completes as max_duration_exceeded", .timeLimit(.minutes(1)))
    func activeVisitPastMaxDurationCompletes() {
        let (sut, wideEvent, clock) = makeSUT()
        let startStamp = clock.now
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        // Active every 10s: the inactivity gap never elapses, so only the cap can fire.
        for _ in 1...13 {
            clock.advance(by: 10)
            sut.scrollView()
        }

        // The cap elapses on the 12th tick, and the check runs before the action is recorded,
        // so only the first 11 count.
        #expect(wideEvent.completions.isEmpty)

        sut.visitBackgrounded()

        guard let completion = lastCompletion(wideEvent) else {
            Issue.record("Expected a completion")
            return
        }
        #expect(wideEvent.completions.count == 1)
        #expect(completion.0.terminalAction == .maxDurationExceeded)
        #expect(completion.1 == .failure)
        #expect(completion.0.actionCount == 11)
        #expect(completion.0.sessionInterval.end == startStamp.addingTimeInterval(130))
    }

    @available(iOS 16, *)
    @Test("Inactivity is checked before the max duration when both are exceeded", .timeLimit(.minutes(1)))
    func inactivityWinsOverMaxDuration() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: 300)
        sut.scrollView()
        sut.visitBackgrounded()

        #expect(wideEvent.completions.count == 1)
        #expect(lastCompletion(wideEvent)?.0.terminalAction == .noActionTimeout)
    }

    // MARK: - Orphans and superseded visits

    @available(iOS 16, *)
    @Test("visitStarted completes a stored orphan as UNKNOWN with app_terminated", .timeLimit(.minutes(1)))
    func visitStartedCompletesOrphanAsAppTerminated() {
        let (sut, wideEvent, _) = makeSUT()
        let orphan = NewTabPageSessionWideEventData(trigger: .newTabOpened,
                                                   launchKeyboardMode: .down,
                                                   toggleEnabled: false)
        wideEvent.startFlow(orphan)

        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: true)

        guard let orphanCompletion = wideEvent.completions.first(where: {
            ($0.0 as? NewTabPageSessionWideEventData)?.globalData.id == orphan.globalData.id
        }) else {
            Issue.record("Expected the orphan to be completed")
            return
        }
        #expect(orphanCompletion.1 == .unknown(reason: NewTabPageSessionWideEventData.TerminalAction.appTerminated.rawValue))
        #expect(orphan.terminalAction == .appTerminated)
        #expect(wideEvent.completions.count == 1)
        // The new visit is started after the sweep, and is not itself swept.
        #expect(wideEvent.started.count == 2)
        #expect(activeVisit(wideEvent)?.terminalAction == nil)
    }

    @available(iOS 16, *)
    @Test("visitStarted without orphans produces no completions", .timeLimit(.minutes(1)))
    func visitStartedWithoutOrphansProducesNoCompletions() {
        let (sut, wideEvent, _) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)
        #expect(wideEvent.completions.isEmpty)
        #expect(wideEvent.discarded.isEmpty)
    }

    @available(iOS 16, *)
    @Test("A superseded visit is discarded rather than completed", .timeLimit(.minutes(1)))
    func supersededVisitIsDiscarded() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)
        guard let firstVisit = activeVisit(wideEvent) else {
            Issue.record("Expected an active visit")
            return
        }

        clock.advance(by: 1)
        sut.visitStarted(trigger: .newTabOpened, launchKeyboardMode: .down, toggleEnabled: true)

        #expect(wideEvent.completions.isEmpty)
        #expect(wideEvent.discarded.count == 1)
        #expect((wideEvent.discarded.first as? NewTabPageSessionWideEventData)?.globalData.id == firstVisit.globalData.id)
        #expect(wideEvent.started.count == 2)
        #expect(activeVisit(wideEvent)?.trigger == .newTabOpened)
    }

    @available(iOS 16, *)
    @Test("Burning drops the visit it interrupted and opens an after-fire one", .timeLimit(.minutes(1)))
    func burnDiscardsInterruptedVisitAndOpensAfterFireVisit() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .down, toggleEnabled: true)
        guard let interruptedVisit = activeVisit(wideEvent) else {
            Issue.record("Expected an active visit")
            return
        }

        // The Fire button clears everything and lands on a fresh New Tab Page, which starts
        // the next visit. The interrupted one has no terminal of its own until the data
        // clearing hook is wired, so it is dropped rather than reported.
        clock.advance(by: 3)
        sut.visitStarted(trigger: .newTabOpenedAfterFire, launchKeyboardMode: .down, toggleEnabled: true)

        #expect(wideEvent.completions.isEmpty)
        #expect(wideEvent.discarded.count == 1)
        #expect((wideEvent.discarded.first as? NewTabPageSessionWideEventData)?.globalData.id == interruptedVisit.globalData.id)
        #expect(activeVisit(wideEvent)?.trigger == .newTabOpenedAfterFire)

        clock.advance(by: 2)
        sut.visitBackgrounded()

        let completion = lastCompletion(wideEvent)
        #expect(completion?.0.trigger == .newTabOpenedAfterFire)
        #expect(completion?.0.terminalAction == .appBackgrounded)
    }

    @available(iOS 16, *)
    @Test("A stale visit is completed as a timeout at the next visitStarted, not discarded", .timeLimit(.minutes(1)))
    func staleVisitIsCompletedAtNextVisitStarted() {
        let (sut, wideEvent, clock) = makeSUT()
        sut.visitStarted(trigger: .appOpen, launchKeyboardMode: .up, toggleEnabled: false)

        clock.advance(by: 60)
        sut.visitStarted(trigger: .newTabOpened, launchKeyboardMode: .down, toggleEnabled: false)

        #expect(wideEvent.discarded.isEmpty)
        #expect(wideEvent.completions.count == 1)
        #expect(lastCompletion(wideEvent)?.0.terminalAction == .noActionTimeout)
        // Replacing the visit is what removed it from the screen, so that is its end.
        #expect(lastCompletion(wideEvent)?.0.sessionInterval.durationMilliseconds == 60_000)
        #expect(wideEvent.started.count == 2)
    }
}
