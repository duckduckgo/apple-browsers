//
//  ContentBlockerRulesUserScript.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import WebKit
import TrackerRadarKit
import Common
import UserScript
import ContentBlocking

public protocol ContentBlockerRulesUserScriptDelegate: NSObjectProtocol {

    func contentBlockerRulesUserScriptShouldProcessTrackers(_ script: ContentBlockerRulesUserScript) -> Bool
    func contentBlockerRulesUserScriptShouldProcessCTLTrackers(_ script: ContentBlockerRulesUserScript) -> Bool
    func contentBlockerRulesUserScript(_ script: ContentBlockerRulesUserScript,
                                       detectedTracker tracker: DetectedRequest)
    func contentBlockerRulesUserScript(_ script: ContentBlockerRulesUserScript,
                                       detectedThirdPartyRequest request: DetectedRequest)

}

public protocol ContentBlockerUserScriptConfig: UserScriptSourceProviding {

    var privacyConfiguration: PrivacyConfiguration { get }
    var trackerData: TrackerData? { get }
    var ctlTrackerData: TrackerData? { get }
    var tld: TLD { get }
}

public class DefaultContentBlockerUserScriptConfig: ContentBlockerUserScriptConfig {

    public let privacyConfiguration: PrivacyConfiguration
    public let trackerData: TrackerData?
    public let ctlTrackerData: TrackerData?
    public let tld: TLD

    public private(set) var source: String

    public init(privacyConfiguration: PrivacyConfiguration,
                trackerData: TrackerData?, // This should be non-optional
                ctlTrackerData: TrackerData?,
                tld: TLD,
                trackerDataManager: TrackerDataManager? = nil) {

        if trackerData == nil {
            // Fallback to embedded
            self.trackerData = trackerDataManager?.trackerData
        } else {
            self.trackerData = trackerData
        }

        self.privacyConfiguration = privacyConfiguration
        self.ctlTrackerData = ctlTrackerData
        self.tld = tld

        source = ContentBlockerRulesUserScript.generateSource(privacyConfiguration: privacyConfiguration)
    }

}

open class ContentBlockerRulesUserScript: NSObject, UserScript {

    struct ContentBlockerKey {
        static let url = "url"
        static let resourceType = "resourceType"
        static let blocked = "blocked"
        static let pageUrl = "pageUrl"
    }

    private let configuration: ContentBlockerUserScriptConfig

    public init(configuration: ContentBlockerUserScriptConfig) {
        self.configuration = configuration

        super.init()
    }

    public var source: String {
        return configuration.source
    }

    public var injectionTime: WKUserScriptInjectionTime = .atDocumentStart

    public var forMainFrameOnly: Bool = false

    public var messageNames: [String] = [ "processRule" ]

    public var supplementaryTrackerData = [TrackerData]()
    public var currentAdClickAttributionVendor: String?

    public weak var delegate: ContentBlockerRulesUserScriptDelegate?

    private var _temporaryUnprotectedDomainsCache = [String: [String]]()

    var temporaryUnprotectedDomains: [String] {
        if let domains = _temporaryUnprotectedDomainsCache[configuration.privacyConfiguration.identifier] {
            return domains
        }

        let privacyConfiguration = configuration.privacyConfiguration
        var temporaryUnprotectedDomains = privacyConfiguration.tempUnprotectedDomains.filter { !$0.trimmingWhitespace().isEmpty }
        temporaryUnprotectedDomains.append(contentsOf: privacyConfiguration.exceptionsList(forFeature: .contentBlocking))
        _temporaryUnprotectedDomainsCache = [configuration.privacyConfiguration.identifier: temporaryUnprotectedDomains]
        return temporaryUnprotectedDomains
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let delegate = delegate else { return }
        guard delegate.contentBlockerRulesUserScriptShouldProcessTrackers(self) else { return }
        let ctlEnabled = delegate.contentBlockerRulesUserScriptShouldProcessCTLTrackers(self)

        guard let dict = message.body as? [String: Any] else { return }

        // False if domain is in unprotected list
        guard let blocked = dict[ContentBlockerKey.blocked] as? Bool else { return }
        guard let trackerUrlString = dict[ContentBlockerKey.url] as? String else { return }
        let resourceType = (dict[ContentBlockerKey.resourceType] as? String) ?? "unknown"
        guard let pageUrlStr = dict[ContentBlockerKey.pageUrl] as? String else { return }

        guard let currentTrackerData = configuration.trackerData else {
            return
        }

        let privacyConfiguration = configuration.privacyConfiguration

        var additionalTDSSets = supplementaryTrackerData

        if ctlEnabled, let ctlTrackerData = configuration.ctlTrackerData {
            additionalTDSSets.append(ctlTrackerData)
        }

        var detectedTracker: DetectedRequest?

        for trackerData in additionalTDSSets {
            let resolver = TrackerResolver(tds: trackerData,
                                           unprotectedSites: privacyConfiguration.userUnprotectedDomains,
                                           tempList: temporaryUnprotectedDomains,
                                           tld: configuration.tld,
                                           adClickAttributionVendor: currentAdClickAttributionVendor)

            if let tracker = resolver.trackerFromUrl(trackerUrlString,
                                                     pageUrlString: pageUrlStr,
                                                     resourceType: resourceType,
                                                     potentiallyBlocked: blocked && privacyConfiguration.isEnabled(featureKey: .contentBlocking)) {
                if tracker.isBlocked {
                    guard !isFirstParty(requestURL: tracker.url, websiteURL: pageUrlStr) else { return }
                    delegate.contentBlockerRulesUserScript(self, detectedTracker: tracker)
                    return
                } else {
                    detectedTracker = tracker
                }
            }
        }

        let resolver = TrackerResolver(tds: currentTrackerData,
                                       unprotectedSites: privacyConfiguration.userUnprotectedDomains,
                                       tempList: temporaryUnprotectedDomains,
                                       tld: configuration.tld)

        if let tracker = resolver.trackerFromUrl(trackerUrlString,
                                                 pageUrlString: pageUrlStr,
                                                 resourceType: resourceType,
                                                 potentiallyBlocked: blocked && privacyConfiguration.isEnabled(featureKey: .contentBlocking)) {
            detectedTracker = tracker
        }

        if let tracker = detectedTracker {
            guard !isFirstParty(requestURL: tracker.url, websiteURL: pageUrlStr) else { return }
            delegate.contentBlockerRulesUserScript(self, detectedTracker: tracker)
        } else {
            guard let requestETLDp1 = configuration.tld.eTLDplus1(forStringURL: trackerUrlString),
                  !isFirstParty(requestURL: trackerUrlString, websiteURL: pageUrlStr) else { return }

            let entity = currentTrackerData.findEntity(forHost: requestETLDp1) ?? Entity(displayName: requestETLDp1, domains: nil, prevalence: nil)
            let isAffiliated = resolver.isPageAffiliatedWithTrackerEntity(pageUrlString: pageUrlStr, trackerEntity: entity)

            let thirdPartyRequest = DetectedRequest(url: trackerUrlString,
                                                    eTLDplus1: requestETLDp1,
                                                    knownTracker: nil,
                                                    entity: entity,
                                                    state: .allowed(reason: isAffiliated ? .ownedByFirstParty : .otherThirdPartyRequest),
                                                    pageUrl: pageUrlStr)
            delegate.contentBlockerRulesUserScript(self, detectedThirdPartyRequest: thirdPartyRequest)
        }
    }

    private func isFirstParty(requestURL: String, websiteURL: String) -> Bool {
        guard let requestDomain = configuration.tld.eTLDplus1(forStringURL: requestURL),
              let websiteDomain = configuration.tld.eTLDplus1(forStringURL: websiteURL)
        else { return false }

        return requestDomain == websiteDomain
    }

    public static func generateSource(privacyConfiguration: PrivacyConfiguration) -> String {
        let remoteUnprotectedDomains = (privacyConfiguration.tempUnprotectedDomains.joined(separator: "\n"))
            + "\n"
            + (privacyConfiguration.exceptionsList(forFeature: .contentBlocking).joined(separator: "\n"))

        return ContentBlockerRulesUserScript.loadJS("contentblockerrules", from: Bundle.module, withReplacements: [
            "$TEMP_UNPROTECTED_DOMAINS$": remoteUnprotectedDomains,
            "$USER_UNPROTECTED_DOMAINS$": privacyConfiguration.userUnprotectedDomains.joined(separator: "\n"),
            "$TRACKER_ALLOWLIST_ENTRIES$": TrackerAllowlistInjection.prepareForInjection(allowlist: privacyConfiguration.trackerAllowlist.entries)
        ])
    }
}

public class TrackerAllowlistInjection {

    static public func prepareForInjection(allowlist: PrivacyConfigurationData.TrackerAllowlistData) -> String {
        // Transform rules into regular expresions
        var output = PrivacyConfigurationData.TrackerAllowlistData()
        for dictEntry in allowlist {
            let newValue = dictEntry.value.map { entry -> PrivacyConfigurationData.TrackerAllowlist.Entry in
                let regexp = ContentBlockerRulesBuilder.makeRegexpFilter(fromAllowlistRule: entry.rule)
                let escapedRegexp = regexp.replacingOccurrences(of: "\\", with: "\\\\")
                return PrivacyConfigurationData.TrackerAllowlist.Entry(rule: escapedRegexp, domains: entry.domains)
            }
            output[dictEntry.key] = newValue
        }

        return (try? String(data: JSONEncoder().encode(output), encoding: .utf8)) ?? ""
    }

}
