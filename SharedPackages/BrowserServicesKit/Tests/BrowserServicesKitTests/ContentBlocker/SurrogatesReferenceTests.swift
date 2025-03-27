//
//  SurrogatesReferenceTests.swift
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
@testable import TrackerRadarKit
import os.log
import WebKit
import BrowserServicesKit
import Common

final class SurrogatesReferenceTests: XCTestCase {
    private let schemeHandler = TestSchemeHandler()
    private var mockWebsite: MockWebsite!
    private let userScriptDelegateMock = MockSurrogatesUserScriptDelegate()
    private let navigationDelegateMock = MockNavigationDelegate()
    private let tld = TLD()
    private var redirectTests = [RefTests.Test]()
    private var webView: WKWebView!

    private enum Resource {
        static let trackerRadar = "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/tracker_radar_reference.json"
        static let tests = "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/domain_matching_tests.json"
        static let surrogates = "Resources/privacy-reference-tests/tracker-radar-tests/TR-domain-matching/surrogates.txt"
    }

    func testSurrogates() throws {
        let dataLoader = JsonTestDataLoader()

        let trackerRadarJSONData = dataLoader.fromJsonFile(Resource.trackerRadar)
        let testsData = dataLoader.fromJsonFile(Resource.tests)
        let surrogatesData = dataLoader.fromJsonFile(Resource.surrogates)

        let referenceTests = try JSONDecoder().decode(RefTests.self, from: testsData)
        let surrogateTests = referenceTests.surrogateTests.tests

        let surrogateString = String(data: surrogatesData, encoding: .utf8)!

        let trackerData = try JSONDecoder().decode(TrackerData.self, from: trackerRadarJSONData)
        let encodedData = try? JSONEncoder().encode(trackerData)
        let encodedTrackerData = String(data: encodedData!, encoding: .utf8)!

        let rules = ContentBlockerRulesBuilder(trackerData: trackerData).buildRules(withExceptions: [],
                                                                                    andTemporaryUnprotectedDomains: [])

        let privacyConfig = WebKitTestHelper.preparePrivacyConfig(locallyUnprotected: [],
                                                                  tempUnprotected: [],
                                                                  trackerAllowlist: [:],
                                                                  contentBlockingEnabled: true,
                                                                  exceptions: [])

        let platformTests = surrogateTests.filter {
            let skip = $0.exceptPlatforms?.contains("ios-browser")
            return skip == false || skip == nil
        }

        /*
         We need to split redirect tests from the rest
         redirect surrogates have to be injected in webview and then validated against an expression
         */
        redirectTests = platformTests.filter {
            $0.expectAction == "redirect"
        }

        let notRedirectTests = platformTests.filter {
            $0.expectAction != "redirect"
        }

        for test in notRedirectTests {
            os_log("TEST: %s", test.name)
            let requestURL = URL(string: test.requestURL)!
            let siteURL = URL(string: test.siteURL)!
            let requestType = ContentBlockerRulesBuilder.resourceMapping[test.requestType]
            let rule = rules.matchURL(url: requestURL, topLevel: siteURL, resourceType: requestType!)
            let result = rule?.action

            if test.expectAction == "block" {
                XCTAssertEqual(result, .block())
            } else if test.expectAction == "ignore" {
                XCTAssertTrue(result == nil || result == .ignorePreviousRules())
            }
        }

        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = redirectTests.count

        createWebViewForUserScripTests(trackerData: trackerData,
                                       encodedTrackerData: encodedTrackerData,
                                       surrogates: surrogateString,
                                       privacyConfig: privacyConfig) { webview in

            self.webView = webview
            self.runTestForRedirect(onTestExecuted: testsExecuted)
        }

        waitForExpectations(timeout: 30, handler: nil)
    }

    private func runTestForRedirect(onTestExecuted: XCTestExpectation) {

        guard let test = redirectTests.popLast(),
              let expectExpression = test.expectExpression else {
            return
        }

        os_log("TEST: %s", test.name)

        let requestURL = URL(string: test.requestURL.testSchemeNormalized)!
        let siteURL = URL(string: test.siteURL.testSchemeNormalized)!

        let resource: MockWebsite.EmbeddedResource
        if test.requestType == "image" {
            resource = MockWebsite.EmbeddedResource(type: .image,
                                                    url: requestURL)
        } else if test.requestType == "script" {
            resource = MockWebsite.EmbeddedResource(type: .script,
                                                    url: requestURL)
        } else {
            XCTFail("Unknown request type: \(test.requestType) in test \(test.name)")
            return
        }

        mockWebsite = MockWebsite(resources: [resource])

        schemeHandler.reset()
        schemeHandler.requestHandlers[siteURL] = { _ in
            return self.mockWebsite.htmlRepresentation.data(using: .utf8)!
        }

        let request = URLRequest(url: siteURL)
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache,
                                                          WKWebsiteDataTypeMemoryCache,
                                                          WKWebsiteDataTypeOfflineWebApplicationCache],
                                                modifiedSince: Date(timeIntervalSince1970: 0),
                                                completionHandler: {
            self.webView.load(request)
        })

        navigationDelegateMock.onDidFinishNavigation = {

            XCTAssertEqual(self.userScriptDelegateMock.detectedSurrogates.count, 1)

            if let request = self.userScriptDelegateMock.detectedSurrogates.first {
                XCTAssertTrue(request.isBlocked, "Surrogate should block request \(requestURL)")
                XCTAssertEqual(request.url, requestURL.absoluteString)
            }

            self.userScriptDelegateMock.reset()

            self.webView?.evaluateJavaScript(expectExpression, completionHandler: { result, err in
                XCTAssertNil(err)

                if let result = result as? Bool {
                    XCTAssertTrue(result, "Expression \(expectExpression) should return true")
                    onTestExecuted.fulfill()

                    DispatchQueue.main.async {
                        self.runTestForRedirect(onTestExecuted: onTestExecuted)
                    }
                }
            })
        }
    }

    private func createWebViewForUserScripTests(trackerData: TrackerData,
                                                encodedTrackerData: String,
                                                surrogates: String,
                                                privacyConfig: PrivacyConfiguration,
                                                completion: @escaping (WKWebView) -> Void) {

        var tempUnprotected = privacyConfig.tempUnprotectedDomains.filter { !$0.trimmingWhitespace().isEmpty }
        tempUnprotected.append(contentsOf: privacyConfig.exceptionsList(forFeature: .contentBlocking))

        let exceptions = DefaultContentBlockerRulesExceptionsSource.transform(allowList: privacyConfig.trackerAllowlist.entries)

        WebKitTestHelper.prepareContentBlockingRules(trackerData: trackerData,
                                                     exceptions: privacyConfig.userUnprotectedDomains,
                                                     tempUnprotected: tempUnprotected,
                                                     trackerExceptions: exceptions) { rules in
            guard let rules = rules else {
                XCTFail("Rules were not compiled properly")
                return
            }

            let configuration = WKWebViewConfiguration()
            configuration.setURLSchemeHandler(self.schemeHandler, forURLScheme: self.schemeHandler.scheme)

            let webView = WKWebView(frame: .init(origin: .zero, size: .init(width: 500, height: 1000)),
                                    configuration: configuration)
            webView.navigationDelegate = self.navigationDelegateMock

            let config = TestSchemeSurrogatesUserScriptConfig(privacyConfig: privacyConfig,
                                                              surrogates: surrogates,
                                                              trackerData: trackerData,
                                                              encodedSurrogateTrackerData: encodedTrackerData,
                                                              tld: self.tld,
                                                              isDebugBuild: true)

            let userScript = SurrogatesUserScript(configuration: config)
            userScript.delegate = self.userScriptDelegateMock

            for messageName in userScript.messageNames {
                configuration.userContentController.addScriptMessageHandler(userScript, contentWorld: .page, name: messageName)
            }

            configuration.userContentController.addUserScript(WKUserScript(source: userScript.source,
                                                                           injectionTime: .atDocumentStart,
                                                                           forMainFrameOnly: false))
            configuration.userContentController.add(rules)

            completion(webView)
        }
    }
}

#endif
