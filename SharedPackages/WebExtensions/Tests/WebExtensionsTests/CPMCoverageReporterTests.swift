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
        #expect(CPMCoverageCounts(summary: summary).unhandled == expected)
    }

    @Test("Missing keys count as zero", .timeLimit(.minutes(1)))
    func missingKeys() {
        #expect(CPMCoverageCounts(summary: [:]) == CPMCoverageCounts(unhandled: 0, pages: 0))
        #expect(reportedEvents([:], siteRank: .top10k).isEmpty)
    }

    @Test("Counts are clamped so a malformed message cannot loop for long or overflow", .timeLimit(.minutes(1)))
    func clampsCounts() {
        let max = CPMCoverageCounts.maxCount
        #expect(CPMCoverageCounts(unhandled: Int.max, pages: Int.max) == CPMCoverageCounts(unhandled: max, pages: max))
        #expect(CPMCoverageCounts(unhandled: -5, pages: Int.min) == CPMCoverageCounts(unhandled: 0, pages: 0))
        #expect(CPMCoverageCounts(summary: ["init": Int.max, "detected-by-patterns": Int.max, "detected-by-both": -1]).unhandled == max)
        #expect(CPMCoverageCounts(summary: ["detected-by-patterns": Int.min, "detected-by-both": Int.max]).unhandled == 0)
    }

    @Test("Counts report one event per unit", .timeLimit(.minutes(1)))
    func countsReportOneEventPerUnit() {
        var events: [String: Int] = [:]
        CPMCoverageReporter.report(counts: CPMCoverageCounts(unhandled: 2, pages: 3), siteRank: .top10k) { events[$0, default: 0] += 1 }
        #expect(events == [
            EventType.pages: 3, EventType.pagesTop10k: 3,
            EventType.unhandled: 2, EventType.unhandledTop10k: 2,
        ])
    }

    @Test("A top10k summary feeds both the total and the top10k counters", .timeLimit(.minutes(1)))
    func top10kSummary() {
        let events = reportedEvents(["init": 4, "detected-by-patterns": 3, "detected-by-both": 1], siteRank: .top10k)
        #expect(events == [
            EventType.pages: 4, EventType.pagesTop10k: 4,
            EventType.unhandled: 2, EventType.unhandledTop10k: 2,
        ])
    }

    @Test("Other and unknown site ranks feed only the total counters", .timeLimit(.minutes(1)),
          arguments: [CPMSiteRank.other, nil])
    func nonTop10kSummary(siteRank: CPMSiteRank?) {
        let events = reportedEvents(["init": 4, "detected-by-patterns": 3, "detected-by-both": 1], siteRank: siteRank)
        #expect(events == [EventType.pages: 4, EventType.unhandled: 2])
    }

    @Test("Patterns below both sends no unhandled events", .timeLimit(.minutes(1)))
    func patternsBelowBoth() {
        let events = reportedEvents(["init": 2, "detected-by-patterns": 1, "detected-by-both": 3], siteRank: .top10k)
        #expect(events == [EventType.pages: 2, EventType.pagesTop10k: 2])
    }

    @Test("Other summary keys are ignored", .timeLimit(.minutes(1)))
    func otherKeysIgnored() {
        let events = reportedEvents(["popup-found": 7, "done": 5, "detected-only-rules": 2], siteRank: .other)
        #expect(events.isEmpty)
    }

    private func reportedDomains(_ hosts: [String], siteRank: CPMSiteRank?) -> [(type: String, domain: String)] {
        var events: [(type: String, domain: String)] = []
        CPMCoverageReporter.report(unhandledHosts: hosts, siteRank: siteRank) { type, data in
            events.append((type, data[CPMCoverageReporter.domainKey] ?? ""))
        }
        return events
    }

    @Test("Hosts are reduced to their registrable domain and sent once", .timeLimit(.minutes(1)))
    func hostsAreReducedToRegistrableDomains() {
        let events = reportedDomains(["www.example.com", "shop.example.com", "News.Example.co.uk", "example.co.uk"], siteRank: .other)
        #expect(events.map(\.type) == [EventType.unhandledDomain, EventType.unhandledDomain])
        #expect(events.map(\.domain) == ["example.co.uk", "example.com"])
    }

    @Test("A top10k host feeds both the total and the top10k domain event", .timeLimit(.minutes(1)))
    func top10kDomain() {
        let events = reportedDomains(["www.example.com"], siteRank: .top10k)
        #expect(events.map(\.type) == [EventType.unhandledDomain, EventType.unhandledDomainTop10k])
        #expect(events.allSatisfy { $0.domain == "example.com" })
    }

    @Test("Hosts without a registrable domain send nothing", .timeLimit(.minutes(1)))
    func hostsWithoutRegistrableDomain() {
        #expect(reportedDomains(["127.0.0.1", "com", "", "localhost"], siteRank: .other).isEmpty)
    }

    @Test("Only the first hosts of a report are used", .timeLimit(.minutes(1)))
    func hostsAreCapped() {
        let hosts = (0..<(CPMCoverageReporter.maxHostsPerReport + 50)).map { "site\($0).example.com" } + (0..<10).map { "other\($0).example.org" }
        #expect(reportedDomains(hosts, siteRank: .other).count == 1)
    }

    @Test("Unhandled hosts are the detected sites no rule detected, by site rank", .timeLimit(.minutes(1)))
    func unhandledHostsOfSites() {
        let sites = [
            "a": CPMDetectedSite(host: "www.example.com", siteRank: .top10k),
            "b": CPMDetectedSite(host: "shop.example.org", siteRank: .other),
            "c": CPMDetectedSite(host: "example.net", siteRank: .other),
            "d": CPMDetectedSite(host: "example.org", siteRank: nil),
            "e": CPMDetectedSite(host: "shop.example.org", siteRank: .other),
        ]

        let hosts = CPMCoverageReporter.unhandledHosts(of: sites, detectedByBoth: ["c"])

        let expected: [CPMSiteRank?: Set<String>] = [
            CPMSiteRank.top10k: ["www.example.com"],
            CPMSiteRank.other: ["shop.example.org"],
            nil: ["example.org"],
        ]
        #expect(hosts == expected)
    }
}
