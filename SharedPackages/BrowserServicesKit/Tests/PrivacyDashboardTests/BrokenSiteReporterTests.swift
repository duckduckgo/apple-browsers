//
//  BrokenSiteReporterTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import XCTest
import DDGNavigation
@testable import PrivacyDashboard
@_spi(Testing) import Persistence

final class BrokenSiteReporterTests: XCTestCase {

    func testReport() throws {

        let expctation1 = expectation(description: "Pixel sent without lastSentDay")
        let expctation2 = expectation(description: "Pixel sent with lastSentDay ")
        var pixelCount = 0

        let keyValueStore = MockKeyValueStore()
        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            // Send pixel
            print("PIXEL SENT: \n\(parameters)")
            pixelCount += 1

            if pixelCount == 1, parameters["lastSentDay"] == nil {
                expctation1.fulfill()
            } else if pixelCount == 2, parameters["lastSentDay"] != nil {
                expctation2.fulfill()
            }
        }, keyValueStoring: keyValueStore)

        try reporter.report(BrokenSiteReportMocks.report, reportMode: .regular)

        // test second report, the pixel must have `lastSeenDate` param
        try reporter.report(BrokenSiteReportMocks.report, reportMode: .regular)

        waitForExpectations(timeout: 3)
    }

    func testReportContainsExperimentData() throws {
        let keyValueStore = MockKeyValueStore()
        let expectation = expectation(description: "Pixel sent")
        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            XCTAssertTrue(parameters["contentScopeExperiments"]!.contains("experiment1:control"))
            XCTAssertTrue(parameters["contentScopeExperiments"]!.contains("experiment2:treatment"))
            print(parameters)
            expectation.fulfill()
        }, keyValueStoring: keyValueStore)

        try reporter.report(BrokenSiteReportMocks.report, reportMode: .regular)

        waitForExpectations(timeout: 3)
    }

    func testWhenBreakageDataPresentThenItIsIncludedInParameters() throws {
        let keyValueStore = MockKeyValueStore()
        let expectation = expectation(description: "Pixel sent")

        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            XCTAssertNotNil(parameters["breakageData"])
            XCTAssertTrue(parameters["breakageData"]!.contains("webDetection"))
            expectation.fulfill()
        }, keyValueStoring: keyValueStore)

        try reporter.report(BrokenSiteReportMocks.reportWithBreakageData, reportMode: .regular)
        waitForExpectations(timeout: 3)
    }

    func testWhenBreakageDataAbsentThenItIsNotIncludedInParameters() throws {
        let keyValueStore = MockKeyValueStore()
        let expectation = expectation(description: "Pixel sent")

        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            XCTAssertNil(parameters["breakageData"])
            expectation.fulfill()
        }, keyValueStoring: keyValueStore)

        try reporter.report(BrokenSiteReportMocks.report, reportMode: .regular)
        waitForExpectations(timeout: 3)
    }

    func testWhenWebExtensionFieldsProvidedThenTheyAreIncluded() throws {
        let keyValueStore = MockKeyValueStore()
        let expectation = expectation(description: "Pixel sent")

        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            XCTAssertEqual(parameters["loadedWebExtensions"], "embedded,adBlocking")
            XCTAssertEqual(parameters["adBlockingExtensionScriptletsVersion"], "2.0.0")
            expectation.fulfill()
        }, keyValueStoring: keyValueStore)

        try reporter.report(BrokenSiteReportMocks.reportWithWebExtensions, reportMode: .regular)
        waitForExpectations(timeout: 3)
    }

    func testWhenWebExtensionFieldsAbsentThenTheyAreNotIncluded() throws {
        let keyValueStore = MockKeyValueStore()
        let expectation = expectation(description: "Pixel sent")

        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            XCTAssertNil(parameters["loadedWebExtensions"])
            XCTAssertNil(parameters["adBlockingExtensionScriptletsVersion"])
            expectation.fulfill()
        }, keyValueStoring: keyValueStore)

        try reporter.report(BrokenSiteReportMocks.report, reportMode: .regular)
        waitForExpectations(timeout: 3)
    }

    func testWhenCPMDiagnosticsPresentThenTheyAreIncluded() throws {
        let keyValueStore = MockKeyValueStore()
        let expectation = expectation(description: "Pixel sent")

        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            XCTAssertEqual(parameters["cpmExtensionDroppedCallbacks"], "3")
            XCTAssertEqual(parameters["cpmExtensionLoaded"], "1")
            XCTAssertEqual(parameters["cpmDashboardState"], "applied")
            XCTAssertEqual(parameters["cpmStage"], "popup_found")
            XCTAssertEqual(parameters["cpmErrors"], "multiple_cmps,tab_refreshDashboardState")
            XCTAssertEqual(parameters["cpmQueueSize"], "2")
            XCTAssertEqual(parameters["cpmConfigVersion"], "123")
            expectation.fulfill()
        }, keyValueStoring: keyValueStore)

        try reporter.report(makeReport(cookieConsentInfo: CookieConsentInfo(
            consentManaged: true,
            cosmetic: true,
            optoutFailed: false,
            selftestFailed: false,
            consentReloadLoop: false,
            consentRule: "test-cmp",
            consentHeuristicEnabled: true,
            cpmExtensionDroppedCallbacks: 3,
            cpmExtensionLoaded: true,
            cpmDashboardState: .applied,
            cpmStage: .popupFound,
            cpmErrors: "multiple_cmps,tab_refreshDashboardState",
            cpmQueueSize: 2,
            cpmConfigVersion: "123")), reportMode: .regular)
        waitForExpectations(timeout: 3)
    }

    func testWhenCPMDiagnosticsAbsentThenEmptyValuesAreIncluded() throws {
        let keyValueStore = MockKeyValueStore()
        let expectation = expectation(description: "Pixel sent")

        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            XCTAssertEqual(parameters["cpmExtensionDroppedCallbacks"], "")
            XCTAssertEqual(parameters["cpmExtensionLoaded"], "")
            XCTAssertEqual(parameters["cpmDashboardState"], "")
            XCTAssertEqual(parameters["cpmStage"], "")
            XCTAssertEqual(parameters["cpmErrors"], "")
            XCTAssertEqual(parameters["cpmQueueSize"], "")
            XCTAssertEqual(parameters["cpmConfigVersion"], "")
            expectation.fulfill()
        }, keyValueStoring: keyValueStore)

        try reporter.report(makeReport(cookieConsentInfo: nil), reportMode: .regular)
        waitForExpectations(timeout: 3)
    }

    func testWhenReportFlowIsErrorPageThenParameterIsErrorPage() {
        let report = makeReport(cookieConsentInfo: nil, reportFlow: .errorPage)

        XCTAssertEqual(report.requestParameters["reportFlow"], "error_page")
    }

    func testWhenReportIsAfterTabTerminationThenParameterIsIncluded() {
        let report = makeReport(cookieConsentInfo: nil, isAfterTabTermination: true)

        XCTAssertEqual(report.requestParameters["isAfterTabTermination"], "true")
    }

    func testWhenReportIsNotAfterTabTerminationThenParameterIsNotIncluded() {
        let report = makeReport(cookieConsentInfo: nil)

        XCTAssertNil(report.requestParameters["isAfterTabTermination"])
    }

    func testWhenSignalsArePresentThenTheyAreIncluded() {
        let networkSignals = NetworkSignals(isNetworkAvailable: true, networkType: .wifi, isLowDataModeEnabled: true, hasVPNConnectivityIssues: false, pingQuality: .poor)
        let pageSignals = PageSignals(resourceFailures: ["b.com": [.statusCode(500)], "a.com": [Self.dnsError, Self.certificateError]],
                                      blockedDomains: ["x.com": 1, "z.com": 5, "y.com": 1],
                                      blockedLoads: 7)

        let parameters = makeReport(cookieConsentInfo: nil,
                                    networkSignals: networkSignals,
                                    dnsResolution: .blocked,
                                    memoryPressure: .warning,
                                    pageSignals: pageSignals).requestParameters

        XCTAssertEqual(parameters["isNetworkAvailable"], "true")
        XCTAssertEqual(parameters["networkType"], "wifi")
        XCTAssertEqual(parameters["isLowDataModeEnabled"], "true")
        XCTAssertEqual(parameters["hasVPNConnectivityIssues"], "false")
        XCTAssertEqual(parameters["networkPingQuality"], "poor")
        XCTAssertEqual(parameters["dnsResolution"], "blocked")
        XCTAssertEqual(parameters["memoryPressure"], "warning")
        XCTAssertEqual(parameters["resourceLoadErrors"], "a.com:(NSURLErrorDomain,-1003),a.com:(NSURLErrorDomain,-1202),b.com:(statusCode,500)")
        XCTAssertEqual(parameters["contentBlockedLoads"], "7")
        XCTAssertEqual(parameters["contentBlockedDomains"], "z.com:5,x.com:1,y.com:1")
    }

    func testWhenSignalsAreAbsentThenTheyAreNotIncluded() {
        let parameters = makeReport(cookieConsentInfo: nil).requestParameters
        let keys = ["isNetworkAvailable", "networkType", "isLowDataModeEnabled", "hasVPNConnectivityIssues", "networkPingQuality", "dnsResolution",
                    "memoryPressure", "resourceLoadErrors", "contentBlockedLoads", "contentBlockedDomains"]

        for key in keys {
            XCTAssertNil(parameters[key], key)
        }
    }

    func testWhenPageSignalsExceedMaxEntriesThenListsAreCapped() {
        let pageSignals = PageSignals(resourceFailures: ["a.com": [Self.dnsError, .statusCode(500)], "b.com": [.statusCode(404)]],
                                      blockedDomains: ["a.com": 1, "y.com": 2, "x.com": 3],
                                      blockedLoads: 6)

        let parameters = makeReport(cookieConsentInfo: nil, pageSignals: pageSignals, pageSignalsEntryLimit: 2).requestParameters

        XCTAssertEqual(parameters["resourceLoadErrors"], "a.com:(NSURLErrorDomain,-1003),a.com:(statusCode,500)")
        XCTAssertEqual(parameters["contentBlockedDomains"], "x.com:3,y.com:2")
        XCTAssertEqual(parameters["contentBlockedLoads"], "6")
    }

    private static let dnsError = PageResourceLoadError.error(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost))
    private static let certificateError = PageResourceLoadError.error(NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted))

    private func makeReport(cookieConsentInfo: CookieConsentInfo?,
                            reportFlow: BrokenSiteReport.Source = .appMenu,
                            isAfterTabTermination: Bool = false,
                            networkSignals: NetworkSignals? = nil,
                            dnsResolution: DNSResolution? = nil,
                            memoryPressure: MemoryPressureLevel? = nil,
                            pageSignals: PageSignals? = nil,
                            pageSignalsEntryLimit: Int = PageSignalsSettings.defaultMaxEntries) -> BrokenSiteReport {
#if os(iOS)
        BrokenSiteReport(siteUrl: URL(string: "https://duckduckgo.com")!,
                         category: "test",
                         description: "test",
                         osVersion: "test",
                         manufacturer: "Apple",
                         upgradedHttps: true,
                         tdsETag: "test",
                         configVersion: "123456789",
                         blockedTrackerDomains: [],
                         installedSurrogates: [],
                         isGPCEnabled: true,
                         ampURL: "test",
                         urlParametersRemoved: true,
                         protectionsState: true,
                         reportFlow: reportFlow,
                         siteType: .desktop,
                         model: "test",
                         errors: nil,
                         httpStatusCodes: nil,
                         openerContext: nil,
                         vpnOn: false,
                         jsPerformance: nil,
                         userRefreshCount: 0,
                         variant: "",
                         cookieConsentInfo: cookieConsentInfo,
                         debugFlags: "",
                         privacyExperiments: "experiment1:control,experiment2:treatment",
                         isPirEnabled: nil,
                         isForceDarkModeEnabled: nil,
                         isAfterTabTermination: isAfterTabTermination,
                         networkSignals: networkSignals,
                         dnsResolution: dnsResolution,
                         memoryPressure: memoryPressure,
                         pageSignals: pageSignals,
                         pageSignalsEntryLimit: pageSignalsEntryLimit)
#else
        BrokenSiteReport(siteUrl: URL(string: "https://duckduckgo.com")!,
                         category: "test",
                         description: "test",
                         osVersion: "test",
                         manufacturer: "Apple",
                         upgradedHttps: true,
                         tdsETag: "test",
                         configVersion: "123456789",
                         blockedTrackerDomains: [],
                         installedSurrogates: [],
                         isGPCEnabled: true,
                         ampURL: "test",
                         urlParametersRemoved: true,
                         protectionsState: true,
                         reportFlow: reportFlow,
                         errors: nil,
                         httpStatusCodes: nil,
                         openerContext: nil,
                         vpnOn: false,
                         jsPerformance: nil,
                         userRefreshCount: 0,
                         cookieConsentInfo: cookieConsentInfo,
                         debugFlags: "",
                         privacyExperiments: "experiment1:control,experiment2:treatment",
                         isPirEnabled: nil,
                         isForceDarkModeEnabled: nil,
                         isAfterTabTermination: isAfterTabTermination,
                         lastTabSuspension: nil,
                         pageLoadTiming: nil,
                         networkSignals: networkSignals,
                         dnsResolution: dnsResolution,
                         memoryPressure: memoryPressure,
                         pageSignals: pageSignals,
                         pageSignalsEntryLimit: pageSignalsEntryLimit)
#endif
    }
}
