//
//  WebViewTestHelper.swift
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

import Foundation
import WebKit
import XCTest
import BrowserServicesKit
import TrackerRadarKit
import ContentBlocking
import Common

final class MockNavigationDelegate: NSObject, WKNavigationDelegate {

    var onDidFinishNavigation: (() -> Void)?

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        XCTFail("Could to navigate to test site")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onDidFinishNavigation?()
    }
}

final class MockRulesUserScriptDelegate: NSObject, ContentBlockerRulesUserScriptDelegate {

    var shouldProcessTrackers = true
    var shouldProcessCTLTrackers = true
    var onTrackerDetected: ((DetectedRequest) -> Void)?
    var detectedTrackers = Set<DetectedRequest>()
    var onThirdPartyRequestDetected: ((DetectedRequest) -> Void)?
    var detectedThirdPartyRequests = Set<DetectedRequest>()

    func reset() {
        detectedTrackers.removeAll()
    }

    func contentBlockerRulesUserScriptShouldProcessTrackers(_ script: ContentBlockerRulesUserScript) -> Bool {
        return shouldProcessTrackers
    }

    func contentBlockerRulesUserScriptShouldProcessCTLTrackers(_ script: ContentBlockerRulesUserScript) -> Bool {
        return shouldProcessCTLTrackers
    }

    func contentBlockerRulesUserScript(_ script: ContentBlockerRulesUserScript,
                                       detectedTracker tracker: DetectedRequest) {
        detectedTrackers.insert(tracker)
        onTrackerDetected?(tracker)
    }

    func contentBlockerRulesUserScript(_ script: ContentBlockerRulesUserScript,
                                       detectedThirdPartyRequest request: DetectedRequest) {
        detectedThirdPartyRequests.insert(request)
        onThirdPartyRequestDetected?(request)
    }
}

final class MockSurrogatesUserScriptDelegate: NSObject, SurrogatesUserScriptDelegate {

    var shouldProcessTrackers = true
    var shouldProcessCTLTrackers = false

    var onSurrogateDetected: ((DetectedRequest, String) -> Void)?
    var detectedSurrogates = Set<DetectedRequest>()

    func reset() {
        detectedSurrogates.removeAll()
    }

    func surrogatesUserScriptShouldProcessTrackers(_ script: SurrogatesUserScript) -> Bool {
        return shouldProcessTrackers
    }

    func surrogatesUserScriptShouldProcessCTLTrackers(_ script: SurrogatesUserScript) -> Bool {
        shouldProcessCTLTrackers
    }

    func surrogatesUserScript(_ script: SurrogatesUserScript,
                              detectedTracker tracker: DetectedRequest,
                              withSurrogate host: String) {
        detectedSurrogates.insert(tracker)
        onSurrogateDetected?(tracker, host)
    }
}

final class MockDomainsProtectionStore: DomainsProtectionStore {
    var unprotectedDomains = Set<String>()

    func disableProtection(forDomain domain: String) {
        unprotectedDomains.insert(domain)
    }

    func enableProtection(forDomain domain: String) {
        unprotectedDomains.remove(domain)
    }
}

final class TestSchemeContentBlockerUserScriptConfig: ContentBlockerUserScriptConfig {

    public let privacyConfiguration: PrivacyConfiguration
    public let trackerData: TrackerData?
    public let ctlTrackerData: TrackerData?
    public let tld: TLD

    public private(set) var source: String

    public init(privacyConfiguration: PrivacyConfiguration,
                trackerData: TrackerData?,
                ctlTrackerData: TrackerData?,
                tld: TLD) {
        self.privacyConfiguration = privacyConfiguration
        self.trackerData = trackerData
        self.ctlTrackerData = ctlTrackerData
        self.tld = tld

        // UserScripts contain TrackerAllowlist rules in form of regular expressions - we need to ensure test scheme is matched instead of http/https
        let orginalSource = ContentBlockerRulesUserScript.generateSource(privacyConfiguration: privacyConfiguration)
        source = orginalSource.replacingOccurrences(of: "http", with: "test")
    }
}

public class TestSchemeSurrogatesUserScriptConfig: SurrogatesUserScriptConfig {

    public let privacyConfig: PrivacyConfiguration
    public let surrogates: String
    public let trackerData: TrackerData?
    public let encodedSurrogateTrackerData: String?
    public let tld: TLD

    public let source: String

    public init(privacyConfig: PrivacyConfiguration,
                surrogates: String,
                trackerData: TrackerData?,
                encodedSurrogateTrackerData: String?,
                tld: TLD,
                isDebugBuild: Bool) {

        self.privacyConfig = privacyConfig
        self.surrogates = surrogates
        self.trackerData = trackerData
        self.encodedSurrogateTrackerData = encodedSurrogateTrackerData
        self.tld = tld

        // UserScripts contain TrackerAllowlist rules in form of regular expressions - we need to ensure test scheme is matched instead of http/https
        let orginalSource = SurrogatesUserScript.generateSource(privacyConfiguration: privacyConfig,
                                                                surrogates: surrogates,
                                                                encodedSurrogateTrackerData: encodedSurrogateTrackerData,
                                                                isDebugBuild: isDebugBuild)

        source = orginalSource.replacingOccurrences(of: "http", with: "test")
    }
}

final class WebKitTestHelper {

    static func preparePrivacyConfig(locallyUnprotected: [String],
                                     tempUnprotected: [String],
                                     trackerAllowlist: [String: [PrivacyConfigurationData.TrackerAllowlist.Entry]],
                                     contentBlockingEnabled: Bool,
                                     exceptions: [String],
                                     httpsUpgradesEnabled: Bool = false,
                                     clickToLoadEnabled: Bool = true) -> PrivacyConfiguration {
        let contentBlockingExceptions = exceptions.map { PrivacyConfigurationData.ExceptionEntry(domain: $0, reason: nil) }
        let contentBlockingStatus = contentBlockingEnabled ? "enabled" : "disabled"
        let httpsStatus = httpsUpgradesEnabled ? "enabled" : "disabled"
        let clickToLoadStatus = clickToLoadEnabled ? "enabled" : "disabled"
        let features = [PrivacyFeature.contentBlocking.rawValue: PrivacyConfigurationData.PrivacyFeature(state: contentBlockingStatus,
                                                                                                         exceptions: contentBlockingExceptions),
                        PrivacyFeature.httpsUpgrade.rawValue: PrivacyConfigurationData.PrivacyFeature(state: httpsStatus, exceptions: []),
                        PrivacyFeature.clickToLoad.rawValue: PrivacyConfigurationData.PrivacyFeature(state: clickToLoadStatus,
                                                                                                         exceptions: contentBlockingExceptions)]
        let unprotectedTemporary = tempUnprotected.map { PrivacyConfigurationData.ExceptionEntry(domain: $0, reason: nil) }
        let privacyData = PrivacyConfigurationData(features: features,
                                                   unprotectedTemporary: unprotectedTemporary,
                                                   trackerAllowlist: trackerAllowlist)

        let localProtection = MockDomainsProtectionStore()
        localProtection.unprotectedDomains = Set(locallyUnprotected)

        return AppPrivacyConfiguration(data: privacyData,
                                       identifier: "",
                                       localProtection: localProtection,
                                       internalUserDecider: MockInternalUserDecider())
    }

    static func prepareContentBlockingRules(trackerData: TrackerData,
                                            exceptions: [String],
                                            tempUnprotected: [String],
                                            trackerExceptions: [TrackerException],
                                            identifier: String = "test",
                                            completion: @escaping (WKContentRuleList?) -> Void) {

        let rules = ContentBlockerRulesBuilder(trackerData: trackerData).buildRules(withExceptions: exceptions,
                                                                                    andTemporaryUnprotectedDomains: tempUnprotected,
                                                                                    andTrackerAllowlist: trackerExceptions)

        let data = (try? JSONEncoder().encode(rules))!
        var ruleList = String(data: data, encoding: .utf8)!

        // Replace https scheme regexp with test
        ruleList = ruleList.replacingOccurrences(of: "https", with: "test", options: [], range: nil)

        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: ruleList) { list, _ in

            DispatchQueue.main.async {
                completion(list)
            }
        }
    }
}

class MockExperimentCohortsManager: ExperimentCohortsManaging {
    func resolveCohort(for experiment: ExperimentSubfeature, allowCohortAssignment: Bool) -> CohortID? {
        return nil
    }

    var experiments: Experiments?
}
