//
//  PageSignals.swift
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

import Common
import Foundation

/// A snapshot of the signals collected for one main-frame navigation.
public struct PageSignals {
    public var pageHost: String?

    /// Distinct resource load errors per eTLD+1 (or raw host when no registrable domain exists).
    public var resourceFailures: [String: Set<PageResourceLoadError>] = [:]
    public var blockedLoads = 0
    public var blockedCookies = 0
    public var modifiedHeaders = 0
    public var blockedDomains: [String: Int] = [:]
    public var navigationFinished = false
    public var renderMilestones: UInt?

    /// False once visible content is observed, even while loading; true after finishing without
    /// visible content. Nil until rendering progress is observed and either condition is met.
    public var isBlankPage: Bool? {
        guard let milestones = renderMilestones else {
            return nil
        }

        let visibleContent = RenderingProgress.firstVisuallyNonEmptyLayout | RenderingProgress.firstMeaningfulPaint
        if milestones & visibleContent != 0 {
            return false
        }

        return navigationFinished ? true : nil
    }
}

/// Values from WebKit's _WKRenderingProgressEvents.
private enum RenderingProgress {
    static let firstVisuallyNonEmptyLayout: UInt = 1 << 1
    static let firstMeaningfulPaint: UInt = 1 << 8
}

/// Collects page signals. Platform adapters own its lifecycle and supply events.
@MainActor
public final class PageSignalsCollector {
    public private(set) var signals = PageSignals()

    private let tld: TLD

    /// Non-public-suffix hosts fall back to their raw host.
    public init(tld: TLD) {
        self.tld = tld
    }

    /// Call when a main-frame navigation commits (including reloads) and when discarding a page.
    public func reset(for url: URL?) {
        signals = PageSignals(pageHost: url?.host.map(domain))
    }

    public func recordContentRuleListAction(_ action: ContentRuleListAction, forURL url: URL) {
        if action.blockedLoad == true {
            signals.blockedLoads += 1
            if let host = url.host {
                signals.blockedDomains[domain(host), default: 0] += 1
            }
        }

        if action.blockedCookies == true {
            signals.blockedCookies += 1
        }

        if action.modifiedHeaders == true {
            signals.modifiedHeaders += 1
        }
    }

    public func recordResourceFailure(_ error: PageResourceLoadError, for url: URL) {
        guard let host = url.host else {
            return
        }

        let resourceDomain = domain(host)
        signals.resourceFailures[resourceDomain, default: []].insert(error)
    }

    public func recordNavigationFinished() {
        signals.navigationFinished = true
    }

    public func recordRenderingProgress(_ events: UInt) {
        signals.renderMilestones = (signals.renderMilestones ?? 0) | events
    }

    private func domain(_ host: String) -> String {
        tld.eTLDplus1(host) ?? host
    }
}
