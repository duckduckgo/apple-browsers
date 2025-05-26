//
//  ContentBlockerRulesManagerInitialCompilationTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

// Tests are disabled on iOS due to WKWebView stability issues on the iOS 17.5+ simulator.
#if os(macOS)

import Foundation
import TrackerRadarKit
import BrowserServicesKit
import WebKit
import XCTest
import Common

final class CountedFulfillmentTestExpectation: XCTestExpectation, @unchecked Sendable {
    private(set) var currentFulfillmentCount: Int = 0

    override func fulfill() {
        currentFulfillmentCount += 1
        super.fulfill()
    }
}

final class ContentBlockerRulesManagerInitialCompilationTests: XCTestCase {

    private static let fakeEmbeddedDataSet = ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules, etag: "\"\(UUID().uuidString)\"")
    private let rulesUpdateListener = RulesUpdateListener()

    func testSuccessfulCompilationStoresLastCompiledRules() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules,
                                                                                                                                etag: ContentBlockerRulesManagerTests.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        let mockLastCompiledRulesStore = MockLastCompiledRulesStore()

        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let expStore = expectation(description: "Rules Stored")
        mockLastCompiledRulesStore.onRulesSet = {
            expStore.fulfill()
        }

        let lookupAndFetchExp =  self.expectation(description: "LRC should be missing")
        let errorHandler = EventMapping<ContentBlockerDebugEvents> { event, _, params, _ in
            if case .contentBlockingLRCMissing = event {
                lookupAndFetchExp.fulfill()
            } else if case .contentBlockingCompilationTaskPerformance(let iterationCount, _) = event {
                XCTAssertEqual(iterationCount, 1)
            } else {
                XCTFail("Unexpected event: \(event)")
            }
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              lastCompiledRulesStore: mockLastCompiledRulesStore,
                                              updateListener: rulesUpdateListener,
                                              errorReporting: errorHandler)

        wait(for: [exp, expStore, lookupAndFetchExp], timeout: 15.0)

        XCTAssertNotNil(mockLastCompiledRulesStore.rules)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.etag, mockRulesSource.trackerData?.etag)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.name, mockRulesSource.ruleListName)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.trackerData, mockRulesSource.trackerData?.tds)
        XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.identifier, cbrm.currentRules.first?.identifier)
    }

    func testInitialCompilation_WhenNoChangesToTDS_ShouldNotFetchLastCompiled() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules,
                                                                                                                                etag: ContentBlockerRulesManagerTests.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        let mockLastCompiledRulesStore = MockLastCompiledRulesStore()
        let identifier = ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                       tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                       tempListId: nil,
                                                       allowListId: nil,
                                                       unprotectedSitesHash: nil)
        let cachedRules = MockLastCompiledRules(name: mockRulesSource.ruleListName,
                                                trackerData: mockRulesSource.trackerData!.tds,
                                                etag: mockRulesSource.trackerData!.etag,
                                                identifier: identifier)

        mockLastCompiledRulesStore.rules = [cachedRules]
        mockLastCompiledRulesStore.onRulesGet = {
            XCTFail("Should use rules cached by WebKit")
        }

        let lookupAndFetchExp =  self.expectation(description: "Should not fetch LRC")

        // simulate the rules have been compiled in the past so the WKContentRuleListStore contains it
        _ = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                       exceptionsSource: mockExceptionsSource,
                                       updateListener: rulesUpdateListener)

        let exp = CountedFulfillmentTestExpectation(description: "Rules Compiled")
        exp.expectedFulfillmentCount = 2
        rulesUpdateListener.onRulesUpdated = { rules in
            exp.fulfill()
            if exp.currentFulfillmentCount == 1 { // finished compilation after first installation
                let errorHandler = EventMapping<ContentBlockerDebugEvents> { event, _, params, _ in
                    if case .contentBlockingFetchLRCSucceeded = event {
                        XCTFail("Should  not fetch LRC")
                    } else if case .contentBlockingLookupRulesSucceeded = event {
                        lookupAndFetchExp.fulfill()
                    } else {
                        XCTFail("Unexpected event: \(event)")
                    }
                }

                _ = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                               exceptionsSource: mockExceptionsSource,
                                               lastCompiledRulesStore: mockLastCompiledRulesStore,
                                               updateListener: self.rulesUpdateListener,
                                               errorReporting: errorHandler)
            }
            assertRules(rules)
        }

        wait(for: [exp, lookupAndFetchExp], timeout: 15.0)

        func assertRules(_ rules: [ContentBlockerRulesManager.Rules]) {
            guard let rules = rules.first else { XCTFail("Couldn't get rules"); return }
            XCTAssertEqual(cachedRules.etag, rules.etag)
            XCTAssertEqual(cachedRules.name, rules.name)
            XCTAssertEqual(cachedRules.trackerData, rules.trackerData)
            XCTAssertEqual(cachedRules.identifier, rules.identifier)
        }
    }

    func testInitialCompilation_WhenNumberOfRuleListsChange_ShouldNotFetchLastCompiled() {

        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules,
                                                                                                                                etag: ContentBlockerRulesManagerTests.makeEtag()),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        let mockLastCompiledRulesStore = MockLastCompiledRulesStore()
        let identifier = ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                       tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                       tempListId: nil,
                                                       allowListId: nil,
                                                       unprotectedSitesHash: nil)
        let cachedRules = MockLastCompiledRules(name: mockRulesSource.ruleListName,
                                                trackerData: mockRulesSource.trackerData!.tds,
                                                etag: mockRulesSource.trackerData!.etag,
                                                identifier: identifier)

        mockLastCompiledRulesStore.rules = [cachedRules]

        let expInitial = CountedFulfillmentTestExpectation(description: "Initial Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            expInitial.fulfill()
        }

        let expCache = CountedFulfillmentTestExpectation(description: "Initial Rules stored in cache")
        mockLastCompiledRulesStore.onRulesSet = {
            expCache.fulfill()
        }

        // simulate the rules have been compiled in the past so the WKContentRuleListStore contains it
        _ = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                       exceptionsSource: mockExceptionsSource,
                                       lastCompiledRulesStore: mockLastCompiledRulesStore,
                                       updateListener: rulesUpdateListener)
        wait(for: [expInitial, expCache], timeout: 15.0)

        let newListName = UUID().uuidString
        mockRulesSource.contentBlockerRulesLists = [ContentBlockerRulesList(name: newListName,
                                                                            trackerData: mockRulesSource.trackerData!,
                                                                            fallbackTrackerData: Self.fakeEmbeddedDataSet)]

        let expCacheLookup = CountedFulfillmentTestExpectation(description: "Initial Rules lookup")
        mockLastCompiledRulesStore.onRulesSet = {}
        mockLastCompiledRulesStore.onRulesGet = {
            expCacheLookup.fulfill()
        }

        let expNext = CountedFulfillmentTestExpectation(description: "Next Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { rules in
            expNext.fulfill()

            guard let rules = rules.first else { XCTFail("Couldn't get rules"); return }
            XCTAssertNotEqual(cachedRules.name, rules.name)
            XCTAssertEqual(newListName, rules.name)
        }

        let lookupAndFetchExp =  self.expectation(description: "Should  not fetch LRC")

        let errorHandler = EventMapping<ContentBlockerDebugEvents> { event, _, params, _ in
            if case .contentBlockingFetchLRCSucceeded = event {
                XCTFail("Should  not fetch LRC")
            } else if case .contentBlockingCompilationTaskPerformance(let iterationCount, _) = event {
                XCTAssertEqual(iterationCount, 1)
            } else if case .contentBlockingNoMatchInLRC = event {
                lookupAndFetchExp.fulfill()
            } else {
                XCTFail("Unexpected event: \(event)")
            }
        }

        _ = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                       exceptionsSource: mockExceptionsSource,
                                       lastCompiledRulesStore: mockLastCompiledRulesStore,
                                       updateListener: rulesUpdateListener,
                                       errorReporting: errorHandler)

        wait(for: [expCacheLookup, expNext, lookupAndFetchExp], timeout: 15.0)
    }

    func testInitialCompilation_WhenThereAreChangesToTDS_ShouldBuildRulesUsingLastCompiledRulesAndScheduleRecompilationWithNewSource() {

        let oldEtag = ContentBlockerRulesManagerTests.makeEtag()
        let mockRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules,
                                                                                                                                etag: oldEtag),
                                                                       embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let updatedEtag = ContentBlockerRulesManagerTests.makeEtag()
        let mockUpdatedRulesSource = MockSimpleContentBlockerRulesListsSource(trackerData: ContentBlockerRulesManagerTests.makeDataSet(tds: ContentBlockerRulesManagerTests.validRules,
                                                                                                                                       etag: updatedEtag),
                                                                              embeddedTrackerData: Self.fakeEmbeddedDataSet)
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        let mockLastCompiledRulesStore = MockLastCompiledRulesStore()
        let oldIdentifier = ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                          tdsEtag: mockRulesSource.trackerData?.etag ?? "\"\"",
                                                          tempListId: nil,
                                                          allowListId: nil,
                                                          unprotectedSitesHash: nil)
        let newIdentifier = ContentBlockerRulesIdentifier(name: DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName,
                                                          tdsEtag: mockUpdatedRulesSource.trackerData?.etag ?? "\"\"",
                                                          tempListId: nil,
                                                          allowListId: nil,
                                                          unprotectedSitesHash: nil)
        let cachedRules = MockLastCompiledRules(name: mockRulesSource.ruleListName,
                                                trackerData: mockRulesSource.trackerData!.tds,
                                                etag: mockRulesSource.trackerData!.etag,
                                                identifier: oldIdentifier)

        mockLastCompiledRulesStore.rules = [cachedRules]

        // simulate the rules have been compiled in the past so the WKContentRuleListStore contains it
        _ = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                       exceptionsSource: mockExceptionsSource,
                                       updateListener: rulesUpdateListener)

        let lookupAndFetchExp =  self.expectation(description: "Fetch LRC succeeded")
        let expOld = CountedFulfillmentTestExpectation(description: "Old Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            expOld.fulfill()

            let errorHandler = EventMapping<ContentBlockerDebugEvents> { event, _, params, _ in
                if case .contentBlockingFetchLRCSucceeded = event {
                    lookupAndFetchExp.fulfill()
                } else if case .contentBlockingCompilationTaskPerformance(let iterationCount, _) = event {
                    XCTAssertEqual(iterationCount, 1)
                } else {
                    XCTFail("Unexpected event: \(event)")
                }
            }

            _ = ContentBlockerRulesManager(rulesSource: mockUpdatedRulesSource,
                                           exceptionsSource: mockExceptionsSource,
                                           lastCompiledRulesStore: mockLastCompiledRulesStore,
                                           updateListener: self.rulesUpdateListener,
                                           errorReporting: errorHandler)
        }

        wait(for: [expOld], timeout: 15.0)

        let expLastCompiledFetched = CountedFulfillmentTestExpectation(description: "Last compiled fetched")
        mockLastCompiledRulesStore.onRulesGet = {
            expLastCompiledFetched.fulfill()
        }

            let expRecompiled = CountedFulfillmentTestExpectation(description: "New Rules Compiled")
            rulesUpdateListener.onRulesUpdated = { _ in
                expRecompiled.fulfill()

                if expRecompiled.currentFulfillmentCount == 1 { // finished compilation after cold start (using last compiled rules)
                    mockLastCompiledRulesStore.onRulesGet = {}
                    XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.etag, oldEtag)
                    XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.name, mockRulesSource.ruleListName)
                    XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.trackerData, mockRulesSource.trackerData?.tds)
                    XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.identifier, oldIdentifier)
                } else if expRecompiled.currentFulfillmentCount == 2 { // finished recompilation of rules due to changed tds
                    XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.etag, updatedEtag)
                    XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.name, mockRulesSource.ruleListName)
                    XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.trackerData, mockRulesSource.trackerData?.tds)
                    XCTAssertEqual(mockLastCompiledRulesStore.rules.first?.identifier, newIdentifier)
                }
            }

        wait(for: [expLastCompiledFetched, expRecompiled, lookupAndFetchExp], timeout: 15.0)

        }

    struct MockLastCompiledRules: LastCompiledRules {

        var name: String
        var trackerData: TrackerData
        var etag: String
        var identifier: ContentBlockerRulesIdentifier

    }

    final class MockLastCompiledRulesStore: LastCompiledRulesStore {

        var onRulesGet: () -> Void = { }
        var onRulesSet: () -> Void = { }

        var _rules: [LastCompiledRules] = []
        var rules: [LastCompiledRules] {
            get {
                onRulesGet()
                return _rules
            }
            set {
                onRulesSet()
                _rules = newValue
            }
        }

        func update(with contentBlockerRules: [ContentBlockerRulesManager.Rules]) {
            rules = contentBlockerRules.map { rules in
                MockLastCompiledRules(name: rules.name,
                                      trackerData: rules.trackerData,
                                      etag: rules.etag,
                                      identifier: rules.identifier)
            }
        }

    }

}

#endif
