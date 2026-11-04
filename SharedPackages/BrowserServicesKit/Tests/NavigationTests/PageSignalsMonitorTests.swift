//
//  PageSignalsMonitorTests.swift
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

#if PRIVATE_PAGE_SIGNALS_ENABLED
import Common
import Foundation
import Testing

@testable import DDGNavigation

@MainActor
struct PageSignalsMonitorTests {

    enum Event: CaseIterable {
        case commit
        case provisionalFailure
        case blockedLoad
    }

    private let flag = FlagStub()
    private let monitor: PageSignalsMonitor

    init() {
        monitor = PageSignalsMonitor(tld: TLD(), isEnabled: { [flag] in flag.isOn })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Events are ignored while the flag is off", .timeLimit(.minutes(1)), arguments: Event.allCases)
    func eventsAreIgnoredWhileDisabled(event: Event) {
        flag.isOn = false
        send(event, url: URL(string: "https://www.example.com")!)

        flag.isOn = true
        let signals = monitor.pageSignals

        #expect(signals?.host == nil)
        #expect(signals?.resourceFailures.isEmpty == true)
        #expect(signals?.blockedLoads == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag off stops reporting collected signals", .timeLimit(.minutes(1)))
    func disablingStopsReporting() {
        monitor.didCommitNavigation(to: URL(string: "https://www.example.com")!)
        #expect(monitor.pageSignals?.host == "example.com")

        flag.isOn = false

        #expect(monitor.pageSignals == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag on starts collecting at the next commit", .timeLimit(.minutes(1)))
    func enablingStartsCollectingAtNextCommit() {
        flag.isOn = false
        monitor.didCommitNavigation(to: URL(string: "https://www.previous.com")!)

        flag.isOn = true
        monitor.didCommitNavigation(to: URL(string: "https://www.example.com")!)
        send(.blockedLoad, url: URL(string: "https://tracker.com/pixel.gif")!)

        #expect(monitor.pageSignals?.host == "example.com")
        #expect(monitor.pageSignals?.blockedDomains == ["tracker.com": 1])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Provisional failures without a URL leave signals untouched", .timeLimit(.minutes(1)))
    func provisionalFailureWithoutURLIsIgnored() {
        monitor.didCommitNavigation(to: URL(string: "https://www.example.com")!)
        monitor.didFailProvisionalNavigation(to: nil, with: URLError(.cannotFindHost))

        #expect(monitor.pageSignals?.host == "example.com")
        #expect(monitor.pageSignals?.resourceFailures.isEmpty == true)
    }
}

private extension PageSignalsMonitorTests {

    func send(_ event: Event, url: URL) {
        switch event {
        case .commit:
            monitor.didCommitNavigation(to: url)
        case .provisionalFailure:
            monitor.didFailProvisionalNavigation(to: url, with: URLError(.cannotFindHost))
        case .blockedLoad:
            monitor.didPerformContentRuleListAction(ContentRuleListAction(webKitAction: ContentRuleListActionStub(blockedLoad: true)), for: url)
        }
    }
}

private final class FlagStub: @unchecked Sendable {
    var isOn = true
}
#endif
