//
//  CPMCoverageReporterTests.swift
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

import Testing
@testable import WebExtensions

@available(iOS 16, macOS 13, *)
@Suite("CPM coverage reporter")
struct CPMCoverageReporterTests {

    private typealias EventType = CPMCoverageReporter.EventType

    private func reportedEvents(_ summary: [String: Int], siteRank: CPMSiteRank?) -> [String: Int] {
        var events: [String: Int] = [:]
        CPMCoverageReporter.report(summary: summary, siteRank: siteRank) { events[$0, default: 0] += 1 }
        return events
    }

    @Test("Unhandled is detected-by-patterns minus detected-by-both", .timeLimit(.minutes(1)),
          arguments: [
            (patterns: 5, both: 2, expected: 3),
            (patterns: 3, both: 3, expected: 0),
            (patterns: 1, both: 4, expected: 0),
            (patterns: 0, both: 0, expected: 0),
          ])
    func unhandledFormula(patterns: Int, both: Int, expected: Int) {
        let summary = ["detected-by-patterns": patterns, "detected-by-both": both]
        #expect(CPMCoverageReporter.unhandledCount(in: summary) == expected)
    }

    @Test("Missing keys count as zero", .timeLimit(.minutes(1)))
    func missingKeys() {
        #expect(CPMCoverageReporter.unhandledCount(in: [:]) == 0)
        #expect(reportedEvents([:], siteRank: .top10k).isEmpty)
    }

    @Test("A top10k summary feeds both the total and the top10k counters", .timeLimit(.minutes(1)))
    func top10kSummary() {
        let events = reportedEvents(["init": 4, "detected-by-patterns": 3, "detected-by-both": 1], siteRank: .top10k)
        #expect(events == [
            EventType.page: 4, EventType.pageTop10k: 4,
            EventType.unhandled: 2, EventType.unhandledTop10k: 2,
        ])
    }

    @Test("Other and unknown site ranks feed only the total counters", .timeLimit(.minutes(1)),
          arguments: [CPMSiteRank.other, nil])
    func nonTop10kSummary(siteRank: CPMSiteRank?) {
        let events = reportedEvents(["init": 4, "detected-by-patterns": 3, "detected-by-both": 1], siteRank: siteRank)
        #expect(events == [EventType.page: 4, EventType.unhandled: 2])
    }

    @Test("Patterns below both sends no unhandled events", .timeLimit(.minutes(1)))
    func patternsBelowBoth() {
        let events = reportedEvents(["init": 2, "detected-by-patterns": 1, "detected-by-both": 3], siteRank: .top10k)
        #expect(events == [EventType.page: 2, EventType.pageTop10k: 2])
    }

    @Test("Other summary keys are ignored", .timeLimit(.minutes(1)))
    func otherKeysIgnored() {
        let events = reportedEvents(["popup-found": 7, "done": 5, "detected-only-rules": 2], siteRank: .other)
        #expect(events.isEmpty)
    }
}
