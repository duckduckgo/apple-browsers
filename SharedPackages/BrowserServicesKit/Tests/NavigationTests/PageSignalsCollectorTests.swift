//
//  PageSignalsCollectorTests.swift
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
import Testing

@testable import DDGNavigation

@MainActor
struct PageSignalsCollectorTests {

    private let collector = PageSignalsCollector(tld: TLD())
    private let dnsError = PageResourceLoadError.error(URLError(.cannotFindHost) as NSError)
    private let serverError = PageResourceLoadError.statusCode(503)

    @available(iOS 16, macOS 13, *)
    @Test("Starting collection resets signals to the page's eTLD+1", .timeLimit(.minutes(1)))
    func startCollectingResetsSignals() {
        collector.recordResourceFailure(dnsError, for: URL(string: "https://cdn.example.com")!)
        collector.startCollectingSignals(for: URL(string: "https://www.duckduckgo.com/about")!)

        #expect(collector.signals.host == "duckduckgo.com")
        #expect(collector.signals.resourceFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Resource failures are grouped by eTLD+1", .timeLimit(.minutes(1)))
    func resourceFailuresAreGroupedByDomain() {
        collector.recordResourceFailure(dnsError, for: URL(string: "https://a.example.com/1.js")!)
        collector.recordResourceFailure(serverError, for: URL(string: "https://b.example.com/2.js")!)
        collector.recordResourceFailure(dnsError, for: URL(string: "https://example.com/3.js")!)

        #expect(collector.signals.resourceFailures == ["example.com": [dnsError, serverError]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only blocked content rule list actions are counted", .timeLimit(.minutes(1)))
    func onlyBlockedLoadsAreCounted() {
        let url = URL(string: "https://tracker.example.com/pixel.gif")!

        collector.recordContentRuleListAction(ContentRuleListAction(webKitAction: ContentRuleListActionStub(blockedLoad: true)), for: url)
        collector.recordContentRuleListAction(ContentRuleListAction(webKitAction: ContentRuleListActionStub(blockedLoad: true)), for: url)
        collector.recordContentRuleListAction(ContentRuleListAction(webKitAction: ContentRuleListActionStub(blockedLoad: false)), for: url)
        collector.recordContentRuleListAction(ContentRuleListAction(webKitAction: NSObject()), for: url)

        #expect(collector.signals.blockedLoads == 2)
        #expect(collector.signals.blockedDomains == ["example.com": 2])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Provisional failures start the failed page's signals", .timeLimit(.minutes(1)))
    func provisionalFailureStartsSignals() {
        collector.startCollectingSignals(for: URL(string: "https://previous.com")!)
        collector.didFailProvisionalNavigation(to: URL(string: "https://www.example.com")!, with: URLError(.cannotFindHost))

        #expect(collector.signals.host == "example.com")
        #expect(collector.signals.resourceFailures == ["example.com": [dnsError]])
    }
}

/// Mimics `_WKContentRuleListAction`'s `blockedLoad` property.
private final class ContentRuleListActionStub: NSObject {
    @objc let blockedLoad: Bool

    init(blockedLoad: Bool) {
        self.blockedLoad = blockedLoad
    }
}
