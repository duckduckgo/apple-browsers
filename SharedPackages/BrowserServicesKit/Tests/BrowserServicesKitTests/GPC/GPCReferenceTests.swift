//
//  GPCReferenceTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import os.log
import WebKit
@testable import TrackerRadarKit

final class GPCReferenceTests: XCTestCase {
    private let userScriptDelegateMock = MockSurrogatesUserScriptDelegate()
    private let navigationDelegateMock = MockNavigationDelegate()
    private let schemeHandler = TestSchemeHandler()
    private static let data = JsonTestDataLoader()
    private static let config = data.fromJsonFile(Resource.config)
    private var javascriptTests = [GpcJavaScriptAPITest]()

    private enum Resource {
        static let config = "Resources/privacy-reference-tests/global-privacy-control/config_reference.json"
        static let tests = "Resources/privacy-reference-tests/global-privacy-control/tests.json"
    }

    private var privacyManager: PrivacyConfigurationManager {
        let embeddedDataProvider = MockEmbeddedDataProvider(data: Self.config,
                                                            etag: "embedded")
        let localProtection = MockDomainsProtectionStore()
        localProtection.unprotectedDomains = []

        return PrivacyConfigurationManager(fetchedETag: nil,
                                           fetchedData: nil,
                                           embeddedDataProvider: embeddedDataProvider,
                                           localProtection: localProtection,
                                           internalUserDecider: MockInternalUserDecider())
    }

    func testGPCHeader() throws {
        let dataLoader = JsonTestDataLoader()

        let testsData = dataLoader.fromJsonFile(Resource.tests)
        let referenceTests = try JSONDecoder().decode(GPCTestData.self, from: testsData)

        let privacyConfig = privacyManager.privacyConfig

        for test in referenceTests.gpcHeader.tests {

            if test.exceptPlatforms.contains("ios-browser") || test.exceptPlatforms.contains("macos-browser") {
                os_log("Skipping test, ignore platform for [%s]", type: .info, test.name)
                continue
            }

            os_log("Testing [%s]", type: .info, test.name)

            let factory = GPCRequestFactory()
            var testRequest = URLRequest(url: URL(string: test.requestURL)!)

            // Simulate request with actual headers
            testRequest.addValue("DDG-Test", forHTTPHeaderField: "User-Agent")
            let request = factory.requestForGPC(basedOn: testRequest,
                                                config: privacyConfig,
                                                gpcEnabled: test.gpcUserSettingOn)

            if !test.gpcUserSettingOn {
                XCTAssertNil(request, "User opt out, request should not exist \([test.name])")
            }

            let hasHeader = request?.allHTTPHeaderFields?[GPCRequestFactory.Constants.secGPCHeader] != nil
            let headerValue = request?.allHTTPHeaderFields?[GPCRequestFactory.Constants.secGPCHeader]

            if test.expectGPCHeader {
                XCTAssertNotNil(request, "Request should exist if expectGPCHeader is true [\(test.name)]")
                XCTAssert(hasHeader, "Couldn't find header for [\(test.requestURL)]")

                if let expectedHeaderValue = test.expectGPCHeaderValue {
                    let headerValue = request?.allHTTPHeaderFields?[GPCRequestFactory.Constants.secGPCHeader]
                    XCTAssertEqual(expectedHeaderValue, headerValue, "Header should be equal [\(test.name)]")
                }
            } else {
                XCTAssertNil(headerValue, "Header value should not exist [\(test.name)]")
            }
        }
    }

    func testGPCJavascriptAPI() throws {
        let dataLoader = JsonTestDataLoader()

        let testsData = dataLoader.fromJsonFile(Resource.tests)
        let referenceTests = try JSONDecoder().decode(GPCTestData.self, from: testsData)

        javascriptTests = referenceTests.gpcJavaScriptAPI.tests.filter {
            $0.exceptPlatforms.contains("macos-browser") == false
        }

        let testsExecuted = expectation(description: "tests executed")
        testsExecuted.expectedFulfillmentCount = javascriptTests.count

        runJavascriptTests(onTestExecuted: testsExecuted)

        waitForExpectations(timeout: 30, handler: nil)
    }

    private func runJavascriptTests(onTestExecuted: XCTestExpectation) {

        guard let test = javascriptTests.popLast() else {
            return
        }

        let siteURL = URL(string: test.siteURL.testSchemeNormalized)!

        schemeHandler.reset()
        schemeHandler.requestHandlers[siteURL] = { _ in
            return "<html></html>".data(using: .utf8)!
        }

        let request = URLRequest(url: siteURL)
        guard let webView = try? createWebViewForUserScripTests(gpcEnabled: test.gpcUserSettingOn, privacyConfig: privacyManager.privacyConfig) else {
            return XCTFail("Failed to create webview for test \(test.name)")
        }

        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache,
                                                          WKWebsiteDataTypeMemoryCache,
                                                          WKWebsiteDataTypeOfflineWebApplicationCache],
                                                modifiedSince: Date(timeIntervalSince1970: 0),
                                                completionHandler: {
            webView.load(request)
        })

        let javascriptToEvaluate = "Navigator.prototype.globalPrivacyControl"

        navigationDelegateMock.onDidFinishNavigation = {

            webView.evaluateJavaScript(javascriptToEvaluate, completionHandler: { result, err in

                XCTAssertNil(err, "Evaluation should not fail")

                if let expectedValue = test.expectGPCAPIValue {
                    switch expectedValue {
                    case "false":
                        XCTAssertTrue(result as? Bool == false, "Test \(test.name) expected value should be false")
                    case "true":
                        XCTAssertTrue(result as? Bool == true, "Test \(test.name) expected value should be true")
                    default:
                        XCTAssertNil(result, "Test \(test.name) expected value should be nil")
                    }
                }

                DispatchQueue.main.async {
                    onTestExecuted.fulfill()
                    self.runJavascriptTests(onTestExecuted: onTestExecuted)
                }
            })
        }
    }

    private func createWebViewForUserScripTests(gpcEnabled: Bool, privacyConfig: PrivacyConfiguration) throws -> WKWebView {

        let properties = ContentScopeProperties(gpcEnabled: gpcEnabled,
                                                sessionKey: UUID().uuidString,
                                                messageSecret: UUID().uuidString,
                                                featureToggles: ContentScopeFeatureToggles.allTogglesOn)

        let contentScopeScript = try ContentScopeUserScript(privacyManager,
                                                            properties: properties,
                                                            privacyConfigurationJSONGenerator: nil)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(self.schemeHandler, forURLScheme: self.schemeHandler.scheme)

        let webView = WKWebView(frame: .init(origin: .zero, size: .init(width: 500, height: 1000)),
                                configuration: configuration)
        webView.navigationDelegate = self.navigationDelegateMock

        for messageName in contentScopeScript.messageNames {
            configuration.userContentController.add(contentScopeScript, name: messageName)
        }

        configuration.userContentController.addUserScript(WKUserScript(source: contentScopeScript.source,
                                                                       injectionTime: .atDocumentStart,
                                                                       forMainFrameOnly: false))

        return webView
    }
}

// MARK: - GPCTestData

private struct GPCTestData: Codable {
    let gpcHeader: GpcHeader
    let gpcJavaScriptAPI: GpcJavaScriptAPI
}

// MARK: - GpcHeader

struct GpcHeader: Codable {
    let name, desc: String
    let tests: [GpcHeaderTest]
}

// MARK: - GpcHeaderTest

struct GpcHeaderTest: Codable {
    let name: String
    let siteURL: String
    let requestURL: String
    let requestType: String
    let gpcUserSettingOn, expectGPCHeader: Bool
    let expectGPCHeaderValue: String?
    let exceptPlatforms: [String]
}

// MARK: - GpcJavaScriptAPI

struct GpcJavaScriptAPI: Codable {
    let name, desc: String
    let tests: [GpcJavaScriptAPITest]
}

// MARK: - GpcJavaScriptAPITest

struct GpcJavaScriptAPITest: Codable {
    let name: String
    let siteURL: String
    let gpcUserSettingOn, expectGPCAPI: Bool
    let expectGPCAPIValue: String?
    let exceptPlatforms: [String]
    let frameURL: String?
}

#endif
