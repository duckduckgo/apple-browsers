//
//  NavigationDelayInstrumentation.swift
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

import Combine
import Common
import Core
import Foundation
import UIKit
import WebKit
import WideEvent

/// Launch-scoped state for the navigation delay wide event. Created once at launch, where it completes flows
/// left by a terminated launch, and hands each tab a `NavigationDelayTracker`.
final class NavigationDelayInstrumentation {

    private let wideEvent: WideEventManaging
    private let isOnboarding: () -> Bool
    private var hasClaimedFirstInLaunch = false

    init(wideEvent: WideEventManaging,
         isOnboarding: @escaping () -> Bool = { !DefaultTutorialSettings().hasSeenOnboarding },
         completeOrphanedFlowsOnInit: Bool = true) {
        self.wideEvent = wideEvent
        self.isOnboarding = isOnboarding

        if completeOrphanedFlowsOnInit {
            completeOrphanedFlowsFromPreviousAppSession()
        }
    }

    func makeTracker() -> NavigationDelayTracker {
        NavigationDelayTracker(instrumentation: self)
    }

    fileprivate func claimFirstInLaunch() -> Bool {
        guard !hasClaimedFirstInLaunch else { return false }
        hasClaimedFirstInLaunch = true
        return true
    }

    fileprivate func makeData(scope: NavigationDelayWideEventData.Scope,
                              navigationType: WKNavigationType,
                              url: URL) -> NavigationDelayWideEventData {
        NavigationDelayWideEventData(scope: scope,
                                     navigationType: .init(navigationType),
                                     isDuckDuckGoSearch: url.isDuckDuckGoSearch,
                                     appState: isOnboarding() ? .onboarding : .regular)
    }

    fileprivate func start(_ data: NavigationDelayWideEventData) {
        wideEvent.startFlow(data)
    }

    fileprivate func complete(_ data: NavigationDelayWideEventData, status: WideEventStatus) {
        wideEvent.completeFlow(data, status: status, onComplete: { _, _ in })
    }

    private func completeOrphanedFlowsFromPreviousAppSession() {
        for orphan in wideEvent.getAllFlowData(NavigationDelayWideEventData.self) {
            wideEvent.completeFlow(orphan,
                                   status: .unknown(reason: NavigationDelayWideEventData.appTerminatedReason),
                                   onComplete: { _, _ in })
        }
    }
}

/// Measures one tab's main-frame navigation decisions, from `decidePolicyFor` until the decision reaches WebKit.
/// Only one decision is measured at a time: a new main-frame request replaces the one in flight.
final class NavigationDelayTracker {

    enum WaitOutcome {
        case ready
        case timedOut
        case cancelled
    }

    private struct Measurement {
        let id: UUID
        let data: NavigationDelayWideEventData
        /// First navigations are saved when they start, so one cut short by termination is sent as UNKNOWN next launch.
        /// Later ones are only worth sending if they turn out to be held, so they stay in memory until then.
        let isPersisted: Bool
        var timedOut = false
        var holdCancelled = false
    }

    private let instrumentation: NavigationDelayInstrumentation
    private var current: Measurement?
    private var isFirstInWebView = true
    private var backgroundCancellable: AnyCancellable?

    fileprivate init(instrumentation: NavigationDelayInstrumentation,
                     notificationCenter: NotificationCenter = .default) {
        self.instrumentation = instrumentation
        backgroundCancellable = notificationCenter.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.cancelCurrent(reason: .appBackgrounded)
            }
    }

    /// A new web view replaces the old one, whose pending decisions are abandoned.
    func webViewAttached() {
        cancelCurrent(reason: .navigationReplaced)
        isFirstInWebView = true
    }

    func tabClosed() {
        cancelCurrent(reason: .tabClosed)
    }

    /// Starts measuring a main-frame navigation decision. Returns `nil` for anything other than an http(s) page.
    func navigationRequested(navigationType: WKNavigationType, url: URL?) -> UUID? {
        cancelCurrent(reason: .navigationReplaced)
        guard let url, [.http, .https].contains(url.navigationalScheme) else { return nil }

        let scope: NavigationDelayWideEventData.Scope
        if instrumentation.claimFirstInLaunch() {
            scope = .firstInLaunch
        } else if isFirstInWebView {
            scope = .firstInWebView
        } else {
            scope = .laterHeld
        }
        isFirstInWebView = false

        let data = instrumentation.makeData(scope: scope, navigationType: navigationType, url: url)
        let measurement = Measurement(id: UUID(), data: data, isPersisted: scope != .laterHeld)
        if measurement.isPersisted {
            instrumentation.start(data)
        }
        current = measurement
        return measurement.id
    }

    func webExtensionWaitStarted(_ id: UUID) {
        guard current?.id == id else { return }
        current?.data.webExtensionWait = .startingNow()
    }

    func webExtensionWaitEnded(_ id: UUID, outcome: WaitOutcome) {
        guard current?.id == id else { return }
        current?.data.webExtensionWait?.complete()
        if outcome == .cancelled {
            current?.holdCancelled = true
        }
    }

    /// The content blocking check passed without waiting. Ignored once a wait has been recorded, because
    /// a finished wait re-enters the check. Subframe checks are ignored: only the main frame holds the page.
    func contentBlockingDidNotWait(isMainFrame: Bool) {
        guard isMainFrame, let data = current?.data, data.contentBlockingWait == nil else { return }
        data.contentBlockingCheckedWithoutWait = true
    }

    /// Returns the ID to pass back when the wait ends, so a wait that outlives its navigation can't touch the next one.
    func contentBlockingWaitStarted(path: NavigationDelayWideEventData.ContentBlockingWaitPath, isMainFrame: Bool) -> UUID? {
        guard isMainFrame, let current else { return nil }
        current.data.contentBlockingWait = .startingNow()
        current.data.contentBlockingWaitPath = path
        return current.id
    }

    func contentBlockingWaitEnded(_ id: UUID, outcome: WaitOutcome) {
        guard current?.id == id else { return }
        current?.data.contentBlockingWait?.complete()
        switch outcome {
        case .ready: break
        case .timedOut: current?.timedOut = true
        case .cancelled: current?.holdCancelled = true
        }
    }

    func decisionDelivered(_ id: UUID) {
        guard let measurement = current, measurement.id == id else { return }
        current = nil

        if measurement.timedOut {
            measurement.data.statusReason = .assetsTimeout
            finish(measurement, status: .failure)
        } else if measurement.holdCancelled {
            measurement.data.statusReason = .navigationCancelled
            finish(measurement, status: .cancelled)
        } else {
            finish(measurement, status: .success)
        }
    }

    private func cancelCurrent(reason: NavigationDelayWideEventData.StatusReason) {
        guard let measurement = current else { return }
        current = nil
        measurement.data.statusReason = reason
        finish(measurement, status: .cancelled)
    }

    private func finish(_ measurement: Measurement, status: WideEventStatus) {
        let data = measurement.data
        data.holdInterval.complete()
        data.webExtensionWait?.completeIfOpen()
        data.contentBlockingWait?.completeIfOpen()

        if !measurement.isPersisted {
            guard let holdMs = data.holdMs, holdMs >= NavigationDelayWideEventData.heldThresholdMs else { return }
            instrumentation.start(data)
        }
        instrumentation.complete(data, status: status)
    }
}

private extension WideEvent.MeasuredInterval {

    /// Closes a wait still open when the decision ends early, so its time counts up to that point.
    mutating func completeIfOpen() {
        if end == nil {
            complete()
        }
    }
}
