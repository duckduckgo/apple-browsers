//
//  MaliciousSiteProtectionIntegrationTests.swift
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

import BrowserServicesKit
import Combine
import Common
import MaliciousSiteProtection
import OHHTTPStubs
import OHHTTPStubsSwift
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@available(macOS 12.0, *)
class MaliciousSiteProtectionIntegrationTests: XCTestCase {

    var window: NSWindow!
    var cancellables: Set<AnyCancellable>!

    // dataSets loading takes long time, so we preload them in a separate task once per the test class
    static func dataManager() async -> MaliciousSiteProtection.DataManager {
        let configurationUrl = FileManager.default.configurationDirectory()
        let fileStore = MaliciousSiteProtection.FileStore(dataStoreURL: configurationUrl)
        let dataManager = MaliciousSiteProtection.DataManager(fileStore: fileStore,
                                                              embeddedDataProvider: MaliciousSiteProtectionManager.EmbeddedDataProvider(),
                                                              fileNameProvider: MaliciousSiteProtectionManager.fileName(for:))
        let preloadDataTask = Task.detached {
            await dataManager.preloadData(for: ThreatKind.allCases)
        }
        await preloadDataTask.value
        return dataManager
    }
    static var initDetectorTask: Task<MaliciousSiteProtectionManager, Never>! = Task {
        let dataManager = await MaliciousSiteProtectionIntegrationTests.dataManager()
        return MaliciousSiteProtectionManager(dataManager: dataManager, featureFlagger: MockFeatureFlagger(), updateIntervalProvider: { _ in nil })
    }

    var detector: MaliciousSiteDetecting!
    var contentBlockingMock: ContentBlockingMock!
    var privacyFeaturesMock: AnyPrivacyFeatures!
    var privacyConfiguration: MockPrivacyConfiguration {
        contentBlockingMock.privacyConfigurationManager.privacyConfig as! MockPrivacyConfiguration
    }
    var tab: Tab!
    var tabViewModel: TabViewModel!
    var schemeHandler: TestSchemeHandler!

    @MainActor
    override func setUp() async throws {
        detector = await Self.initDetectorTask.value

        WebTrackingProtectionPreferences.shared.isGPCEnabled = false
        MaliciousSiteProtectionPreferences.shared.isEnabled = true

        schemeHandler = TestSchemeHandler { request in
            if request.url!.lastPathComponent == "phishing.html" {
                XCTFail("Phishing request loaded")
            } else if request.url!.lastPathComponent == "malware.html" {
                XCTFail("Malware request loaded")
            }
            return .ok(.html(""))
        }

        let matchesUrlPrefix = MaliciousSiteDetector.APIEnvironment.production.url(for: .matches(.init(hashPrefix: "")), platform: .macOS)
            .absoluteString.prefix(while: { $0 != "?" })
        let hashPrefixUrlPrefix = MaliciousSiteDetector.APIEnvironment.production.url(for: .hashPrefixSet(.init(threatKind: .phishing, revision: nil)), platform: .macOS)
            .absoluteString.prefix(while: { $0 != "?" })
        let filterSetUrlPrefix = MaliciousSiteDetector.APIEnvironment.production.url(for: .filterSet(.init(threatKind: .phishing, revision: nil)), platform: .macOS)
            .absoluteString.prefix(while: { $0 != "?" })
        stub { request in
            let matches = request.url?.absoluteString.hasPrefix(matchesUrlPrefix) == true
            return matches
        } response: { _ in
            let path = OHPathForFile("match.api.response.json", type(of: self))!
            return fixture(filePath: path, status: 200, headers: nil)
        }
        stub { request in
            let matches = request.url?.absoluteString.hasPrefix(hashPrefixUrlPrefix) == true
            || request.url?.absoluteString.hasPrefix(filterSetUrlPrefix) == true
            return matches
        } response: { _ in
            return .init(data: Data(), statusCode: 200, headers: nil)
        }

        contentBlockingMock = ContentBlockingMock()
        privacyFeaturesMock = AppPrivacyFeatures(contentBlocking: contentBlockingMock, httpsUpgradeStore: HTTPSUpgradeStoreMock())
        // disable waiting for CBR compilation on navigation
        privacyConfiguration.isFeatureKeyEnabled = { feature, _ in
            if case .maliciousSiteProtection = feature { true } else { false }
        }

        tab = Tab(content: .none, webViewConfiguration: schemeHandler.webViewConfiguration(), privacyFeatures: privacyFeaturesMock, maliciousSiteDetector: detector)
        tabViewModel = TabViewModel(tab: tab)
        window = WindowsManager.openNewWindow(with: tab)!
        cancellables = Set<AnyCancellable>()
    }

    @MainActor
    override func tearDown() async throws {
        window.close()
        window = nil
        cancellables = nil
        detector = nil
        tab = nil
        tabViewModel = nil
        schemeHandler = nil
        HTTPStubs.removeAllStubs()
        WebTrackingProtectionPreferences.shared.isGPCEnabled = true
    }

    override class func tearDown() {
        initDetectorTask = nil
    }

    // MARK: - Phishing Detection Tests

    @MainActor
    func testPhishingNotDetected_tabIsNotMarkedPhishing() async throws {
        let url = URL(string: "http://privacy-test-pages.site/")!
        try await loadUrl(url)
        XCTAssertNil(tabViewModel.tab.error)
    }

    @MainActor
    func testPhishingDetected_tabIsMarkedPhishing() async throws {
        let url = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        try await loadUrl(url)
        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .phishing, failingUrl: url))
    }

    @MainActor
    func testFeatureDisabledAndPhishingDetection_tabIsNotMarkedPhishing() async throws {
        MaliciousSiteProtectionPreferences.shared.isEnabled = false
        let e = expectation(description: "request sent")
        schemeHandler.middleware = [{ _ in
            e.fulfill()
            return .ok(.html(""))
        }]
        let url = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        try await loadUrl(url)
        await fulfillment(of: [e], timeout: 1)
        XCTAssertNil(tabViewModel.tab.error)
    }

    @MainActor
    func testPhishingDetectedThenNotDetected_tabIsNotMarkedPhishing() async throws {
        let url1 = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        try await loadUrl(url1)
        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .phishing, failingUrl: url1))

        let url2 = URL(string: "http://broken.third-party.site/")!
        try await loadUrl(url2)
        XCTAssertNil(tabViewModel.tab.error)
    }

    @MainActor
    func testPhishingDetectedThenDDGLoaded_tabIsNotMarkedPhishing() async throws {
        let url1 = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!
        try await loadUrl(url1)
        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .phishing, failingUrl: url1))

        let url2 = URL(string: "http://duckduckgo.com/")!
        try await loadUrl(url2)
        let tabErrorCode2 = tabViewModel.tab.error?.errorCode
        XCTAssertNil(tabErrorCode2)
    }

    @MainActor
    func testPhishingDetectedViaHTTPRedirectChain_tabIsMarkedPhishing() async throws {
        let eRedirected = expectation(description: "Request redirected")
        let url = URL(string: "http://privacy-test-pages.site/security/badware/phishing-redirect/")!
        let redirectUrl = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!

        schemeHandler.middleware = [{
            if $0.url?.lastPathComponent == "phishing-redirect" {
                eRedirected.fulfill()
                return .redirect(to: "/security/badware/phishing.html")
            }
            XCTFail("\(self.name): Phishing request loaded")
            return nil
        }]
        try await loadUrl(url)
        await fulfillment(of: [eRedirected], timeout: 0)

        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .phishing, failingUrl: redirectUrl))
    }

    @MainActor
    func testPhishingDetectedViaJSRedirectChain_tabIsMarkedPhishing() async throws {
        let eRequested = expectation(description: "Request sent")
        let url = URL(string: "http://my-test-pages.site/security/badware/phishing-js-redirector.html")!
        let redirectUrl = URL(string: "http://privacy-test-pages.site/security/badware/phishing.html")!

        schemeHandler.middleware = [{
            if $0.url?.lastPathComponent == "phishing-js-redirector.html" {
                eRequested.fulfill()
                return .ok(.html("""
                <html>
                <head>
                    <script>
                        window.location = 'http://privacy-test-pages.site/security/badware/phishing.html';
                    </script>
                </head>
                </html>
                """))
            }
            XCTFail("\(self.name): Phishing request loaded for \($0.url!.absoluteString)")
            return nil
        }]
        try await loadUrl(url)
        await fulfillment(of: [eRequested], timeout: 0)
        try await wait { self.tab.error != nil }

        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .phishing, failingUrl: redirectUrl))
    }

    // MARK: - Malware Detection Tests

    @MainActor
    func testMalwareDetected_tabIsMarkedMalware() async throws {
        let url = URL(string: "http://privacy-test-pages.site/security/badware/malware.html")!
        try await loadUrl(url)
        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .malware, failingUrl: url))
    }

    @MainActor
    func testFeatureDisabledAndMalwareDetection_tabIsNotMarkedMalware() async throws {
        MaliciousSiteProtectionPreferences.shared.isEnabled = false
        let e = expectation(description: "request sent")
        schemeHandler.middleware = [{ _ in
            e.fulfill()
            return .ok(.html(""))
        }]
        let url = URL(string: "http://privacy-test-pages.site/security/badware/malware.html")!
        try await loadUrl(url)
        await fulfillment(of: [e], timeout: 1)
        XCTAssertNil(tabViewModel.tab.error)
    }

    @MainActor
    func testMalwareDetectedThenNotDetected_tabIsNotMarkedMalware() async throws {
        let url1 = URL(string: "http://privacy-test-pages.site/security/badware/malware.html")!
        try await loadUrl(url1)
        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .malware, failingUrl: url1))

        let url2 = URL(string: "http://broken.third-party.site/")!
        try await loadUrl(url2)
        XCTAssertNil(tabViewModel.tab.error)
    }

    @MainActor
    func testMalwareDetectedThenDDGLoaded_tabIsNotMarkedMalware() async throws {
        let url1 = URL(string: "http://privacy-test-pages.site/security/badware/malware.html")!
        try await loadUrl(url1)
        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .malware, failingUrl: url1))

        let url2 = URL(string: "http://duckduckgo.com/")!
        try await loadUrl(url2)
        let tabErrorCode2 = tabViewModel.tab.error?.errorCode
        XCTAssertNil(tabErrorCode2)
    }

    @MainActor
    func testMalwareDetectedViaHTTPRedirectChain_tabIsMarkedMalware() async throws {
        let eRedirected = expectation(description: "Request redirected")
        let url = URL(string: "http://privacy-test-pages.site/security/badware/malware-redirect/")!
        let redirectUrl = URL(string: "http://privacy-test-pages.site/security/badware/malware.html")!

        schemeHandler.middleware = [{
            if $0.url?.lastPathComponent == "malware-redirect" {
                eRedirected.fulfill()
                return .redirect(to: "/security/badware/malware.html")
            }
            XCTFail("\(self.name): Malware request loaded")
            return nil
        }]
        try await loadUrl(url)
        await fulfillment(of: [eRedirected], timeout: 0)

        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .malware, failingUrl: redirectUrl))
    }

    @MainActor
    func testMalwareDetectedViaJSRedirectChain_tabIsMarkedMalware() async throws {
        let eRequested = expectation(description: "Request sent")
        let url = URL(string: "http://my-test-pages.site/security/badware/malware-js-redirector.html")!
        let redirectUrl = URL(string: "http://privacy-test-pages.site/security/badware/malware.html")!

        schemeHandler.middleware = [{
            if $0.url?.lastPathComponent == "malware-js-redirector.html" {
                eRequested.fulfill()
                return .ok(.html("""
                <html>
                <head>
                    <script>
                        window.location = 'http://privacy-test-pages.site/security/badware/malware.html';
                    </script>
                </head>
                </html>
                """))
            }
            XCTFail("\(self.name): Malware request loaded for \($0.url!.absoluteString)")
            return nil
        }]
        try await loadUrl(url)
        await fulfillment(of: [eRequested], timeout: 0)
        try await wait { self.tab.error != nil }

        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .malware, failingUrl: redirectUrl))
    }

    // MARK: - Scam Detection Tests

    @MainActor
    func testScamDetected_tabIsMarkedScam() async throws {
        let url = URL(string: "http://privacy-test-pages.site/security/badware/scam.html")!
        try await loadUrl(url)
        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .scam, failingUrl: url))
    }

    @MainActor
    func testFeatureDisabledAndScamDetection_tabIsNotMarkedScam() async throws {
        MaliciousSiteProtectionPreferences.shared.isEnabled = false
        let e = expectation(description: "request sent")
        schemeHandler.middleware = [{ _ in
            e.fulfill()
            return .ok(.html(""))
        }]
        let url = URL(string: "http://privacy-test-pages.site/security/badware/scam.html")!
        try await loadUrl(url)
        await fulfillment(of: [e], timeout: 1)
        XCTAssertNotEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .scam, failingUrl: url))
    }

    @MainActor
    func testScamDetectedNotDetected_tabIsNotMarkedScam() async throws {
        let url1 = URL(string: "http://privacy-test-pages.site/security/badware/scam.html")!
        try await loadUrl(url1)
        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .scam, failingUrl: url1))

        let url2 = URL(string: "http://broken.third-party.site/")!
        try await loadUrl(url2)
        XCTAssertNil(tabViewModel.tab.error)
    }

    @MainActor
    func testScamDetectedThenDDGLoaded_tabIsNotMarkedScam() async throws {
        let url1 = URL(string: "http://privacy-test-pages.site/security/badware/scam.html")!
        try await loadUrl(url1)
        XCTAssertEqual(tabViewModel.tab.error as NSError? as? MaliciousSiteError, MaliciousSiteError(code: .scam, failingUrl: url1))

        let url2 = URL(string: "http://duckduckgo.com/")!
        try await loadUrl(url2)
        let tabErrorCode2 = tabViewModel.tab.error?.errorCode
        XCTAssertNil(tabErrorCode2)
    }

    // MARK: - Helper Methods

    @MainActor
    private func loadUrl(_ url: URL) async throws {
        tab.setUrl(url, source: .link)
        try await wait { !self.tab.isLoading }
    }

    @MainActor
    func wait(until condition: @escaping () -> Bool) async throws {
        let waiter = XCTWaiter()
        let loadingExpectation = expectation(description: "Tab finished loading")
        let task = Task {
            while !condition() {
                try Task.checkCancellation()
                await Task.yield()
            }
            loadingExpectation.fulfill()
        }
        defer { task.cancel() }

        let result = await waiter.fulfillment(of: [loadingExpectation], timeout: 2)

        switch result {
        case .completed: break
        case .timedOut: XCTFail("Test timed out")
        case .incorrectOrder, .invertedFulfillment, .interrupted: XCTFail("Test waiting failed")
        @unknown default: XCTFail("Unknown result")
        }
    }
}

class MockFeatureFlagger: FeatureFlagger {
    var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring())
    var localOverrides: FeatureFlagLocalOverriding?
    var isFeatureOn = true

    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        return isFeatureOn
    }

    func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        return nil
    }

    var allActiveExperiments: Experiments {
        return [:]
    }
}
