//
//  TrackerProtectionEventMapperTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import BrowserServicesKit
import Common
import ContentBlocking
import PrivacyConfig
import TrackerRadarKit

final class TrackerProtectionEventMapperTests: XCTestCase {

    private let tld = TLD()

    private func makeTestTDS() -> TrackerData {
        let tracker = KnownTracker(
            domain: "tracker.com",
            defaultAction: .block,
            owner: KnownTracker.Owner(name: "Tracker Inc", displayName: "Tracker Inc", ownedBy: nil),
            prevalence: 0.1,
            subdomains: nil,
            categories: ["Analytics"],
            rules: nil)

        let entity = Entity(displayName: "Tracker Inc", domains: ["tracker.com"], prevalence: 0.1)

        return TrackerData(
            trackers: ["tracker.com": tracker],
            entities: ["Tracker Inc": entity],
            domains: ["tracker.com": "Tracker Inc"],
            cnames: nil)
    }

    private func makeMapper(
        trackerData: TrackerData? = nil,
        unprotectedSites: [String] = [],
        tempList: [String] = [],
        trackerAllowlist: PrivacyConfigurationData.TrackerAllowlistData = [:]
    ) -> TrackerProtectionEventMapper {
        TrackerProtectionEventMapper(tld: tld,
                                     mainTrackerData: trackerData ?? makeTestTDS(),
                                     unprotectedSites: unprotectedSites,
                                     tempList: tempList,
                                     contentBlockingEnabled: true,
                                     trackerAllowlist: trackerAllowlist)
    }

    private func classify(
        mapper: TrackerProtectionEventMapper,
        url: String,
        pageUrl: String
    ) -> DetectedRequest? {
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: url, resourceType: "script", potentiallyBlocked: true, pageUrl: pageUrl)
        return mapper.classifyResource(observation)
    }

    // MARK: - ResourceObservation Classification

    func testWhenTrackerUrlIsObservedThenClassifyReturnsDetectedRequest() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")

        let result = mapper.classifyResource(observation)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.url, "https://tracker.com/pixel.js")
    }

    func testWhenNonTrackerUrlIsObservedThenClassifyReturnsNil() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://not-a-tracker.com/script.js",
            resourceType: "script",
            potentiallyBlocked: false,
            pageUrl: "https://example.com")

        let result = mapper.classifyResource(observation)
        XCTAssertNil(result)
    }

    func testWhenFirstPartyTrackerIsObservedThenItIsSuppressed() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://tracker.com")

        let result = mapper.classifyResource(observation)
        XCTAssertNil(result, "Same-site known trackers must be suppressed — content rules only block third-party loads")
    }

    // MARK: - SurrogateInjection Classification

    func testWhenSurrogateInjectionIsReceivedThenClassifyReturnsDetectedRequest() {
        let mapper = makeMapper()
        let surrogate = TrackerProtectionSubfeature.SurrogateInjection(
            url: "https://tracker.com/analytics.js",
            pageUrl: "https://example.com",
            surrogateName: "analytics.js")

        let result = mapper.classifySurrogate(surrogate)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.url, "https://tracker.com/analytics.js")
    }

    func testWhenSurrogateHostIsExtractedThenItMatchesUrl() {
        let mapper = makeMapper()
        let surrogate = TrackerProtectionSubfeature.SurrogateInjection(
            url: "https://tracker.com/analytics.js",
            pageUrl: "https://example.com",
            surrogateName: "analytics.js")

        XCTAssertEqual(mapper.surrogateHost(from: surrogate), "tracker.com")
    }

    // MARK: - Same-Site Detection

    func testWhenObservationIsSameSiteThenIsSameSiteReturnsTrue() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://cdn.example.com/script.js",
            resourceType: "script",
            potentiallyBlocked: false,
            pageUrl: "https://example.com")

        XCTAssertTrue(mapper.isSameSiteObservation(observation))
    }

    func testWhenObservationIsCrossSiteThenIsSameSiteReturnsFalse() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")

        XCTAssertFalse(mapper.isSameSiteObservation(observation))
    }

    // MARK: - Native Allowlist Override

    func testAllowlistedTrackerIsNotBlocked() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["example.com"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://example.com")

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked, "Allowlisted tracker must not be blocked")
        if case .allowed(reason: .ruleException) = result?.state {} else {
            XCTFail("Expected .allowed(reason: .ruleException), got \(String(describing: result?.state))")
        }
    }

    func testNonAllowlistedBlockedTrackerRemainsBlocked() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["example.com"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)
        let result = classify(mapper: mapper, url: "https://tracker.com/other.js", pageUrl: "https://example.com")

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked, "Non-allowlisted tracker must remain blocked")
    }

    func testAllowlistMatchStripsPortBeforeRegex() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["<all>"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)
        let result = classify(mapper: mapper, url: "https://tracker.com:8080/pixel.js", pageUrl: "https://example.com")

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked, "Port must be stripped before allowlist regex matching")
    }

    func testAllowlistMatchStripsQueryStringBeforeRegex() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["<all>"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js?v=1&uid=abc", pageUrl: "https://example.com")

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked, "Query string must be stripped before allowlist regex matching")
    }

    func testAllowlistMatchStripsSemicolonParametersBeforeRegex() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["<all>"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js;session=xyz&a=1", pageUrl: "https://example.com")

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked, "Semicolon parameters must be stripped before allowlist regex matching")
    }

    func testAllowlistPageDomainMatchesSubdomains() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["example.com"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)

        let fromSubdomain = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://a.b.c.example.com")
        XCTAssertNotNil(fromSubdomain)
        XCTAssertFalse(fromSubdomain!.isBlocked,
                        "Allowlist must match subdomains of the listed page domain")
    }

    func testAllowlistDoesNotMatchUnlistedPageDomain() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["example.com"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://other-site.com")

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked,
                       "Allowlist must NOT match when page domain is not in the rule's domain list")
    }

    func testAllowlistDoesNotMatchSimilarHostAccidentally() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["example.com"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)

        // "nottracker.com" contains "tracker.com" as a substring but is a different domain
        let tdsWithExtra = TrackerData(
            trackers: [
                "tracker.com": KnownTracker(
                    domain: "tracker.com", defaultAction: .block,
                    owner: KnownTracker.Owner(name: "T", displayName: "T", ownedBy: nil),
                    prevalence: 0.1, subdomains: nil, categories: nil, rules: nil),
                "nottracker.com": KnownTracker(
                    domain: "nottracker.com", defaultAction: .block,
                    owner: KnownTracker.Owner(name: "N", displayName: "N", ownedBy: nil),
                    prevalence: 0.1, subdomains: nil, categories: nil, rules: nil)
            ],
            entities: [
                "T": Entity(displayName: "T", domains: ["tracker.com"], prevalence: 0.1),
                "N": Entity(displayName: "N", domains: ["nottracker.com"], prevalence: 0.1)
            ],
            domains: ["tracker.com": "T", "nottracker.com": "N"],
            cnames: nil)

        let mapperWithExtra = TrackerProtectionEventMapper(
            tld: tld, mainTrackerData: tdsWithExtra,
            unprotectedSites: [], tempList: [],
            contentBlockingEnabled: true, trackerAllowlist: allowlist)

        let result = classify(mapper: mapperWithExtra,
                              url: "https://nottracker.com/pixel.js", pageUrl: "https://example.com")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked,
                       "Allowlist for tracker.com must not accidentally match nottracker.com")
    }

    func testAllowlistAllDomainsWildcardMatchesAnyPage() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["<all>"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)

        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://any-site.org")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked, "<all> domain wildcard must match any page")
    }

    func testAllowlistMatchesTrackerSubdomains() {
        let allowlist: PrivacyConfigurationData.TrackerAllowlistData = [
            "tracker.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "tracker\\.com/pixel\\.js", domains: ["<all>"])
            ]
        ]
        let mapper = makeMapper(trackerAllowlist: allowlist)

        let result = classify(mapper: mapper, url: "https://sub.tracker.com/pixel.js", pageUrl: "https://example.com")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked,
                        "Allowlist must match subdomains of the allowlisted tracker domain")
    }

    func testWithoutAllowlistBlockedTrackerRemainsBlocked() {
        let mapper = makeMapper()
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://example.com")

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked, "Without allowlist, tracker must be blocked")
    }

    // MARK: - Affiliated Entity (makeThirdPartyRequest)

    private func makeAffiliatedTDS() -> TrackerData {
        let tracker = KnownTracker(
            domain: "tracker.com",
            defaultAction: .block,
            owner: KnownTracker.Owner(name: "Tracker Inc", displayName: "Tracker Inc", ownedBy: nil),
            prevalence: 0.1,
            subdomains: nil,
            categories: ["Analytics"],
            rules: nil)

        let entity = Entity(displayName: "Tracker Inc",
                            domains: ["tracker.com", "trackeraffiliated.com"],
                            prevalence: 0.1)

        return TrackerData(
            trackers: ["tracker.com": tracker],
            entities: ["Tracker Inc": entity],
            domains: ["tracker.com": "Tracker Inc", "trackeraffiliated.com": "Tracker Inc"],
            cnames: nil)
    }

    func testAffiliatedSameEntityCrossSiteEmitsOwnedByFirstParty() {
        let tds = makeAffiliatedTDS()
        let mapper = makeMapper(trackerData: tds)
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://trackeraffiliated.com/1.png",
            resourceType: "image",
            potentiallyBlocked: false,
            pageUrl: "https://tracker.com")

        let result = mapper.makeThirdPartyRequest(from: observation)
        XCTAssertNotNil(result, "Affiliated same-entity cross-site must emit a final event")
        if case .allowed(reason: .ownedByFirstParty) = result?.state {} else {
            XCTFail("Expected .ownedByFirstParty, got \(String(describing: result?.state))")
        }
    }

    func testUnaffiliatedCrossSiteNonTrackerEmitsOtherThirdPartyRequest() {
        let tds = makeAffiliatedTDS()
        let mapper = makeMapper(trackerData: tds)
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://nontracker.com/1.png",
            resourceType: "image",
            potentiallyBlocked: false,
            pageUrl: "https://tracker.com")

        let result = mapper.makeThirdPartyRequest(from: observation)
        XCTAssertNotNil(result, "Unaffiliated cross-site non-tracker must emit a final event")
        if case .allowed(reason: .otherThirdPartyRequest) = result?.state {} else {
            XCTFail("Expected .otherThirdPartyRequest, got \(String(describing: result?.state))")
        }
    }

    func testSameSiteNonTrackerProducesNoEvent() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://cdn.example.com/style.css",
            resourceType: "stylesheet",
            potentiallyBlocked: false,
            pageUrl: "https://example.com")

        let result = mapper.makeThirdPartyRequest(from: observation)
        XCTAssertNil(result, "Same-site non-tracker must produce no event")
    }

    // MARK: - Temp-List Subdomain Override

    func testTempListExactHostUnblocksTracker() {
        let mapper = makeMapper(tempList: ["example.com"])
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://example.com")

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked, "Exact temp-list host must disable protection")
        if case .allowed(reason: .protectionDisabled) = result?.state {} else {
            XCTFail("Expected .protectionDisabled, got \(String(describing: result?.state))")
        }
    }

    func testTempListSubdomainUnblocksTracker() {
        let mapper = makeMapper(tempList: ["example.com"])
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://sub.example.com")

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked, "Subdomain of temp-list entry must disable protection")
        if case .allowed(reason: .protectionDisabled) = result?.state {} else {
            XCTFail("Expected .protectionDisabled, got \(String(describing: result?.state))")
        }
    }

    func testTempListDeepSubdomainUnblocksTracker() {
        let mapper = makeMapper(tempList: ["example.com"])
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://a.b.c.example.com")

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked, "Deep subdomain of temp-list entry must disable protection")
    }

    func testLocallyUnprotectedSubdomainStillBlocked() {
        let mapper = makeMapper(unprotectedSites: ["example.com"])
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://sub.example.com")

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked,
                       "Locally-unprotected is exact-host only; subdomain must remain blocked")
    }

    func testTempListSimilarDomainStillBlocked() {
        let mapper = makeMapper(tempList: ["example.com"])
        let result = classify(mapper: mapper, url: "https://tracker.com/pixel.js", pageUrl: "https://notexample.com")

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked,
                       "Similar domain name must not accidentally match temp-list entry")
    }

    // MARK: - CTL Supplementary TDS (Option A validation)

    private func makeCtlTDS() -> TrackerData {
        let ctlRule = KnownTracker.Rule(
            rule: "facebook\\.net/.*sdk\\.js",
            surrogate: nil,
            action: .blockCTLFB,
            options: nil,
            exceptions: nil)
        let tracker = KnownTracker(
            domain: "facebook.net",
            defaultAction: .ignore,
            owner: KnownTracker.Owner(name: "Facebook Inc", displayName: "Facebook", ownedBy: nil),
            prevalence: 0.8,
            subdomains: nil,
            categories: nil,
            rules: [ctlRule])
        let entity = Entity(displayName: "Facebook", domains: ["facebook.net", "facebook.com"], prevalence: 0.8)
        return TrackerData(
            trackers: ["facebook.net": tracker],
            entities: ["Facebook Inc": entity],
            domains: ["facebook.net": "Facebook Inc", "facebook.com": "Facebook Inc"],
            cnames: nil)
    }

    func testCTLRuleBlockedWhenCTLTDSIncludedInSupplementary() {
        let mapper = TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: makeTestTDS(),
            supplementaryTrackerData: [makeCtlTDS()],
            unprotectedSites: [],
            tempList: [],
            contentBlockingEnabled: true,
            trackerAllowlist: [:])

        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://connect.facebook.net/en_US/sdk.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")
        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result, "CTL rule in supplementary TDS must produce a DetectedRequest")
        XCTAssertTrue(result!.isBlocked, "CTL rule must classify as blocked when CTL TDS is included")
    }

    func testCTLRuleNotBlockedWhenCTLTDSExcludedFromSupplementary() {
        let mapper = TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: makeTestTDS(),
            supplementaryTrackerData: [],
            unprotectedSites: [],
            tempList: [],
            contentBlockingEnabled: true,
            trackerAllowlist: [:])

        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://connect.facebook.net/en_US/sdk.js",
            resourceType: "script",
            potentiallyBlocked: false,
            pageUrl: "https://example.com")
        let result = mapper.classifyResource(observation)

        XCTAssertNil(result, "Without CTL TDS, facebook.net must not be classified as a tracker")
    }

    func testNonCTLTrackerUnaffectedByCTLTDSPresence() {
        let mapper = TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: makeTestTDS(),
            supplementaryTrackerData: [makeCtlTDS()],
            unprotectedSites: [],
            tempList: [],
            contentBlockingEnabled: true,
            trackerAllowlist: [:])

        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")
        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked, "Non-CTL tracker must remain blocked regardless of CTL TDS presence")
    }

    func testNonCTLTrackerStillBlockedWhenCTLTDSExcluded() {
        let mapper = TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: makeTestTDS(),
            supplementaryTrackerData: [],
            unprotectedSites: [],
            tempList: [],
            contentBlockingEnabled: true,
            trackerAllowlist: [:])

        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")
        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked, "Non-CTL tracker must remain blocked when CTL TDS is excluded")
    }

    // MARK: - Multi-TDS Loop Parity with Legacy ContentBlockerRulesUserScript
    //
    // These pin the documented contract of `classifyUrl`'s multi-TDS loop so any future
    // refactor that diverges from `ContentBlockerRulesUserScript.userContentController(_:didReceive:)`
    // fails loudly. The legacy script's behavior is the source of truth.

    /// When the supplementary TDS yields a non-blocked candidate (e.g. CTL-inactive
    /// `.allowed(reason: .ruleException)`) and the main TDS is empty for that URL, the
    /// supplementary candidate must survive — matching legacy semantics where the main
    /// resolver's `nil` result does not overwrite `detectedTracker`.
    func testSupplementaryNonBlockedCandidateSurvivesWhenMainTDSReturnsNil() {
        // Supplementary TDS contains facebook.net with default-ignore — yields a
        // non-blocked candidate. Main TDS contains only tracker.com so it returns nil
        // for facebook.net (mirrors splitter contract: supplementary trackers are
        // removed from main).
        let supplementary = makeCtlTDS()
        let mapper = TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: makeTestTDS(),
            supplementaryTrackerData: [supplementary],
            unprotectedSites: [],
            tempList: [],
            contentBlockingEnabled: true,
            trackerAllowlist: [:])

        // facebook.net/some.js does not match the CTL `sdk.js` rule, so the supplementary
        // resolver returns a non-blocked candidate (ignore-default + no matching rule).
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://connect.facebook.net/some-other.js",
            resourceType: "script",
            potentiallyBlocked: false,
            pageUrl: "https://example.com")

        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result, "Supplementary non-blocked candidate must survive when main TDS returns nil")
        XCTAssertFalse(result!.isBlocked, "Candidate from supplementary TDS must remain non-blocked")
        XCTAssertEqual(result?.eTLDplus1, "facebook.net",
                       "Returned candidate must be the supplementary TDS's classification")
    }

    /// When BOTH the supplementary and main TDSes classify the same URL, the main TDS
    /// result wins. This matches legacy `ContentBlockerRulesUserScript` line 180:
    /// `detectedTracker = tracker` (unconditional overwrite). The splitter contract makes
    /// this branch unreachable in practice, but we pin the semantics so the mapper and
    /// the legacy script can never silently diverge.
    func testMainTDSResultOverwritesSupplementaryNonBlockedCandidate() {
        // Both TDSes recognise tracker.com. Supplementary classifies it as ignore-default
        // (non-blocked). Main classifies it as block-default. Legacy semantics: main wins.
        let supplementaryTracker = KnownTracker(
            domain: "tracker.com",
            defaultAction: .ignore,
            owner: KnownTracker.Owner(name: "Supplementary Inc", displayName: "Supplementary", ownedBy: nil),
            prevalence: 0.1, subdomains: nil, categories: nil, rules: nil)
        let supplementaryTDS = TrackerData(
            trackers: ["tracker.com": supplementaryTracker],
            entities: ["Supplementary Inc": Entity(displayName: "Supplementary",
                                                   domains: ["tracker.com"], prevalence: 0.1)],
            domains: ["tracker.com": "Supplementary Inc"],
            cnames: nil)

        let mapper = TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: makeTestTDS(), // tracker.com defaultAction = .block
            supplementaryTrackerData: [supplementaryTDS],
            unprotectedSites: [],
            tempList: [],
            contentBlockingEnabled: true,
            trackerAllowlist: [:])

        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")
        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked,
                      "Main TDS result must overwrite supplementary candidate (legacy parity)")
        XCTAssertEqual(result?.entityName, "Tracker Inc",
                       "Returned classification must come from main TDS, not supplementary")
    }

    /// Supplementary blocked result must short-circuit the loop — main TDS is never consulted.
    /// Mirrors legacy `ContentBlockerRulesUserScript` lines 161–164: `if tracker.isBlocked { return }`.
    func testSupplementaryBlockedResultShortCircuitsMainTDS() {
        // Main TDS would classify tracker.com as blocked too, but the supplementary
        // matches first and short-circuits. We use a sentinel entity name to verify
        // which TDS produced the result.
        let supplementaryBlocking = KnownTracker(
            domain: "tracker.com",
            defaultAction: .block,
            owner: KnownTracker.Owner(name: "Supplementary Sentinel", displayName: "Sup", ownedBy: nil),
            prevalence: 0.1, subdomains: nil, categories: nil, rules: nil)
        let supplementaryTDS = TrackerData(
            trackers: ["tracker.com": supplementaryBlocking],
            entities: ["Supplementary Sentinel": Entity(displayName: "Sup",
                                                        domains: ["tracker.com"], prevalence: 0.1)],
            domains: ["tracker.com": "Supplementary Sentinel"],
            cnames: nil)

        let mapper = TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: makeTestTDS(),
            supplementaryTrackerData: [supplementaryTDS],
            unprotectedSites: [],
            tempList: [],
            contentBlockingEnabled: true,
            trackerAllowlist: [:])

        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")
        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isBlocked)
        XCTAssertEqual(result?.entityName, "Sup",
                       "Supplementary blocked result must short-circuit; main TDS must not run")
    }

    // MARK: - CTL-Inactive Parity (authentic split-TDS validation)
    // Uses ClickToLoadRulesSplitter with a facebook.net CTL fixture (macOS-only).

    #if os(macOS)

    // swiftlint:disable line_length
    private static let ctlExampleRules = """
    {
      "trackers": {
            "facebook.net": {
                "domain": "facebook.net",
                "owner": { "name": "Facebook, Inc.", "displayName": "Facebook", "privacyPolicy": "https://www.facebook.com/privacy/explanation", "url": "https://facebook.com" },
                "prevalence": 0.268, "fingerprinting": 2, "cookies": 0.208, "categories": [],
                "default": "ignore",
                "rules": [
                    { "rule": "facebook\\\\.net/.*/all\\\\.js", "surrogate": "fb-sdk.js", "action": "block-ctl-fb", "fingerprinting": 1, "cookies": 0.0000408 },
                    { "rule": "facebook\\\\.net/.*/fbevents\\\\.js", "fingerprinting": 1, "cookies": 0.108 },
                    { "rule": "facebook\\\\.net/[a-z_A-Z]+/sdk\\\\.js", "surrogate": "fb-sdk.js", "action": "block-ctl-fb", "fingerprinting": 1, "cookies": 0.000334 },
                    { "rule": "facebook\\\\.net/signals/config/", "fingerprinting": 1, "cookies": 0.000101 },
                    { "rule": "facebook\\\\.net\\\\/signals\\\\/plugins\\\\/openbridge3\\\\.js", "fingerprinting": 1, "cookies": 0 },
                    { "rule": "facebook\\\\.net/.*/sdk/.*customerchat\\\\.js", "fingerprinting": 1, "cookies": 0.00000681 },
                    { "rule": "facebook\\\\.net\\\\/en_US\\\\/messenger\\\\.Extensions\\\\.js", "fingerprinting": 1, "cookies": 0 },
                    { "rule": "facebook\\\\.net\\\\/en_US\\\\/sdk\\\\/xfbml\\\\.save\\\\.js", "fingerprinting": 1, "cookies": 0 },
                    { "rule": "facebook\\\\.net/", "action": "block-ctl-fb" }
                ]
            }
      },
      "entities": { "Facebook, Inc.": { "domains": ["facebook.net"], "displayName": "Facebook", "prevalence": 0.1 } },
      "domains": { "facebook.net": "Facebook, Inc." },
      "cnames": {}
    }
    """
    // swiftlint:enable line_length

    /// Builds the same split TDS that production uses via ClickToLoadRulesSplitter,
    /// then creates a mapper that models CTL-inactive state: main TDS = withoutBlockCTL,
    /// supplementary = [] (CTL TDS excluded per Option A).
    private func makeCtlInactiveMapper() throws -> TrackerProtectionEventMapper {
        let fullTDS = try JSONDecoder().decode(
            TrackerData.self, from: Self.ctlExampleRules.data(using: .utf8)!)
        let dataSet = TrackerDataManager.DataSet(tds: fullTDS, etag: "test")
        let ruleList = ContentBlockerRulesList(
            name: "TrackerDataSet", trackerData: nil, fallbackTrackerData: dataSet)
        let splits = try XCTUnwrap(ClickToLoadRulesSplitter(rulesList: ruleList).split())

        return TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: splits.withoutBlockCTL.fallbackTrackerData.tds,
            supplementaryTrackerData: [],
            unprotectedSites: [],
            tempList: [],
            contentBlockingEnabled: true,
            trackerAllowlist: [:])
    }

    func testCTLInactiveCatchAllProducesNonBlockedEvent() throws {
        let mapper = try makeCtlInactiveMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://www.facebook.net/some.js",
            resourceType: "script",
            potentiallyBlocked: false,
            pageUrl: "https://example.com")

        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result, "CTL-inactive catch-all must still produce a DetectedRequest")
        XCTAssertFalse(result!.isBlocked, "CTL-inactive catch-all must not be blocked")
        if case .allowed(reason: .ruleException) = result?.state {} else {
            XCTFail("Expected .ruleException for CTL-inactive ignore-default tracker, got \(String(describing: result?.state))")
        }
    }

    func testCTLInactiveSDKProducesNonBlockedEvent() throws {
        let mapper = try makeCtlInactiveMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://www.facebook.net/EN/sdk.js",
            resourceType: "script",
            potentiallyBlocked: false,
            pageUrl: "https://example.com")

        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result, "CTL-inactive SDK must still produce a DetectedRequest")
        XCTAssertFalse(result!.isBlocked, "CTL-inactive SDK must not be blocked")
        if case .allowed(reason: .ruleException) = result?.state {} else {
            XCTFail("Expected .ruleException for CTL-inactive SDK, got \(String(describing: result?.state))")
        }
    }

    func testCTLInactiveNonCTLRuleStillBlocked() throws {
        let mapper = try makeCtlInactiveMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://www.facebook.net/signals/config/config.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")

        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result, "Non-CTL facebook.net rule must still produce a DetectedRequest")
        XCTAssertTrue(result!.isBlocked, "Non-CTL rule must remain blocked even when CTL is inactive")
    }

    func testCTLActiveSDKIsBlocked() throws {
        let fullTDS = try JSONDecoder().decode(
            TrackerData.self, from: Self.ctlExampleRules.data(using: .utf8)!)
        let dataSet = TrackerDataManager.DataSet(tds: fullTDS, etag: "test")
        let ruleList = ContentBlockerRulesList(
            name: "TrackerDataSet", trackerData: nil, fallbackTrackerData: dataSet)
        let splits = try XCTUnwrap(ClickToLoadRulesSplitter(rulesList: ruleList).split())

        let mapper = TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: splits.withoutBlockCTL.fallbackTrackerData.tds,
            supplementaryTrackerData: [splits.withBlockCTL.fallbackTrackerData.tds],
            unprotectedSites: [],
            tempList: [],
            contentBlockingEnabled: true,
            trackerAllowlist: [:])

        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://www.facebook.net/EN/sdk.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")

        let result = mapper.classifyResource(observation)

        XCTAssertNotNil(result, "CTL-active SDK must produce a DetectedRequest")
        XCTAssertTrue(result!.isBlocked, "CTL-active SDK must be blocked")
    }
    #endif
}
