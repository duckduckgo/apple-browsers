//
//  LegacyUserScriptTestHelpers.swift
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

// Test helpers for the legacy `ContentBlockerRulesUserScript` and
// `SurrogatesUserScript` pipelines. Retained alongside the new
// `TrackerProtectionSubfeature` test scaffolding until the legacy userscripts
// (and their reference/unit tests) are removed in the cleanup commit, at which
// point this file is deleted in one go.

import BrowserServicesKit
import Common
import ContentBlocking
import Foundation
import PrivacyConfig
import PrivacyConfigTestsUtils
import TrackerRadarKit
import WebKit
import XCTest

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

final class TestSchemeContentBlockerUserScriptConfig: ContentBlockerUserScriptConfig {

    public let privacyConfiguration: PrivacyConfiguration
    public let trackerData: TrackerData?
    public let ctlTrackerData: TrackerData?
    public let tld: TLD

    public private(set) var source: String

    public init(privacyConfiguration: PrivacyConfiguration,
                trackerData: TrackerData?,
                ctlTrackerData: TrackerData?,
                tld: TLD) throws {
        self.privacyConfiguration = privacyConfiguration
        self.trackerData = trackerData
        self.ctlTrackerData = ctlTrackerData
        self.tld = tld

        // UserScripts contain TrackerAllowlist rules in form of regular expressions - we need to ensure test scheme is matched instead of http/https
        let orginalSource = try ContentBlockerRulesUserScript.generateSource(privacyConfiguration: privacyConfiguration)
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
                isDebugBuild: Bool) throws {

        self.privacyConfig = privacyConfig
        self.surrogates = surrogates
        self.trackerData = trackerData
        self.encodedSurrogateTrackerData = encodedSurrogateTrackerData
        self.tld = tld

        // UserScripts contain TrackerAllowlist rules in form of regular expressions - we need to ensure test scheme is matched instead of http/https
        let orginalSource = try SurrogatesUserScript.generateSource(privacyConfiguration: privacyConfig,
                                                                surrogates: surrogates,
                                                                encodedSurrogateTrackerData: encodedSurrogateTrackerData,
                                                                isDebugBuild: isDebugBuild)

        source = orginalSource.replacingOccurrences(of: "http", with: "test")
    }
}
