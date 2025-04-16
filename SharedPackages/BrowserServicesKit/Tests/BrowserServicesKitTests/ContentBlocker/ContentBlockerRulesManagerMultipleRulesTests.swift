//
//  ContentBlockerRulesManagerMultipleRulesTests.swift
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

import XCTest
import TrackerRadarKit
import BrowserServicesKit
import WebKit
import Common

class ContentBlockerRulesManagerMultipleRulesTests: ContentBlockerRulesManagerTests {

    let firstRules = """
{
  "trackers": {
    "tracker.com": {
      "domain": "tracker.com",
      "default": "block",
      "owner": {
        "name": "Fake Tracking Inc",
        "displayName": "FT Inc",
        "privacyPolicy": "https://tracker.com/privacy",
        "url": "http://tracker.com"
      },
      "source": [
        "DDG"
      ],
      "prevalence": 0.002,
      "fingerprinting": 0,
      "cookies": 0.002,
      "performance": {
        "time": 1,
        "size": 1,
        "cpu": 1,
        "cache": 3
      },
      "categories": [
        "Ad Motivated Tracking",
        "Advertising",
        "Analytics",
        "Third-Party Analytics Marketing"
      ]
    }
  },
  "entities": {
    "Fake Tracking Inc": {
      "domains": [
        "tracker.com"
      ],
      "displayName": "Fake Tracking Inc",
      "prevalence": 0.1
    }
  },
  "domains": {
    "tracker.com": "Fake Tracking Inc"
  }
}
"""

    let secondRules = """
{
  "trackers": {
    "another-tracker.com": {
      "domain": "another-tracker.com",
      "default": "block",
      "owner": {
        "name": "Fake Tracking Inc",
        "displayName": "FT Inc",
        "privacyPolicy": "https://tracker.com/privacy",
        "url": "http://tracker.com"
      },
      "source": [
        "DDG"
      ],
      "prevalence": 0.002,
      "fingerprinting": 0,
      "cookies": 0.002,
      "performance": {
        "time": 1,
        "size": 1,
        "cpu": 1,
        "cache": 3
      },
      "categories": [
        "Ad Motivated Tracking",
        "Advertising",
        "Analytics",
        "Third-Party Analytics Marketing"
      ]
    }
  },
  "entities": {
    "Fake Tracking Inc": {
      "domains": [
        "another-tracker.com"
      ],
      "displayName": "Fake Tracking Inc",
      "prevalence": 0.1
    }
  },
  "domains": {
    "another-tracker.com": "Fake Tracking Inc"
  }
}
"""

    class MockContentBlockerRulesListsSource: ContentBlockerRulesListsSource {
        let contentBlockerRulesLists: [ContentBlockerRulesList]

        init(firstName: String, firstTD: TrackerDataManager.DataSet?, firstFallbackTD: TrackerDataManager.DataSet,
             secondName: String, secondTD: TrackerDataManager.DataSet?, secondFallbackTD: TrackerDataManager.DataSet) {
            contentBlockerRulesLists = [ContentBlockerRulesList(name: firstName,
                                                                trackerData: firstTD,
                                                                fallbackTrackerData: firstFallbackTD),
                                        ContentBlockerRulesList(name: secondName,
                                                                trackerData: secondTD,
                                                                fallbackTrackerData: secondFallbackTD)]
        }
    }

    private let rulesUpdateListener = RulesUpdateListener()

    let schemeHandler = TestSchemeHandler()
    let navigationDelegateMock = MockNavigationDelegate()

    var webView: WKWebView!

    func setupWebViewForUserScripTests(currentRules: [ContentBlockerRulesManager.Rules],
                                       schemeHandler: TestSchemeHandler) -> WKWebView {

        XCTAssertFalse(currentRules.isEmpty)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: schemeHandler.scheme)

        let webView = WKWebView(frame: .init(origin: .zero, size: .init(width: 500, height: 1000)),
                                configuration: configuration)
        webView.navigationDelegate = self.navigationDelegateMock

        for rule in currentRules {
            configuration.userContentController.add(rule.rulesList)
        }
        return webView
    }

    func testCompilationOfMultipleRulesListsWithSameETag() {

        let sharedETag = Self.makeEtag()
        let mockRulesSource = MockContentBlockerRulesListsSource(firstName: "first",
                                                                 firstTD: Self.makeDataSet(tds: firstRules, etag: sharedETag),
                                                                 firstFallbackTD: Self.makeDataSet(tds: firstRules),
                                                                 secondName: "second",
                                                                 secondTD: Self.makeDataSet(tds: secondRules, etag: sharedETag),
                                                                 secondFallbackTD: Self.makeDataSet(tds: secondRules))
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        XCTAssertNotEqual(mockRulesSource.contentBlockerRulesLists.first?.trackerData?.etag, mockRulesSource.contentBlockerRulesLists.first?.fallbackTrackerData.etag)

        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener)

        wait(for: [exp], timeout: 15.0)

        XCTAssertFalse(cbrm.currentRules.isEmpty)

        for rules in cbrm.currentRules {
            if let source = mockRulesSource.contentBlockerRulesLists.first(where: { $0.name == rules.name }) {
                XCTAssertEqual(source.trackerData?.etag, rules.etag)
            } else {
                XCTFail("Missing rules")
            }
        }

        XCTAssertNotEqual(cbrm.currentRules[0].identifier.stringValue, cbrm.currentRules[1].identifier.stringValue)
    }

    func testBrokenTDSRecompilationAndFallback() {

        let invalidRulesETag = Self.makeEtag()
        let mockRulesSource = MockContentBlockerRulesListsSource(firstName: "first",
                                                                 firstTD: Self.makeDataSet(tds: Self.invalidRules, etag: invalidRulesETag),
                                                                 firstFallbackTD: Self.makeDataSet(tds: firstRules),
                                                                 secondName: "second",
                                                                 secondTD: Self.makeDataSet(tds: Self.invalidRules, etag: invalidRulesETag),
                                                                 secondFallbackTD: Self.makeDataSet(tds: secondRules))
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        XCTAssertNotEqual(mockRulesSource.contentBlockerRulesLists.first?.trackerData?.etag, mockRulesSource.contentBlockerRulesLists.first?.fallbackTrackerData.etag)

        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let errorExp = expectation(description: "No error reported")
        errorExp.expectedFulfillmentCount = 2
        var brokenLists = Set<String>()
        var errorComponents = Set<ContentBlockerDebugEvents.Component>()
        let errorHandler = EventMapping<ContentBlockerDebugEvents> { event, error, params, onComplete in
            if case .contentBlockingCompilationFailed(let listName, let component) = event {
                brokenLists.insert(listName)
                errorComponents.insert(component)
                errorExp.fulfill()
            }
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              errorReporting: errorHandler)

        wait(for: [exp, errorExp], timeout: 15.0)

        XCTAssertEqual(brokenLists, Set(["first", "second"]))
        XCTAssertEqual(errorComponents, Set([.tds]))

        XCTAssertFalse(cbrm.currentRules.isEmpty)

        for rules in cbrm.currentRules {
            if let source = mockRulesSource.contentBlockerRulesLists.first(where: { $0.name == rules.name }) {
                XCTAssertEqual(source.fallbackTrackerData.etag, rules.etag)
            } else {
                XCTFail("Missing rules")
            }
        }
    }

    func testCompilationOfMultipleRulesLists() {

        let mockRulesSource = MockContentBlockerRulesListsSource(firstName: "first",
                                                                 firstTD: Self.makeDataSet(tds: firstRules),
                                                                 firstFallbackTD: Self.makeDataSet(tds: firstRules),
                                                                 secondName: "second",
                                                                 secondTD: Self.makeDataSet(tds: secondRules),
                                                                 secondFallbackTD: Self.makeDataSet(tds: secondRules))
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        XCTAssertNotEqual(mockRulesSource.contentBlockerRulesLists.first?.trackerData?.etag, mockRulesSource.contentBlockerRulesLists.first?.fallbackTrackerData.etag)

        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener)

        wait(for: [exp], timeout: 15.0)

        XCTAssertFalse(cbrm.currentRules.isEmpty)

        for rules in cbrm.currentRules {
            if let source = mockRulesSource.contentBlockerRulesLists.first(where: { $0.name == rules.name }) {
                XCTAssertEqual(source.trackerData?.etag, rules.etag)
            } else {
                XCTFail("Missing rules")
            }
        }
    }

    func testCompilationOfMultipleFallbackRulesLists() {

        let mockRulesSource = MockContentBlockerRulesListsSource(firstName: "first",
                                                                 firstTD: nil,
                                                                 firstFallbackTD: Self.makeDataSet(tds: firstRules),
                                                                 secondName: "second",
                                                                 secondTD: nil,
                                                                 secondFallbackTD: Self.makeDataSet(tds: secondRules))
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        XCTAssertNotEqual(mockRulesSource.contentBlockerRulesLists.first?.trackerData?.etag, mockRulesSource.contentBlockerRulesLists.first?.fallbackTrackerData.etag)

        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener)

        wait(for: [exp], timeout: 15.0)

        XCTAssertFalse(cbrm.currentRules.isEmpty)

        for rules in cbrm.currentRules {
            if let source = mockRulesSource.contentBlockerRulesLists.first(where: { $0.name == rules.name }) {
                XCTAssertEqual(source.fallbackTrackerData.etag, rules.etag)
            } else {
                XCTFail("Missing rules")
            }
        }
    }

    func testBrokenFallbackTDSFailure() {

        let mockRulesSource = MockContentBlockerRulesListsSource(firstName: "first",
                                                                 firstTD: Self.makeDataSet(tds: Self.invalidRules),
                                                                 firstFallbackTD: Self.makeDataSet(tds: Self.invalidRules),
                                                                 secondName: "second",
                                                                 secondTD: nil,
                                                                 secondFallbackTD: Self.makeDataSet(tds: secondRules))
        let mockExceptionsSource = MockContentBlockerRulesExceptionsSource()
        XCTAssertNotEqual(mockRulesSource.contentBlockerRulesLists.first?.trackerData?.etag, mockRulesSource.contentBlockerRulesLists.first?.fallbackTrackerData.etag)

        let exp = expectation(description: "Rules Compiled")
        rulesUpdateListener.onRulesUpdated = { _ in
            exp.fulfill()
        }

        let errorExp = expectation(description: "No error reported")
        errorExp.expectedFulfillmentCount = 2
        var brokenLists = Set<String>()
        var errorComponents = Set<ContentBlockerDebugEvents.Component>()
        let errorHandler = EventMapping<ContentBlockerDebugEvents> { event, error, params, onComplete in
            if case .contentBlockingCompilationFailed(let listName, let component) = event {
                brokenLists.insert(listName)
                errorComponents.insert(component)
                errorExp.fulfill()
            }
        }

        let cbrm = ContentBlockerRulesManager(rulesSource: mockRulesSource,
                                              exceptionsSource: mockExceptionsSource,
                                              updateListener: rulesUpdateListener,
                                              errorReporting: errorHandler)

        wait(for: [exp, errorExp], timeout: 15.0)

        XCTAssertEqual(brokenLists, Set(["first"]))
        XCTAssertEqual(errorComponents, Set([.tds, .fallbackTds]))

        XCTAssertEqual(cbrm.currentRules.count, 1)
        XCTAssertEqual(cbrm.currentRules.first?.name, "second")
    }

}

#endif
