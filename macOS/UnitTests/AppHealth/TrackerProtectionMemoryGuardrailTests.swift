//
//  TrackerProtectionMemoryGuardrailTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Common
import FoundationExtensions
import ContentBlocking
import TrackerRadarKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Lightweight guardrail tests for tracker protection data processing performance.
///
/// These are coarse wall-clock guardrails, NOT microbenchmarks. Thresholds are set at
/// 5-10x expected values to avoid CI flakiness. No strict resident-memory-delta assertions.
///
/// Guards against perf regressions from TDS data processing in the C-S-S pipeline.
final class TrackerProtectionMemoryGuardrailTests: XCTestCase {

    // MARK: - Synthetic TDS Helpers

    /// Creates a synthetic `TrackerData` with the specified number of trackers and rules.
    private func makeSyntheticTrackerData(trackerCount: Int, rulesPerTracker: Int) -> TrackerData {
        var trackers: [String: KnownTracker] = [:]
        var entities: [String: Entity] = [:]
        var domains: [String: String] = [:]

        for i in 0..<trackerCount {
            let domain = "tracker\(i).com"
            let ownerName = "Owner \(i)"

            var rules: [KnownTracker.Rule] = []
            for r in 0..<rulesPerTracker {
                rules.append(KnownTracker.Rule(
                    rule: "tracker\(i)\\.com/path\(r)\\.js",
                    surrogate: nil,
                    action: .block,
                    options: nil,
                    exceptions: nil
                ))
            }

            trackers[domain] = KnownTracker(
                domain: domain,
                defaultAction: .block,
                owner: KnownTracker.Owner(name: ownerName, displayName: ownerName, ownedBy: nil),
                prevalence: Double(i) / Double(trackerCount),
                subdomains: nil,
                categories: ["Advertising"],
                rules: rules
            )

            entities[ownerName] = Entity(
                displayName: ownerName,
                domains: [domain],
                prevalence: Double(i) / Double(trackerCount)
            )

            domains[domain] = ownerName
        }

        return TrackerData(trackers: trackers, entities: entities, domains: domains, cnames: nil)
    }

    /// Creates a synthetic `ResourceObservation` for batch mapping tests.
    private func makeSyntheticObservation(index: Int) -> TrackerProtectionSubfeature.ResourceObservation {
        TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker\(index).com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://testpage.com/")
    }

    // MARK: - Guardrail Tests

    /// Small TDS merge time: 50 trackers, 100 rules → should complete in < 100ms.
    func testSmallTrackerDataMergeTime() {
        let mainTDS = makeSyntheticTrackerData(trackerCount: 50, rulesPerTracker: 2)
        let additionalTDS = makeSyntheticTrackerData(trackerCount: 10, rulesPerTracker: 0)

        let start = CFAbsoluteTimeGetCurrent()

        // Simulate the merge operation done by DefaultTrackerProtectionDataSource
        var trackers = mainTDS.trackers
        var entities = mainTDS.entities
        var domains = mainTDS.domains

        trackers.merge(additionalTDS.trackers) { _, new in new }
        entities.merge(additionalTDS.entities) { _, new in new }
        domains.merge(additionalTDS.domains) { _, new in new }

        let merged = TrackerData(trackers: trackers, entities: entities, domains: domains, cnames: mainTDS.cnames)

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertNotNil(merged)
        XCTAssertLessThan(elapsed, 0.1, "Small TDS merge should complete in < 100ms, took \(elapsed * 1000)ms")
    }

    /// Medium TDS merge time: 500 trackers, 2000 rules → should complete in < 500ms.
    func testMediumTrackerDataMergeTime() {
        let mainTDS = makeSyntheticTrackerData(trackerCount: 500, rulesPerTracker: 4)
        let additionalTDS = makeSyntheticTrackerData(trackerCount: 100, rulesPerTracker: 2)

        let start = CFAbsoluteTimeGetCurrent()

        var trackers = mainTDS.trackers
        var entities = mainTDS.entities
        var domains = mainTDS.domains

        trackers.merge(additionalTDS.trackers) { _, new in new }
        entities.merge(additionalTDS.entities) { _, new in new }
        domains.merge(additionalTDS.domains) { _, new in new }

        let merged = TrackerData(trackers: trackers, entities: entities, domains: domains, cnames: mainTDS.cnames)

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertNotNil(merged)
        XCTAssertLessThan(elapsed, 0.5, "Medium TDS merge should complete in < 500ms, took \(elapsed * 1000)ms")
    }

    /// Mapper batch throughput: 1000 observations classified → should complete in < 200ms.
    func testMapperBatchThroughput() {
        let tds = makeSyntheticTrackerData(trackerCount: 100, rulesPerTracker: 2)
        let mapper = TrackerProtectionEventMapper(tld: TLD(),
                                                  mainTrackerData: tds,
                                                  unprotectedSites: [],
                                                  tempList: [],
                                                  contentBlockingEnabled: true)
        let observations = (0..<1000).map { makeSyntheticObservation(index: $0 % 100) }

        let start = CFAbsoluteTimeGetCurrent()

        var classifiedCount = 0
        for observation in observations where mapper.classifyResource(observation) != nil {
            classifiedCount += 1
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertGreaterThan(classifiedCount, 0)
        XCTAssertLessThan(elapsed, 0.2, "Classifying 1000 observations should complete in < 200ms, took \(elapsed * 1000)ms")
    }
}
