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

final class TrackerProtectionEventMapperTests: XCTestCase {

    private let tld = TLD()
    private lazy var mapper = TrackerProtectionEventMapper(tld: tld)

    // MARK: - Helpers

    private func makeTracker(
        url: String = "https://tracker.example/pixel.js",
        blocked: Bool = true,
        reason: String? = "default block",
        isSurrogate: Bool = false,
        pageUrl: String = "https://example.com",
        entityName: String? = "Tracker Inc",
        ownerName: String? = "Tracker Inc",
        category: String? = "Analytics",
        prevalence: Double? = 0.1,
        isAllowlisted: Bool? = false
    ) -> TrackerProtectionSubfeature.TrackerDetection {
        let params: [String: Any?] = [
            "url": url,
            "blocked": blocked,
            "reason": reason,
            "isSurrogate": isSurrogate,
            "pageUrl": pageUrl,
            "entityName": entityName,
            "ownerName": ownerName,
            "category": category,
            "prevalence": prevalence,
            "isAllowlisted": isAllowlisted
        ]
        let filtered = params.compactMapValues { $0 }
        let data = try! JSONSerialization.data(withJSONObject: filtered)
        return try! JSONDecoder().decode(TrackerProtectionSubfeature.TrackerDetection.self, from: data)
    }

    private func makeSurrogate(
        url: String = "https://tracker.example/analytics.js",
        pageUrl: String = "https://example.com",
        entityName: String? = nil,
        ownerName: String? = nil
    ) -> TrackerProtectionSubfeature.SurrogateInjection {
        let params: [String: Any?] = [
            "url": url,
            "blocked": true,
            "reason": "matched rule - surrogate",
            "isSurrogate": true,
            "pageUrl": pageUrl,
            "entityName": entityName,
            "ownerName": ownerName
        ]
        let filtered = params.compactMapValues { $0 }
        let data = try! JSONSerialization.data(withJSONObject: filtered)
        return try! JSONDecoder().decode(TrackerProtectionSubfeature.SurrogateInjection.self, from: data)
    }

    // MARK: - P0-1: Same-site suppression (strict same eTLD+1)

    func testSameSiteDetection_sameETLDplus1_tracker_returnsTrue() {
        let tracker = makeTracker(
            url: "https://cdn.example.com/pixel.js",
            blocked: true,
            reason: "default block",
            pageUrl: "https://www.example.com/page"
        )
        XCTAssertTrue(mapper.isSameSiteDetection(tracker))
    }

    func testSameSiteDetection_sameETLDplus1_thirdPartyRequest_returnsTrue() {
        let tracker = makeTracker(
            url: "https://cdn.example.com/image.png",
            blocked: false,
            reason: "thirdPartyRequest",
            pageUrl: "https://www.example.com"
        )
        XCTAssertTrue(mapper.isSameSiteDetection(tracker))
    }

    func testSameSiteDetection_differentETLDplus1_returnsFalse() {
        let tracker = makeTracker(
            url: "https://tracker.other.com/pixel.js",
            pageUrl: "https://www.example.com"
        )
        XCTAssertFalse(mapper.isSameSiteDetection(tracker))
    }

    func testSameSiteDetection_sameHost_returnsTrue() {
        let tracker = makeTracker(
            url: "https://example.com/pixel.js",
            pageUrl: "https://example.com/page"
        )
        XCTAssertTrue(mapper.isSameSiteDetection(tracker))
    }

    func testSameSiteDetection_firstPartyReason_sameETLDplus1_returnsTrue() {
        let tracker = makeTracker(
            url: "https://cdn.example.com/script.js",
            blocked: false,
            reason: "first party",
            pageUrl: "https://www.example.com"
        )
        XCTAssertTrue(mapper.isSameSiteDetection(tracker))
    }

    // MARK: - P0-2: Affiliated third-party tracker → ownedByFirstParty

    func testAffiliatedTracker_firstPartyReason_mapsToOwnedByFirstParty() {
        let tracker = makeTracker(
            url: "https://connect.facebook.net/sdk.js",
            blocked: false,
            reason: "first party",
            pageUrl: "https://facebook.com",
            entityName: "Facebook",
            ownerName: "Facebook, Inc."
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertFalse(request.isBlocked)
        if case .allowed(let reason) = request.state {
            XCTAssertEqual(reason, .ownedByFirstParty)
        } else {
            XCTFail("Expected allowed state with ownedByFirstParty reason")
        }
        XCTAssertEqual(request.ownerName, "Facebook, Inc.")
        XCTAssertEqual(request.entityName, "Facebook")
    }

    // MARK: - P0-3: Unaffiliated third-party tracker

    func testUnaffiliatedTracker_blocked_mapsToBlocked() {
        let tracker = makeTracker(
            url: "https://tracker.example/pixel.js",
            blocked: true,
            reason: "default block",
            pageUrl: "https://mysite.com"
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertTrue(request.isBlocked)
        XCTAssertEqual(request.state, .blocked)
    }

    func testUnaffiliatedTracker_ignored_mapsToRuleException() {
        let tracker = makeTracker(
            url: "https://tracker.example/pixel.js",
            blocked: false,
            reason: "default ignore",
            pageUrl: "https://mysite.com"
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertFalse(request.isBlocked)
        if case .allowed(let reason) = request.state {
            XCTAssertEqual(reason, .ruleException)
        } else {
            XCTFail("Expected allowed state")
        }
    }

    func testUnaffiliatedTracker_matchedRuleIgnore_mapsToRuleException() {
        let tracker = makeTracker(
            url: "https://tracker.example/pixel.js",
            blocked: false,
            reason: "matched rule - ignore",
            pageUrl: "https://mysite.com"
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertFalse(request.isBlocked)
        if case .allowed(let reason) = request.state {
            XCTAssertEqual(reason, .ruleException)
        } else {
            XCTFail("Expected allowed state")
        }
    }

    // MARK: - P0-4: Non-tracker same-site suppression

    func testThirdPartyRequest_sameSite_isSameSiteDetection() {
        let tracker = makeTracker(
            url: "https://cdn.example.com/style.css",
            blocked: false,
            reason: "thirdPartyRequest",
            pageUrl: "https://www.example.com",
            entityName: nil,
            ownerName: nil,
            category: nil,
            prevalence: nil
        )
        XCTAssertTrue(mapper.isSameSiteDetection(tracker))
    }

    // MARK: - P0-5: Non-tracker affiliated classification

    func testAffiliatedNonTracker_affiliatedReason_mapsToOwnedByFirstParty() {
        let tracker = makeTracker(
            url: "https://fbcdn.net/image.jpg",
            blocked: false,
            reason: "thirdPartyRequestOwnedByFirstParty",
            pageUrl: "https://facebook.com",
            entityName: "Facebook",
            ownerName: "Facebook, Inc."
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertFalse(request.isBlocked)
        if case .allowed(let reason) = request.state {
            XCTAssertEqual(reason, .ownedByFirstParty)
        } else {
            XCTFail("Expected allowed state with ownedByFirstParty reason")
        }
        XCTAssertEqual(request.entityName, "Facebook")
    }

    func testAffiliatedNonTracker_routesAsThirdPartyRequest() {
        let tracker = makeTracker(
            url: "https://fbcdn.net/image.jpg",
            blocked: false,
            reason: "thirdPartyRequestOwnedByFirstParty",
            pageUrl: "https://facebook.com",
            entityName: "Facebook",
            ownerName: "Facebook, Inc."
        )
        XCTAssertTrue(
            TrackerProtectionEventMapper.isThirdPartyRequest(tracker),
            "Affiliated non-tracker should route as thirdPartyRequest, not through the tracker path"
        )
    }

    func testUnaffiliatedNonTracker_thirdPartyRequestReason_mapsToOtherThirdPartyRequest() {
        let tracker = makeTracker(
            url: "https://cdn.other.com/lib.js",
            blocked: false,
            reason: "thirdPartyRequest",
            pageUrl: "https://example.com",
            entityName: nil,
            ownerName: nil
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertFalse(request.isBlocked)
        if case .allowed(let reason) = request.state {
            XCTAssertEqual(reason, .otherThirdPartyRequest)
        } else {
            XCTFail("Expected allowed state")
        }
    }

    // MARK: - P0-6: pageUrl passthrough

    func testPageUrlPassedThrough_tracker() {
        let tracker = makeTracker(pageUrl: "https://example.com/page?q=1")
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertEqual(request.pageUrl, "https://example.com/page?q=1")
    }

    func testPageUrlPassedThrough_surrogate() {
        let surrogate = makeSurrogate(pageUrl: "https://example.com/page?q=1")
        let request = mapper.detectedRequest(from: surrogate)
        XCTAssertEqual(request.pageUrl, "https://example.com/page?q=1")
    }

    // MARK: - P0-7/P0-8: Surrogate mapping

    func testSurrogateDetection_mapsToBlocked() {
        let surrogate = makeSurrogate(url: "https://tracker.example/analytics.js")
        let request = mapper.detectedRequest(from: surrogate)
        XCTAssertTrue(request.isBlocked)
        XCTAssertEqual(request.state, .blocked)
    }

    func testSurrogateDetection_withMetadata_prefersSurrogateEntityAndOwner() {
        let surrogate = makeSurrogate(
            url: "https://doubleclick.net/instream/ad_status.js",
            entityName: "Google Ads (Google)",
            ownerName: "Google LLC"
        )
        let request = mapper.detectedRequest(from: surrogate)
        XCTAssertEqual(request.entityName, "Google Ads (Google)")
        XCTAssertEqual(request.ownerName, "Google LLC")
    }

    func testSurrogateDetection_withoutMetadata_fallsBackToHostEntity() {
        let surrogate = makeSurrogate(url: "https://doubleclick.net/instream/ad_status.js")
        let request = mapper.detectedRequest(from: surrogate)
        XCTAssertEqual(request.entityName, "doubleclick.net")
        XCTAssertNil(request.ownerName)
    }

    func testSurrogateHost_extracted() {
        let surrogate = makeSurrogate(url: "https://tracker.example/analytics.js")
        let host = mapper.surrogateHost(from: surrogate)
        XCTAssertEqual(host, "tracker.example")
    }

    func testSurrogateHost_iframePageUrl() {
        let surrogate = makeSurrogate(
            url: "https://tracker.example/analytics.js",
            pageUrl: "https://example.com/page-with-iframe"
        )
        let request = mapper.detectedRequest(from: surrogate)
        XCTAssertEqual(request.pageUrl, "https://example.com/page-with-iframe")
        XCTAssertTrue(request.isBlocked)
    }

    // MARK: - P0-9: FB callback parity — tested via ContentBlockingTabExtension

    // MARK: - isThirdPartyRequest classification

    func testIsThirdPartyRequest_thirdPartyRequestReason_returnsTrue() {
        let tracker = makeTracker(reason: "thirdPartyRequest")
        XCTAssertTrue(TrackerProtectionEventMapper.isThirdPartyRequest(tracker))
    }

    func testIsThirdPartyRequest_defaultBlockReason_returnsFalse() {
        let tracker = makeTracker(reason: "default block")
        XCTAssertFalse(TrackerProtectionEventMapper.isThirdPartyRequest(tracker))
    }

    func testIsThirdPartyRequest_firstPartyReason_returnsFalse() {
        let tracker = makeTracker(reason: "first party")
        XCTAssertFalse(
            TrackerProtectionEventMapper.isThirdPartyRequest(tracker),
            "Entity-affiliated tracker should stay on the tracker path, not be routed as thirdPartyRequest"
        )
    }

    func testIsThirdPartyRequest_affiliatedThirdPartyReason_returnsTrue() {
        let tracker = makeTracker(reason: "thirdPartyRequestOwnedByFirstParty")
        XCTAssertTrue(
            TrackerProtectionEventMapper.isThirdPartyRequest(tracker),
            "Affiliated non-tracker should route as thirdPartyRequest to avoid tracker side effects"
        )
    }

    func testIsThirdPartyRequest_nilReason_returnsFalse() {
        let tracker = makeTracker(reason: nil)
        XCTAssertFalse(TrackerProtectionEventMapper.isThirdPartyRequest(tracker))
    }

    // MARK: - P1-6: Metadata fidelity

    func testMetadataFidelity_allFieldsPreserved() {
        let tracker = makeTracker(
            url: "https://tracker.test.com/pixel.js",
            blocked: true,
            reason: "default block",
            pageUrl: "https://page.test.com",
            entityName: "Tracker Inc",
            ownerName: "Tracker Inc",
            category: "Analytics",
            prevalence: 0.42
        )
        let request = mapper.detectedRequest(from: tracker)

        XCTAssertEqual(request.url, "https://tracker.test.com/pixel.js")
        XCTAssertEqual(request.ownerName, "Tracker Inc")
        XCTAssertEqual(request.entityName, "Tracker Inc")
        XCTAssertEqual(request.category, "Analytics")
        XCTAssertEqual(request.prevalence, 0.42)
        XCTAssertEqual(request.pageUrl, "https://page.test.com")
        XCTAssertEqual(request.eTLDplus1, "test.com")
    }

    func testMetadataFidelity_nilOptionalFieldsPreserved() {
        let tracker = makeTracker(
            entityName: nil,
            ownerName: nil,
            category: nil,
            prevalence: nil
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertNil(request.ownerName)
        XCTAssertNil(request.entityName)
        XCTAssertNil(request.category)
        XCTAssertNil(request.prevalence)
    }

    // MARK: - End-to-end reason chain (event payload -> DetectedRequest state -> dashboard grouping)

    func testReasonChain_ruleException_mapsToAllowlisted() {
        let tracker = makeTracker(
            url: "https://tracker.example/pixel.js",
            blocked: false,
            reason: "matched rule - exception",
            pageUrl: "https://mysite.com"
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertEqual(request.state, .allowed(reason: .ruleException))
        XCTAssertFalse(TrackerProtectionEventMapper.isThirdPartyRequest(tracker),
                       "Rule exception tracker should NOT route as thirdPartyRequest")
    }

    func testReasonChain_defaultBlock_mapsToBlocked() {
        let tracker = makeTracker(
            url: "https://tracker.example/pixel.js",
            blocked: true,
            reason: "default block",
            pageUrl: "https://mysite.com"
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertEqual(request.state, .blocked)
        XCTAssertFalse(TrackerProtectionEventMapper.isThirdPartyRequest(tracker),
                       "Blocked tracker should NOT route as thirdPartyRequest")
    }

    func testReasonChain_thirdPartyRequest_mapsToAlsoLoaded() {
        let tracker = makeTracker(
            url: "https://cdn.other.com/lib.js",
            blocked: false,
            reason: "thirdPartyRequest",
            pageUrl: "https://mysite.com",
            entityName: nil,
            ownerName: nil,
            category: nil,
            prevalence: nil
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertEqual(request.state, .allowed(reason: .otherThirdPartyRequest))
        XCTAssertTrue(TrackerProtectionEventMapper.isThirdPartyRequest(tracker),
                      "Non-tracker third-party should route as thirdPartyRequest")
    }

    func testReasonChain_affiliatedThirdParty_mapsToOwnedByFirstParty() {
        let tracker = makeTracker(
            url: "https://fbcdn.net/image.jpg",
            blocked: false,
            reason: "thirdPartyRequestOwnedByFirstParty",
            pageUrl: "https://facebook.com",
            entityName: "Facebook",
            ownerName: "Facebook, Inc."
        )
        let request = mapper.detectedRequest(from: tracker)
        XCTAssertEqual(request.state, .allowed(reason: .ownedByFirstParty),
                       "Affiliated non-tracker should map to ownedByFirstParty (key affiliated path on Apple)")
        XCTAssertTrue(TrackerProtectionEventMapper.isThirdPartyRequest(tracker),
                      "Affiliated non-tracker should route as thirdPartyRequest, not through the tracker path")
    }

    // MARK: - Unprotected domain reason mapping

    func testUnprotectedDomainReason_mapsToProtectionDisabled() {
        let tracker = makeTracker(blocked: false, reason: "unprotectedDomain")
        let request = mapper.detectedRequest(from: tracker)
        if case .allowed(let reason) = request.state {
            XCTAssertEqual(reason, .protectionDisabled)
        } else {
            XCTFail("Expected allowed state with protectionDisabled")
        }
    }

    // MARK: - Rule exception reason mapping

    func testRuleExceptionReason_mapsToRuleException() {
        let tracker = makeTracker(blocked: false, reason: "matched rule - exception")
        let request = mapper.detectedRequest(from: tracker)
        if case .allowed(let reason) = request.state {
            XCTAssertEqual(reason, .ruleException)
        } else {
            XCTFail("Expected allowed state with ruleException")
        }
    }
}
