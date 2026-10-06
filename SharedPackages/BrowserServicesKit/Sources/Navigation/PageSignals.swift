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

/// Snapshot of the signals collected for one main-frame navigation.
public struct PageSignals {
    public var host: String?
    public var resourceFailures: [String: Set<PageResourceLoadError>] = [:] /// eTLD+1 > Error
    public var blockedDomains: [String: Int] = [:]
    public var blockedLoads = 0
}

@MainActor
public final class PageSignalsCollector {
    public private(set) var signals = PageSignals()
    private let tld: TLD

    public init(tld: TLD) {
        self.tld = tld
    }

    public func startCollectingSignals(for url: URL?) {
        let domain = tld.eTLDPlus1(url: url)
        signals = PageSignals(host: domain)
    }

    /// Main-frame failures never commit, so they start the failed page's signals here.
    public func didFailProvisionalNavigation(to url: URL, with error: Error) {
        guard let resourceLoadError = PageResourceLoadError.resourceLoadError(from: error as NSError, response: nil) else {
            return
        }

        startCollectingSignals(for: url)
        recordResourceFailure(resourceLoadError, for: url)
    }

    public func recordContentRuleListAction(_ action: ContentRuleListAction, for url: URL) {
        guard action.blockedLoad == true else {
            return
        }

        signals.blockedLoads += 1
        guard let domain = tld.eTLDPlus1(url: url) else {
            return
        }

        signals.blockedDomains[domain, default: 0] += 1
    }

    public func recordResourceFailure(_ error: PageResourceLoadError, for url: URL) {
        guard let domain = tld.eTLDPlus1(url: url) else {
            return
        }

        signals
            .resourceFailures[domain, default: []]
            .insert(error)
    }
}

private extension TLD {

    func eTLDPlus1(url: URL?) -> String? {
        guard let host = url?.host else {
            return nil
        }

        return eTLDplus1(host) ?? host
    }
}
