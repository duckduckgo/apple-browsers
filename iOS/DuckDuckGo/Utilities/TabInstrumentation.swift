//
//  TabInstrumentation.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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
import os

/// Signposts for the native tab-loading lifecycle, isolated with the WebKit delegate callbacks.
///
/// "Load Page" starts at main-frame action policy and ends after the native didFinish handler.
/// "Provisional Navigation" ends at commit; "Load Document" ends at WebKit's didFinish callback.
/// Native request preparation and web-view setup have their own intervals, since they can precede
/// WebKit's first callback. Navigation completion does not imply first paint or page interactivity.
/// Every interval includes an opaque tab ID. No URL, page title, or search text is recorded.
@MainActor
final class TabInstrumentation {

    enum Outcome: String {
        case completed, cancelled, failed, superseded, stopped, download
        case processTerminated, webViewReplaced, dataCleared, tabClosed, evicted, skipped, timedOut
    }

    /// An interval can end only once. Retaining it in an asynchronous callback preserves its identity
    /// even if another navigation starts before that callback runs.
    @MainActor
    final class Interval {
        let key = UUID()
        let id: OSSignpostID
        private let name: StaticString
        private let signposter: OSSignposter
        private let isPageLoad: Bool
        private var state: OSSignpostIntervalState?
        private var hasEnded = false
        fileprivate var onEnd: (() -> Void)?

        var isActive: Bool { !hasEnded }

        fileprivate init(_ name: StaticString, signposter: OSSignposter, tabID: UInt64, isPageLoad: Bool, parent: Interval?) {
            self.name = name
            self.signposter = signposter
            self.isPageLoad = isPageLoad
            id = signposter.makeSignpostID()
            guard signposter.isEnabled else { return }
            if isPageLoad {
                // Preserve the custom DDG Timeline schema without recording the URL.
                state = signposter.beginInterval(name, id: id, "Loading URL: Load-\(self.key.uuidString, privacy: .public) in \(tabID)")
            } else {
                let context = "Tab-\(tabID) Interval-\(key) Parent-\(parent?.key.uuidString ?? "none")"
                state = signposter.beginInterval(name, id: id, "Event: \(String(describing: name), privacy: .public) info: \(context, privacy: .public)")
            }
        }

        func end(_ outcome: Outcome = .completed) {
            guard !hasEnded else { return }
            hasEnded = true
            let state = self.state
            self.state = nil
            if let state {
                if isPageLoad {
                    signposter.endInterval(name, state, "Loading Finished: \(outcome.rawValue, privacy: .public)")
                } else {
                    signposter.endInterval(name, state, "Result: \(outcome.rawValue, privacy: .public)")
                }
            }
            onEnd?()
            onEnd = nil
        }

    }

    @MainActor
    final class NavigationPolicy {
        let interval: Interval
        fileprivate let load: Interval?
        fileprivate let continuesNavigation: Bool

        fileprivate init(interval: Interval, load: Interval?, continuesNavigation: Bool) {
            self.interval = interval
            self.load = load
            self.continuesNavigation = continuesNavigation
        }
    }

    private struct Navigation {
        // Retain the handle so a newer navigation cannot reuse its identity.
        let handle: AnyObject
        let load: Interval
        var phase: Interval
        var progressMilestones = Set<Int>()
    }

    private let tabID = UInt64.random(in: 1...UInt64.max)
    private let signposter = OSSignposter(logHandle: OSLog(subsystem: "com.duckduckgo.instrumentation", category: "TabInstrumentation"))
    private var intervals = [UUID: Interval]()
    private var policies = [UUID: NavigationPolicy]()
    private var allowedLoad: Interval?
    private var navigation: Navigation?

    var currentLoad: Interval? { navigation?.load }

    func prepareWebView(replacing: Bool) -> Interval {
        if replacing {
            endAll(.webViewReplaced)
        }
        return begin("Prepare Web View")
    }

    @discardableResult
    func begin(_ name: StaticString, parent: Interval? = nil) -> Interval {
        makeInterval(name, parent: parent)
    }

    private func makeInterval(_ name: StaticString, isPageLoad: Bool = false, parent: Interval? = nil) -> Interval {
        let interval = Interval(name, signposter: signposter, tabID: tabID, isPageLoad: isPageLoad, parent: parent)
        let key = interval.key
        interval.onEnd = { [weak self] in self?.intervals[key] = nil }
        intervals[key] = interval
        return interval
    }

    func event(_ name: StaticString, in interval: Interval? = nil, detail: String = "") {
        guard signposter.isEnabled else { return }
        guard interval?.isActive != false else { return }
        signposter.emitEvent(name, id: interval?.id ?? signposter.makeSignpostID(),
                             "Tab-\(self.tabID) \(detail, privacy: .public)")
    }

    func beginNavigationPolicy(isSameDocument: Bool, isRedirect: Bool) -> NavigationPolicy {
        let continuesNavigation = isRedirect && navigation != nil
        let load: Interval?
        if isSameDocument {
            load = nil
        } else if continuesNavigation {
            load = navigation?.load
        } else {
            load = makeInterval("Load Page", isPageLoad: true)
        }
        let policy = NavigationPolicy(interval: begin("Navigation Action Policy", parent: load), load: load, continuesNavigation: continuesNavigation)
        policies[policy.interval.key] = policy
        event(isSameDocument ? "Same Document Navigation" : "Navigation Requested", in: load ?? policy.interval)
        return policy
    }

    func endNavigationPolicy(_ policy: NavigationPolicy?, allowed: Bool) {
        guard let policy, policies.removeValue(forKey: policy.interval.key) != nil else { return }
        policy.interval.end(allowed ? .completed : .cancelled)
        guard let load = policy.load, load.isActive else { return }
        event(allowed ? "Navigation Allowed" : "Navigation Cancelled", in: load)
        if !allowed {
            endLoad(load, outcome: .cancelled)
        } else if !policy.continuesNavigation {
            if allowedLoad !== load {
                allowedLoad?.end(.superseded)
            }
            allowedLoad = load
        }
    }

    func didStartNavigation(_ handle: AnyObject?) {
        guard let handle else { return }
        guard navigation?.handle !== handle else { return }
        if let previous = navigation {
            endLoad(previous.load, outcome: .superseded)
        }
        let load = allowedLoad ?? makeInterval("Load Page", isPageLoad: true)
        allowedLoad = nil
        navigation = Navigation(handle: handle, load: load, phase: begin("Provisional Navigation", parent: load))
        event("Provisional Navigation Started", in: load)
    }

    func didRedirectNavigation(_ handle: AnyObject?) {
        guard let handle, navigation?.handle === handle else { return }
        event("Server Redirect", in: navigation?.load)
    }

    func didCommitNavigation(_ handle: AnyObject?) {
        guard let handle, navigation?.handle === handle else { return }
        navigation?.phase.end()
        let phase = begin("Load Document", parent: navigation?.load)
        navigation?.phase = phase
        event("Navigation Committed", in: navigation?.load)
    }

    func didFinishNavigation(_ handle: AnyObject?) {
        guard let handle, navigation?.handle === handle else { return }
        navigation?.phase.end()
        let phase = begin("Finish Navigation", parent: navigation?.load)
        navigation?.phase = phase
        event("WebKit Navigation Finished", in: navigation?.load)
    }

    func completeNavigation(_ handle: AnyObject?, outcome: Outcome) {
        guard let handle, let navigation, navigation.handle === handle else { return }
        endLoad(navigation.load, outcome: outcome)
    }

    /// Response policy has no navigation handle. Capture its load before awaiting the decision so
    /// a late response cannot close a newer navigation.
    func endResponsePolicy(load: Interval?, outcome: Outcome) {
        guard let load, outcome != .completed else { return }
        endLoad(load, outcome: outcome)
    }

    private func endLoad(_ load: Interval, outcome: Outcome) {
        if navigation?.load === load {
            navigation?.phase.end(outcome)
            navigation = nil
        }
        if allowedLoad === load {
            allowedLoad = nil
        }
        load.end(outcome)
    }

    func recordProgress(_ progress: Double) {
        guard navigation != nil else { return }
        for percent in [25, 50, 75, 100] where progress >= Double(percent) / 100 {
            if navigation?.progressMilestones.insert(percent).inserted == true {
                event("Estimated Loading Progress", in: navigation?.load, detail: "percent=\(percent)")
            }
        }
    }

    func endAll(_ outcome: Outcome) {
        // Copy first: ending an interval removes it from the dictionary.
        for interval in Array(intervals.values) {
            interval.end(outcome)
        }
        policies.removeAll()
        allowedLoad = nil
        navigation = nil
    }

}
