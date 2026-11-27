//
//  ContentBlockerSurrogateRulesUnblockingTests.swift
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
import PrivacyConfigTestsUtils
import TrackerRadarKit
import XCTest
@testable import BrowserServicesKit

/// `unblockSurrogateRules` has to reach the rules builder from every rules list, and has to change the compiled
/// rules' identifier only when it is on, so rules compiled before it existed are still found in the cache.
final class ContentBlockerSurrogateRulesUnblockingTests: XCTestCase {

    // MARK: - Identifier

    private func makeIdentifier(unblockSurrogateRules: Bool? = nil) -> ContentBlockerRulesIdentifier {
        guard let unblockSurrogateRules else {
            return ContentBlockerRulesIdentifier(name: "TDS", tdsEtag: "etag", tempListId: "temp", allowListId: "allow",
                                                 unprotectedSitesHash: "sites")
        }
        return ContentBlockerRulesIdentifier(name: "TDS", tdsEtag: "etag", tempListId: "temp", allowListId: "allow",
                                             unprotectedSitesHash: "sites", unblockSurrogateRules: unblockSurrogateRules)
    }

    func testWhenSurrogateRulesAreBlockedThenIdentifierStringIsUnchanged() {
        XCTAssertEqual(makeIdentifier(unblockSurrogateRules: false).stringValue,
                       #""TDS""etag""temp""allow""sites""#)
        XCTAssertEqual(makeIdentifier(unblockSurrogateRules: false).stringValue, makeIdentifier().stringValue)
    }

    func testWhenSurrogateRulesAreUnblockedThenIdentifierStringDiffers() {
        XCTAssertNotEqual(makeIdentifier(unblockSurrogateRules: true).stringValue,
                          makeIdentifier(unblockSurrogateRules: false).stringValue)
    }

    func testWhenOnlyUnblockSurrogateRulesChangesThenDifferenceIsReported() {
        let difference = makeIdentifier(unblockSurrogateRules: false).compare(with: makeIdentifier(unblockSurrogateRules: true))

        XCTAssertEqual(difference, .unblockSurrogateRules)
        XCTAssertNotEqual(makeIdentifier(unblockSurrogateRules: false), makeIdentifier(unblockSurrogateRules: true))
        XCTAssertTrue(ContentBlockerRulesIdentifier.Difference.all.contains(.unblockSurrogateRules))
    }

    // iOS saves the last compiled identifiers, so ones written before this field existed must still decode.
    func testWhenSavedIdentifierHasNoUnblockSurrogateRulesThenItDecodesAsBlocked() throws {
        let json = #"{"name":"\"TDS\"","tdsEtag":"\"etag\"","tempListId":"\"temp\"","allowListId":"\"allow\"","unprotectedSitesHash":"\"sites\""}"#

        let identifier = try JSONDecoder().decode(ContentBlockerRulesIdentifier.self, from: Data(json.utf8))

        XCTAssertFalse(identifier.unblockSurrogateRules)
        XCTAssertEqual(identifier, makeIdentifier())
        XCTAssertEqual(identifier.stringValue, makeIdentifier().stringValue)
    }

    func testWhenIdentifierIsSavedThenUnblockSurrogateRulesSurvives() throws {
        let data = try JSONEncoder().encode(makeIdentifier(unblockSurrogateRules: true))

        let identifier = try JSONDecoder().decode(ContentBlockerRulesIdentifier.self, from: data)

        XCTAssertTrue(identifier.unblockSurrogateRules)
        XCTAssertEqual(identifier, makeIdentifier(unblockSurrogateRules: true))
    }

    // MARK: - Rules lists

    private let trackerData = TrackerData(trackers: ["example.com": KnownTracker(domain: "example.com",
                                                                                defaultAction: .block,
                                                                                owner: .init(name: "Example", displayName: "Example", ownedBy: nil),
                                                                                prevalence: 5.0,
                                                                                subdomains: nil,
                                                                                categories: nil,
                                                                                rules: nil)],
                                          entities: ["Example": Entity(displayName: "Example", domains: ["example.com"], prevalence: 5.0)],
                                          domains: ["example.com": "Example"],
                                          cnames: nil)

    private func makeTrackerDataManager() throws -> TrackerDataManager {
        let data = try JSONEncoder().encode(trackerData)
        return TrackerDataManager(etag: nil, data: nil, embeddedDataProvider: MockEmbeddedDataProvider(data: data, etag: "embedded"))
    }

    func testWhenUnblockSurrogateRulesChangesThenTrackerDataSetListFollowsIt() throws {
        var isEnabled = false
        let source = DefaultContentBlockerRulesListsSource(trackerDataManager: try makeTrackerDataManager(),
                                                           unblockSurrogateRules: { isEnabled })

        XCTAssertEqual(source.contentBlockerRulesLists.map(\.unblockSurrogateRules), [false])

        isEnabled = true
        XCTAssertEqual(source.contentBlockerRulesLists.map(\.unblockSurrogateRules), [true])
    }

    func testWhenNoUnblockSurrogateRulesIsGivenThenSurrogateRulesAreBlocked() throws {
        let source = DefaultContentBlockerRulesListsSource(trackerDataManager: try makeTrackerDataManager())

        XCTAssertEqual(source.contentBlockerRulesLists.map(\.unblockSurrogateRules), [false])
    }

    func testWhenModelIsMadeThenItCarriesUnblockSurrogateRules() {
        for unblockSurrogateRules in [false, true] {
            let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                    trackerData: (self.trackerData, "etag"),
                                                    fallbackTrackerData: (self.trackerData, "embedded"),
                                                    unblockSurrogateRules: unblockSurrogateRules)
            let sourceManager = ContentBlockerRulesSourceManager(rulesList: rulesList,
                                                                 exceptionsSource: MockContentBlockerRulesExceptionsSource())

            let model = sourceManager.makeModel()

            XCTAssertEqual(model?.unblockSurrogateRules, unblockSurrogateRules)
            XCTAssertEqual(model?.rulesIdentifier.unblockSurrogateRules, unblockSurrogateRules)
        }
    }

    // The fallback list must keep the setting too, or a broken TDS would silently start blocking surrogates again.
    func testWhenModelFallsBackToEmbeddedDataThenItKeepsUnblockSurrogateRules() {
        let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                trackerData: nil,
                                                fallbackTrackerData: (self.trackerData, "embedded"),
                                                unblockSurrogateRules: true)
        let sourceManager = ContentBlockerRulesSourceManager(rulesList: rulesList,
                                                             exceptionsSource: MockContentBlockerRulesExceptionsSource())

        XCTAssertEqual(sourceManager.makeModel()?.unblockSurrogateRules, true)
    }

    func testWhenRulesAreSplitForAdClickAttributionThenBothListsKeepUnblockSurrogateRules() throws {
        for unblockSurrogateRules in [false, true] {
            let rulesList = ContentBlockerRulesList(name: "TrackerDataSet",
                                                    trackerData: (self.trackerData, "etag"),
                                                    fallbackTrackerData: (self.trackerData, "embedded"),
                                                    unblockSurrogateRules: unblockSurrogateRules)

            let split = try XCTUnwrap(AdClickAttributionRulesSplitter(rulesList: rulesList, allowlistedTrackerNames: ["example.com"]).split())

            XCTAssertEqual(split.0.unblockSurrogateRules, unblockSurrogateRules)
            XCTAssertEqual(split.1.unblockSurrogateRules, unblockSurrogateRules)
        }
    }

    // MARK: - Recompilation

    func testWhenValueChangesOnUpdateThenChangeIsEmittedOnlyOnce() {
        var value = false
        let updates = PassthroughSubject<Void, Never>()
        var emitted = [Bool]()
        let cancellable = ContentBlockerRulesManager.changes(of: { value }, from: false, on: updates.eraseToAnyPublisher())
            .sink { emitted.append($0) }

        updates.send()
        value = true
        updates.send()
        updates.send()
        value = false
        updates.send()

        XCTAssertEqual(emitted, [true, false])
        cancellable.cancel()
    }

    func testWhenValueDiffersFromInitialOnFirstUpdateThenChangeIsEmitted() {
        let updates = PassthroughSubject<Void, Never>()
        var emitted = [Bool]()
        let cancellable = ContentBlockerRulesManager.changes(of: { true }, from: false, on: updates.eraseToAnyPublisher())
            .sink { emitted.append($0) }

        XCTAssertEqual(emitted, [])
        updates.send()
        XCTAssertEqual(emitted, [true])
        cancellable.cancel()
    }
}
