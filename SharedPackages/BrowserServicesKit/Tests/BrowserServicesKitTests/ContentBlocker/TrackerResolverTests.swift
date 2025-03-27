//
//  TrackerResolverTests.swift
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

import Common
import ContentBlocking
import TrackerRadarKit
import XCTest

@testable import BrowserServicesKit

class TrackerResolverTests: XCTestCase {

    let tld = TLD()

    func testWhenOptionsAreEmptyThenNothingMatches() {

        let rule = KnownTracker.Rule.Matching(domains: [], types: [])

        let urlOne = URL(string: "https://www.one.com")!

        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "image"))
    }

    func testWhenJustDomainsAreRequiredThenTypesDoNotMatter() {

        let rule = KnownTracker.Rule.Matching(domains: ["one.com", "two.com"], types: nil)

        let urlOne = URL(string: "https://www.one.com")!
        let urlTwo = URL(string: "https://two.com")!
        let urlThree = URL(string: "https://www.three.com")!

        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "image"))
        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlTwo.host!,
                                                 resourceType: "image"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                  host: urlThree.host!,
                                                  resourceType: "image"))
    }

    func testWhenJustTypesAreRequiredThenDomainsDoNotMatter() {

        let rule = KnownTracker.Rule.Matching(domains: [], types: ["image", "script"])

        let urlOne = URL(string: "https://www.one.com")!
        let urlTwo = URL(string: "https://two.com")!
        let urlThree = URL(string: "https://www.three.com")!

        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "image"))
        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlTwo.host!,
                                                 resourceType: "script"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlThree.host!,
                                                 resourceType: "link"))
        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlThree.host!,
                                                 resourceType: "image"))
    }

    func testWhenTypesAndDomainsAreRequiredThenBothMustMatch() {

        let rule = KnownTracker.Rule.Matching(domains: ["one.com", "two.com"], types: ["image", "script"])

        let urlOne = URL(string: "https://www.one.com")!
        let urlTwo = URL(string: "https://two.com")!
        let urlThree = URL(string: "https://www.three.com")!

        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "image"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "link"))
        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlOne.host!,
                                                 resourceType: "script"))

        XCTAssertTrue(TrackerResolver.isMatching(rule,
                                                 host: urlTwo.host!,
                                                 resourceType: "script"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlTwo.host!,
                                                 resourceType: "link"))

        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlThree.host!,
                                                 resourceType: "link"))
        XCTAssertFalse(TrackerResolver.isMatching(rule,
                                                 host: urlThree.host!,
                                                 resourceType: "image"))
    }

    func testWhenTrackerIsDetectedThenItIsReported() {

        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: ["Advertising"],
                                   rules: nil)

        let entity = Entity(displayName: "Trackr Inc company",
                            domains: ["tracker.com"],
                            prevalence: 0.1)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": entity],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [], tld: tld)

        let result = resolver.trackerFromUrl("https://tracker.com/img/1.png", pageUrlString: "https://example.com", resourceType: "image", potentiallyBlocked: true)

        XCTAssertNotNil(result)
        XCTAssert(result?.isBlocked ?? false)
        XCTAssertEqual(result?.state, .blocked)
        XCTAssertEqual(result?.ownerName, tracker.owner?.name)
        XCTAssertEqual(result?.entityName, entity.displayName)
        XCTAssertEqual(result?.category, tracker.category)
        XCTAssertEqual(result?.prevalence, tracker.prevalence)
    }

    func testWhenTrackerWithBlockActionHasRulesThenTheseAreRespected() {

        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: [
                                    KnownTracker.Rule(rule: "tracker\\.com/attr/.*",
                                                      surrogate: nil,
                                                      action: nil,
                                                      options: nil,
                                                      exceptions: KnownTracker.Rule.Matching(domains: ["attributed.com"],
                                                                                             types: nil)),
                                    KnownTracker.Rule(rule: "tracker\\.com/ctl-block/.*",
                                                      surrogate: nil,
                                                      action: .blockCTLFB,
                                                      options: nil,
                                                      exceptions: KnownTracker.Rule.Matching(domains: ["other.com"],
                                                                                             types: nil)),
                                    KnownTracker.Rule(rule: "tracker\\.com/ctl-surrogate/.*",
                                                      surrogate: "fb-sdk.js",
                                                      action: .blockCTLFB,
                                                      options: nil,
                                                      exceptions: KnownTracker.Rule.Matching(domains: ["other.com"],
                                                                                             types: nil)),
                                    KnownTracker.Rule(rule: "tracker\\.com/ignore/.*",
                                                      surrogate: nil,
                                                      action: .ignore,
                                                      options: KnownTracker.Rule.Matching(domains: ["exception.com"],
                                                                                          types: nil),
                                                      exceptions: nil),
                                    KnownTracker.Rule(rule: "tracker\\.com/nil/.*",
                                                      surrogate: nil,
                                                      action: nil,
                                                      options: nil,
                                                      exceptions: KnownTracker.Rule.Matching(domains: ["other.com"],
                                                                                             types: nil))
                                   ])

        let entity = Entity(displayName: "Trackr Inc company",
                            domains: ["tracker.com"],
                            prevalence: 0.1)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": entity],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds,
                                       unprotectedSites: [],
                                       tempList: [],
                                       tld: tld,
                                       adClickAttributionVendor: "attributed.com")

        let blockedImgUrl = resolver.trackerFromUrl("https://tracker.com/img/1.png",
                                                    pageUrlString: "https://example.com",
                                                    resourceType: "image",
                                                    potentiallyBlocked: true)

        XCTAssertNotNil(blockedImgUrl)
        XCTAssert(blockedImgUrl?.isBlocked ?? false)
        XCTAssertEqual(blockedImgUrl?.state, .blocked)
        XCTAssertEqual(blockedImgUrl?.ownerName, tracker.owner?.name)
        XCTAssertEqual(blockedImgUrl?.entityName, entity.displayName)
        XCTAssertEqual(blockedImgUrl?.category, tracker.category)
        XCTAssertEqual(blockedImgUrl?.prevalence, tracker.prevalence)

        let ignoredTrackerRuleOption = resolver.trackerFromUrl("https://tracker.com/ignore/s.js",
                                                               pageUrlString: "https://exception.com",
                                                               resourceType: "image",
                                                               potentiallyBlocked: true)

        XCTAssertNotNil(ignoredTrackerRuleOption)
        XCTAssertFalse(ignoredTrackerRuleOption?.isBlocked ?? false)
        XCTAssertEqual(ignoredTrackerRuleOption?.state, BlockingState.allowed(reason: .ruleException))
        XCTAssertEqual(ignoredTrackerRuleOption?.ownerName, tracker.owner?.name)
        XCTAssertEqual(ignoredTrackerRuleOption?.entityName, entity.displayName)
        XCTAssertEqual(ignoredTrackerRuleOption?.category, tracker.category)
        XCTAssertEqual(ignoredTrackerRuleOption?.prevalence, tracker.prevalence)

        let blockTrackerRuleOption = resolver.trackerFromUrl("https://tracker.com/ignore/s.js",
                                                             pageUrlString: "https://other.com",
                                                             resourceType: "image",
                                                             potentiallyBlocked: true)

        XCTAssertNotNil(blockTrackerRuleOption)
        XCTAssertFalse(blockTrackerRuleOption?.isBlocked ?? false)
        XCTAssertEqual(blockTrackerRuleOption?.state, BlockingState.allowed(reason: .ruleException))
        XCTAssertEqual(blockTrackerRuleOption?.ownerName, tracker.owner?.name)
        XCTAssertEqual(blockTrackerRuleOption?.entityName, entity.displayName)
        XCTAssertEqual(blockTrackerRuleOption?.category, tracker.category)
        XCTAssertEqual(blockTrackerRuleOption?.prevalence, tracker.prevalence)

        let ignoredTrackerRuleException = resolver.trackerFromUrl("https://tracker.com/nil/s.js",
                                                                     pageUrlString: "https://other.com",
                                                                     resourceType: "image",
                                                                     potentiallyBlocked: true)

        XCTAssertNotNil(ignoredTrackerRuleException)
        XCTAssertFalse(ignoredTrackerRuleException?.isBlocked ?? false)
        XCTAssertEqual(ignoredTrackerRuleException?.state, BlockingState.allowed(reason: .ruleException))
        XCTAssertEqual(ignoredTrackerRuleException?.ownerName, tracker.owner?.name)
        XCTAssertEqual(ignoredTrackerRuleException?.entityName, entity.displayName)
        XCTAssertEqual(ignoredTrackerRuleException?.category, tracker.category)
        XCTAssertEqual(ignoredTrackerRuleException?.prevalence, tracker.prevalence)

        let blockTrackerRuleException = resolver.trackerFromUrl("https://tracker.com/nil/s.js",
                                                                     pageUrlString: "https://example.com",
                                                                     resourceType: "image",
                                                                     potentiallyBlocked: true)

        XCTAssertNotNil(blockTrackerRuleException)
        XCTAssert(blockTrackerRuleException?.isBlocked ?? false)
        XCTAssertEqual(blockTrackerRuleException?.state, BlockingState.blocked)
        XCTAssertEqual(blockTrackerRuleException?.ownerName, tracker.owner?.name)
        XCTAssertEqual(blockTrackerRuleException?.entityName, entity.displayName)
        XCTAssertEqual(blockTrackerRuleException?.category, tracker.category)
        XCTAssertEqual(blockTrackerRuleException?.prevalence, tracker.prevalence)

        let blockTrackerRuleAttributedException = resolver.trackerFromUrl("https://tracker.com/attr/s.js",
                                                                     pageUrlString: "https://attributed.com",
                                                                     resourceType: "image",
                                                                     potentiallyBlocked: true)

        XCTAssertNotNil(blockTrackerRuleAttributedException)
        XCTAssertFalse(blockTrackerRuleAttributedException?.isBlocked ?? true)
        XCTAssertEqual(blockTrackerRuleAttributedException?.state, BlockingState.allowed(reason: .adClickAttribution))
        XCTAssertEqual(blockTrackerRuleAttributedException?.ownerName, tracker.owner?.name)
        XCTAssertEqual(blockTrackerRuleAttributedException?.entityName, entity.displayName)
        XCTAssertEqual(blockTrackerRuleAttributedException?.category, tracker.category)
        XCTAssertEqual(blockTrackerRuleAttributedException?.prevalence, tracker.prevalence)

        let blockTrackerRuleCTLBlock = resolver.trackerFromUrl("https://tracker.com/ctl-block/s.js",
                                                                     pageUrlString: "https://example.com",
                                                                     resourceType: "image",
                                                                     potentiallyBlocked: true)

        XCTAssertNotNil(blockTrackerRuleCTLBlock)
        XCTAssert(blockTrackerRuleCTLBlock?.isBlocked ?? false)
        XCTAssertEqual(blockTrackerRuleCTLBlock?.state, .blocked)
        XCTAssertEqual(blockTrackerRuleCTLBlock?.ownerName, tracker.owner?.name)
        XCTAssertEqual(blockTrackerRuleCTLBlock?.entityName, entity.displayName)
        XCTAssertEqual(blockTrackerRuleCTLBlock?.category, tracker.category)
        XCTAssertEqual(blockTrackerRuleCTLBlock?.prevalence, tracker.prevalence)

        let blockTrackerRuleCTLSurrogate = resolver.trackerFromUrl("https://tracker.com/ctl-surrogate/s.js",
                                                                     pageUrlString: "https://example.com",
                                                                     resourceType: "image",
                                                                     potentiallyBlocked: true)

        XCTAssertNotNil(blockTrackerRuleCTLSurrogate)
        XCTAssert(blockTrackerRuleCTLSurrogate?.isBlocked ?? false)
        XCTAssertEqual(blockTrackerRuleCTLSurrogate?.state, .blocked)
        XCTAssertEqual(blockTrackerRuleCTLSurrogate?.ownerName, tracker.owner?.name)
        XCTAssertEqual(blockTrackerRuleCTLSurrogate?.entityName, entity.displayName)
        XCTAssertEqual(blockTrackerRuleCTLSurrogate?.category, tracker.category)
        XCTAssertEqual(blockTrackerRuleCTLSurrogate?.prevalence, tracker.prevalence)

        let ignoreTrackerRuleCTLException = resolver.trackerFromUrl("https://tracker.com/ctl-block/s.js",
                                                                     pageUrlString: "https://other.com",
                                                                     resourceType: "image",
                                                                     potentiallyBlocked: true)

        XCTAssertNotNil(ignoreTrackerRuleCTLException)
        XCTAssertFalse(ignoreTrackerRuleCTLException?.isBlocked ?? true)
        XCTAssertEqual(ignoreTrackerRuleCTLException?.state, BlockingState.allowed(reason: .ruleException))
        XCTAssertEqual(ignoreTrackerRuleCTLException?.ownerName, tracker.owner?.name)
        XCTAssertEqual(ignoreTrackerRuleCTLException?.entityName, entity.displayName)
        XCTAssertEqual(ignoreTrackerRuleCTLException?.category, tracker.category)
        XCTAssertEqual(ignoreTrackerRuleCTLException?.prevalence, tracker.prevalence)

    }

    func testWhenTrackerWithIgnoreActionHasRulesThenTheseAreRespected() {

        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .ignore,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: [KnownTracker.Rule(rule: "tracker\\.com/script/.*",
                                                             surrogate: nil,
                                                             action: nil, // default - block
                                                             options: nil,
                                                             exceptions: KnownTracker.Rule.Matching(domains: ["exception.com"],
                                                                                                     types: nil))])

        let entity = Entity(displayName: "Trackr Inc company",
                            domains: ["tracker.com"],
                            prevalence: 0.1)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": entity],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [], tld: tld)

        let resultImgUrl = resolver.trackerFromUrl("https://tracker.com/img/1.png",
                                                   pageUrlString: "https://example.com",
                                                   resourceType: "image",
                                                   potentiallyBlocked: true)

        XCTAssertNotNil(resultImgUrl)
        XCTAssertFalse(resultImgUrl?.isBlocked ?? false)
        XCTAssertEqual(resultImgUrl?.state, BlockingState.allowed(reason: .ruleException))
        XCTAssertEqual(resultImgUrl?.ownerName, tracker.owner?.name)
        XCTAssertEqual(resultImgUrl?.entityName, entity.displayName)
        XCTAssertEqual(resultImgUrl?.category, tracker.category)
        XCTAssertEqual(resultImgUrl?.prevalence, tracker.prevalence)

        let resultScriptURL = resolver.trackerFromUrl("https://tracker.com/script/s.js",
                                                      pageUrlString: "https://example.com",
                                                      resourceType: "image",
                                                      potentiallyBlocked: true)

        XCTAssertNotNil(resultScriptURL)
        XCTAssert(resultScriptURL?.isBlocked ?? false)
        XCTAssertEqual(resultScriptURL?.state, BlockingState.blocked)
        XCTAssertEqual(resultScriptURL?.ownerName, tracker.owner?.name)
        XCTAssertEqual(resultScriptURL?.entityName, entity.displayName)
        XCTAssertEqual(resultScriptURL?.category, tracker.category)
        XCTAssertEqual(resultScriptURL?.prevalence, tracker.prevalence)

        let resultScriptURLOnExceptionSite = resolver.trackerFromUrl("https://tracker.com/script/s.js",
                                                                     pageUrlString: "https://exception.com",
                                                                     resourceType: "image",
                                                                     potentiallyBlocked: true)

        XCTAssertNotNil(resultScriptURLOnExceptionSite)
        XCTAssertFalse(resultScriptURLOnExceptionSite?.isBlocked ?? false)
        XCTAssertEqual(resultScriptURLOnExceptionSite?.state, BlockingState.allowed(reason: .ruleException))
        XCTAssertEqual(resultScriptURLOnExceptionSite?.ownerName, tracker.owner?.name)
        XCTAssertEqual(resultScriptURLOnExceptionSite?.entityName, entity.displayName)
        XCTAssertEqual(resultScriptURLOnExceptionSite?.category, tracker.category)
        XCTAssertEqual(resultScriptURLOnExceptionSite?.prevalence, tracker.prevalence)
    }

    func testWhenTrackerIsOnAssociatedPageThenItIsNotBlocked() {

        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com", "example.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc",
                                        "example.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [], tld: tld)

        let result = resolver.trackerFromUrl("https://tracker.com/img/1.png",
                                             pageUrlString: "https://example.com",
                                             resourceType: "image",
                                             potentiallyBlocked: true)

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked)
        XCTAssertEqual(result?.state, BlockingState.allowed(reason: .ownedByFirstParty))
    }

    func testWhenTrackerIsACnameThenItIsReportedAsSuch() {

        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let entity = Entity(displayName: "Tracker Inc company",
                            domains: ["tracker.com"],
                            prevalence: 0.1)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": entity],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: ["cnamed.com": "tracker.com"])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [], tld: tld)

        let result = resolver.trackerFromUrl("https://cnamed.com/img/1.png", pageUrlString: "https://example.com", resourceType: "image", potentiallyBlocked: true)

        XCTAssertNotNil(result)
        XCTAssert(result?.isBlocked ?? false)
        XCTAssertEqual(result?.state, BlockingState.blocked)
        XCTAssertEqual(result?.ownerName, tracker.owner?.name)
        XCTAssertEqual(result?.entityName, entity.displayName)
        XCTAssertEqual(result?.category, tracker.category)
        XCTAssertEqual(result?.prevalence, tracker.prevalence)
    }

    func testWhenTrackerIsACnameForAnotherTrackerThenOriginalOneIsReturned() {

        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let another = KnownTracker(domain: "another.com",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Another Inc",
                                                             displayName: "Another Inc company",
                                                             ownedBy: nil),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let trackerEntity = Entity(displayName: "Tracker Inc company",
                                   domains: ["tracker.com"],
                                   prevalence: 0.1)

        let anotherEntity = Entity(displayName: "Another Inc company",
                                   domains: ["another.com"],
                                   prevalence: 0.1)

        let tds = TrackerData(trackers: ["tracker.com": tracker,
                                         "another.com": another],
                              entities: ["Tracker Inc": trackerEntity,
                                         "Another Inc": anotherEntity],
                              domains: ["tracker.com": "Tracker Inc",
                                        "another.com": "Another Inc."],
                              cnames: ["sub.another.com": "tracker.com"])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [], tld: tld)

        let result = resolver.trackerFromUrl("https://sub.another.com/img/1.png", pageUrlString: "https://example.com", resourceType: "image", potentiallyBlocked: true)

        XCTAssertNotNil(result)
        XCTAssert(result?.isBlocked ?? false)
        XCTAssertEqual(result?.state, BlockingState.blocked)
        XCTAssertEqual(result?.ownerName, another.owner?.name)
        XCTAssertEqual(result?.entityName, anotherEntity.displayName)
        XCTAssertEqual(result?.category, another.category)
        XCTAssertEqual(result?.prevalence, another.prevalence)
    }

    func testWhenTrackerIsOnUnprotectedSiteItIsNotBlocked() {
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: ["example.com"], tempList: [], tld: tld)

        let result = resolver.trackerFromUrl("https://tracker.com/img/1.png",
                                             pageUrlString: "https://example.com",
                                             resourceType: "image",
                                             potentiallyBlocked: true)

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked)
        XCTAssertEqual(result?.state, BlockingState.allowed(reason: .protectionDisabled))
    }

    func testWhenTrackerIsOnTempListItIsNotBlocked() {
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: ["example.com"], tld: tld)

        let result = resolver.trackerFromUrl("https://tracker.com/img/1.png",
                                             pageUrlString: "https://example.com",
                                             resourceType: "image",
                                             potentiallyBlocked: true)

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked)
        XCTAssertEqual(result?.state, BlockingState.allowed(reason: .protectionDisabled))
    }

    // This also covers the scenario when tracker is on domain with disabled contentBlocking feature (through temporaryUnprotectedDomains inside ContentBlockerRulesUserScript)
    func testWhenTrackerIsOnDomainWithDisabledContentBlockingFeatureItIsNotBlocked() {
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: ["example.com"], tld: tld)

        let result = resolver.trackerFromUrl("https://tracker.com/img/1.png",
                                             pageUrlString: "https://example.com",
                                             resourceType: "image",
                                             potentiallyBlocked: true)

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked)
        XCTAssertEqual(result?.state, BlockingState.allowed(reason: .protectionDisabled))
    }

    func testWhenTrackerIsFirstPartyThenItIsNotNotBlocked() { //
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: ["example.com"], tld: tld)

        let result = resolver.trackerFromUrl("https://tracker.com/img/1.png",
                                             pageUrlString: "https://tracker.com",
                                             resourceType: "image",
                                             potentiallyBlocked: true)

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isBlocked)
        XCTAssertEqual(result?.state, BlockingState.allowed(reason: .ownedByFirstParty))
    }

    func testWhenRequestIsThirdPartyNonTrackerThenItIsIgnored() { // Note: User script has additional logic regarding this case
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: ["example.com"], tld: tld)

        let result = resolver.trackerFromUrl("https://other.com/img/1.png",
                                             pageUrlString: "https://example.com",
                                             resourceType: "image",
                                             potentiallyBlocked: true)

        XCTAssertNil(result)
    }

    func testWhenRequestIsFirstPartyNonTrackerThenItIsIgnored() {
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [], tld: tld)

        let result = resolver.trackerFromUrl("https://example.com/img/1.png",
                                             pageUrlString: "https://example.com",
                                             resourceType: "image",
                                             potentiallyBlocked: true)

        XCTAssertNil(result)
    }

    func testWhenRequestIsSameEntityNonTrackerThenItIsIgnored() {
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .trackerInc,
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": Entity(displayName: "Tracker Inc company",
                                                               domains: ["tracker.com"],
                                                               prevalence: 0.1),
                                         "Other Inc": Entity(displayName: "Other Inc company",
                                                                          domains: ["other.com", "example.com"],
                                                                          prevalence: 0.1)],
                              domains: ["tracker.com": "Tracker Inc",
                                        "other.com": "Other Inc",
                                        "example.com": "Other Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [], tld: tld)

        let result = resolver.trackerFromUrl("https://other.com/img/1.png",
                                             pageUrlString: "https://example.com",
                                             resourceType: "image",
                                             potentiallyBlocked: true)

        XCTAssertNil(result)
    }

    // MARK: - Owned By

    func testWhenTrackerIsOwnedByAnotherCompanyThenOwnerNameIsParentOwner() throws {
        // GIVEN
        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: .init(name: "Tracker Inc", displayName: "Tracker Inc company", ownedBy: "Parent Owner Tracker"),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: ["Advertising"],
                                   rules: nil)

        let entity = Entity(displayName: "Trackr Inc company",
                            domains: ["tracker.com"],
                            prevalence: 0.1)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker Inc": entity],
                              domains: ["tracker.com": "Tracker Inc"],
                              cnames: [:])

        let resolver = TrackerResolver(tds: tds, unprotectedSites: [], tempList: [], tld: tld)

        // WHEN
        let result = try XCTUnwrap(resolver.trackerFromUrl("https://tracker.com/img/1.png", pageUrlString: "https://example.com", resourceType: "image", potentiallyBlocked: true))

        // THEN
        XCTAssert(result.isBlocked)
        XCTAssertEqual(result.state, .blocked)
        XCTAssertEqual(result.ownerName, tracker.owner?.ownedBy)
        XCTAssertEqual(result.entityName, entity.displayName)
        XCTAssertEqual(result.category, tracker.category)
        XCTAssertEqual(result.prevalence, tracker.prevalence)
    }

}

private extension KnownTracker.Owner {
    static let trackerInc = KnownTracker.Owner(name: "Tracker Inc", displayName: "Tracker Inc company", ownedBy: nil)
}
