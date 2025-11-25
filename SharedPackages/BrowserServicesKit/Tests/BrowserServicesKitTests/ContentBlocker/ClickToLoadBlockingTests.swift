//
//  ClickToLoadBlockingTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import os.log
import WebKit
import BrowserServicesKit
import TrackerRadarKit
import Common

struct CTLTests: Decodable {

    struct Test: Decodable {

        let description: String
        let site: String
        let request: String
        let ctlProtectionsEnabled: Bool
        let isRequestLoaded: Bool

    }

    static let exampleRules = """
{
  "trackers": {
        "facebook.net": {
            "domain": "facebook.net",
            "owner": {
                "name": "Facebook, Inc.",
                "displayName": "Facebook",
                "privacyPolicy": "https://www.facebook.com/privacy/explanation",
                "url": "https://facebook.com"
            },
            "prevalence": 0.268,
            "fingerprinting": 2,
            "cookies": 0.208,
            "categories": [],
            "default": "ignore",
            "rules": [
                {
                    "rule": "facebook\\\\.net/.*/all\\\\.js",
                    "surrogate": "fb-sdk.js",
                    "action": "block-ctl-fb",
                    "fingerprinting": 1,
                    "cookies": 0.0000408
                },
                {
                    "rule": "facebook\\\\.net/.*/fbevents\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0.108
                },
                {
                    "rule": "facebook\\\\.net/[a-z_A-Z]+/sdk\\\\.js",
                    "surrogate": "fb-sdk.js",
                    "action": "block-ctl-fb",
                    "fingerprinting": 1,
                    "cookies": 0.000334
                },
                {
                    "rule": "facebook\\\\.net/signals/config/",
                    "fingerprinting": 1,
                    "cookies": 0.000101
                },
                {
                    "rule": "facebook\\\\.net\\\\/signals\\\\/plugins\\\\/openbridge3\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0
                },
                {
                    "rule": "facebook\\\\.net/.*/sdk/.*customerchat\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0.00000681
                },
                {
                    "rule": "facebook\\\\.net\\\\/en_US\\\\/messenger\\\\.Extensions\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0
                },
                {
                    "rule": "facebook\\\\.net\\\\/en_US\\\\/sdk\\\\/xfbml\\\\.save\\\\.js",
                    "fingerprinting": 1,
                    "cookies": 0
                },
                {
                    "rule": "facebook\\\\.net/",
                    "action": "block-ctl-fb"
                }
                ]
        }
  },
  "entities": {
    "Facebook, Inc.": {
      "domains": [
        "facebook.net"
      ],
      "displayName": "Facebook",
      "prevalence": 0.1
    }
  },
  "domains": {
    "facebook.net": "Facebook, Inc."
  },
  "cnames": {}
}
"""

    static let domainTests: [CTLTests.Test] = [
        CTLTests.Test(description: "non-CTL tracker request, CTL enabled",
                      site: "https://example.com",
                      request: "https://www.facebook.net/signals/config/config.js",
                      ctlProtectionsEnabled: true,
                      isRequestLoaded: false),
        CTLTests.Test(description: "non-CTL tracker request, CTL disabled",
                      site: "https://www.example.com",
                      request: "https://www.facebook.net/signals/config/config.js",
                      ctlProtectionsEnabled: false,
                      isRequestLoaded: false),
        CTLTests.Test(description: "CTL catch-all tracker, CTL enabled",
                      site: "https://www.example.com",
                      request: "https://www.facebook.net/some.js",
                      ctlProtectionsEnabled: true,
                      isRequestLoaded: false),
        CTLTests.Test(description: "CTL catch-all tracker, CTL disabled",
                      site: "https://www.example.com",
                      request: "https://www.facebook.net/some.js",
                      ctlProtectionsEnabled: false,
                      isRequestLoaded: true),
        CTLTests.Test(description: "CTL SDK request, CTL enabled",
                      site: "https://www.example.com",
                      request: "https://www.facebook.net/EN/fb-sdk.js",
                      ctlProtectionsEnabled: true,
                      isRequestLoaded: false),
        CTLTests.Test(description: "CTL SDK request, CTL disabled",
                      site: "https://www.example.com",
                      request: "https://www.facebook.net/EN/fb-sdk.js",
                      ctlProtectionsEnabled: false,
                      isRequestLoaded: true)
    ]
}

class ClickToLoadBlockingTests: XCTestCase {

    let schemeHandler = TestSchemeHandler()
    let userScriptDelegateMock = MockRulesUserScriptDelegate()
    let navigationDelegateMock = MockNavigationDelegate()
    let tld = TLD()

    var webView: WKWebView!
    var tds: TrackerData!
    var tests = CTLTests.domainTests
    var mockWebsite: MockWebsite!

    var compiledCTLRules: WKContentRuleList!
    var compiledNonCTLRules: WKContentRuleList!

    func setupWebView(trackerData: TrackerData,
                      ctlTrackerData: TrackerData,
                      userScriptDelegate: ContentBlockerRulesUserScriptDelegate,
                      schemeHandler: TestSchemeHandler,
                      completion: @escaping (WKWebView) -> Void) {

        WebKitTestHelper.prepareContentBlockingRules(trackerData: trackerData,
                                                     exceptions: [],
                                                     tempUnprotected: [],
                                                     trackerExceptions: [],
                                                     identifier: "nonCTLRules") { nonCTLRules in

            guard let nonCTLRules = nonCTLRules else {
                XCTFail("Rules were not compiled properly")
                return
            }

            self.compiledNonCTLRules = nonCTLRules
            WebKitTestHelper.prepareContentBlockingRules(trackerData: ctlTrackerData,
                                                         exceptions: [],
                                                         tempUnprotected: [],
                                                         trackerExceptions: [],
                                                         identifier: "ctlRules") { ctlRules in

                guard let ctlRules = ctlRules else {
                    XCTFail("Rules were not compiled properly")
                    return
                }

                self.compiledCTLRules = ctlRules

                let configuration = WKWebViewConfiguration()
                configuration.setURLSchemeHandler(schemeHandler, forURLScheme: schemeHandler.scheme)

                let webView = WKWebView(frame: .init(origin: .zero, size: .init(width: 500, height: 1000)),
                                        configuration: configuration)
                webView.navigationDelegate = self.navigationDelegateMock

                let privacyConfig = WebKitTestHelper.preparePrivacyConfig(locallyUnprotected: [],
                                                                          tempUnprotected: [],
                                                                          trackerAllowlist: [:],
                                                                          contentBlockingEnabled: true,
                                                                          exceptions: [])

                do {
                    let config = try TestSchemeContentBlockerUserScriptConfig(privacyConfiguration: privacyConfig,
                                                                              trackerData: trackerData,
                                                                              ctlTrackerData: ctlTrackerData,
                                                                              tld: self.tld)

                    let userScript = ContentBlockerRulesUserScript(configuration: config)
                    userScript.delegate = userScriptDelegate

                    for messageName in userScript.messageNames {
                        configuration.userContentController.add(userScript, name: messageName)
                    }

                    configuration.userContentController.addUserScript(WKUserScript(source: userScript.source,
                                                                                   injectionTime: .atDocumentStart,
                                                                                   forMainFrameOnly: false))
                    configuration.userContentController.add(nonCTLRules)

                    completion(webView)
                } catch {
                    XCTFail("Failed to initialize TestSchemeContentBlockerUserScriptConfig: \(error)")
                }
            }
        }
    }

    func filterFBTracker(from tds: TrackerData) -> TrackerData {

        guard let fbTracker = tds.trackers["facebook.net"] else {
            XCTFail("Missing FB tracker")
            return TrackerData(trackers: [:], entities: [:], domains: [:], cnames: [:])
        }

        return TrackerData(trackers: ["facebook.net": fbTracker],
                           entities: tds.entities,
                           domains: tds.domains,
                           cnames: [:])
    }

    func testDomainAllowlist() throws {

        let fullTDS = CTLTests.exampleRules.data(using: .utf8)!
        let fullTrackerData = (try? JSONDecoder().decode(TrackerData.self, from: fullTDS))!
        self.tds = fullTrackerData

        let dataSet = TrackerDataManager.DataSet(tds: fullTrackerData, etag: UUID().uuidString)
        let ruleList = ContentBlockerRulesList(name: "TrackerDataSet",
                                               trackerData: nil,
                                               fallbackTrackerData: dataSet)
        let ctlSplitter = ClickToLoadRulesSplitter(rulesList: ruleList)

        guard let splitRules = ctlSplitter.split() else {
            XCTFail("Could not split rules")
            return
        }

        tests = CTLTests.domainTests

        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = tests.count

        setupWebView(trackerData: splitRules.withoutBlockCTL.fallbackTrackerData.tds,
                     ctlTrackerData: splitRules.withBlockCTL.fallbackTrackerData.tds,
                     userScriptDelegate: userScriptDelegateMock,
                     schemeHandler: schemeHandler) { webView in
            self.webView = webView

            self.popTestAndExecute(onTestExecuted: testsExecuted)
        }

        waitForExpectations(timeout: 30, handler: nil)
    }

    private func popTestAndExecute(onTestExecuted: XCTestExpectation) {

        guard let test = tests.popLast() else {
            return
        }

        os_log("TEST: %s", test.description)

        var siteURL = URL(string: test.site.testSchemeNormalized)!
        if siteURL.absoluteString.hasSuffix(".com") {
            siteURL = siteURL.appendingPathComponent("index.html")
        }
        let requestURL = URL(string: test.request.testSchemeNormalized)!

        let resource = MockWebsite.EmbeddedResource(type: .script,
                                                    url: requestURL)

        mockWebsite = MockWebsite(resources: [resource])

        schemeHandler.reset()
        schemeHandler.requestHandlers[siteURL] = { _ in
            return self.mockWebsite.htmlRepresentation.data(using: .utf8)!
        }

        userScriptDelegateMock.reset()

        if test.ctlProtectionsEnabled {
            // CTL protections enabled - adding rule list
            webView.configuration.userContentController.add(self.compiledCTLRules)
            userScriptDelegateMock.shouldProcessCTLTrackers = true
        } else {
            // CTL protections disabled - removing rule list
            webView.configuration.userContentController.remove(self.compiledCTLRules)
            userScriptDelegateMock.shouldProcessCTLTrackers = false
        }

        os_log("Loading %s ...", siteURL.absoluteString)
        let request = URLRequest(url: siteURL)

        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache,
                                                          WKWebsiteDataTypeMemoryCache,
                                                          WKWebsiteDataTypeOfflineWebApplicationCache],
                                                modifiedSince: Date(timeIntervalSince1970: 0),
                                                completionHandler: {
            self.webView.load(request)
        })

        navigationDelegateMock.onDidFinishNavigation = {
            os_log("Website loaded")
            if !test.isRequestLoaded {
                // Only website request
                XCTAssertEqual(self.schemeHandler.handledRequests.count, 1)
                // Only resource request
                XCTAssertEqual(self.userScriptDelegateMock.detectedTrackers.count, 1)

                if let tracker = self.userScriptDelegateMock.detectedTrackers.first {
                    XCTAssert(tracker.isBlocked)
                } else {
                    XCTFail("Expected to detect tracker for test \(test.description)")
                }
            } else {
                // Website request & resource request
                XCTAssertEqual(self.schemeHandler.handledRequests.count, 2)

                if let pageEntity = self.tds.findEntity(forHost: siteURL.host!),
                   let trackerOwner = self.tds.findTracker(forUrl: requestURL.absoluteString)?.owner,
                   pageEntity.displayName == trackerOwner.name {

                    // Nothing to detect - tracker and website have the same entity
                } else {
                    XCTAssertEqual(self.userScriptDelegateMock.detectedTrackers.count, 1)

                    if let tracker = self.userScriptDelegateMock.detectedTrackers.first {
                        XCTAssertFalse(tracker.isBlocked)
                    } else {
                        XCTFail("Expected to detect tracker for test \(test.description)")
                    }
                }
            }

            onTestExecuted.fulfill()
            DispatchQueue.main.async {
                self.popTestAndExecute(onTestExecuted: onTestExecuted)
            }
        }
    }
}

#endif
