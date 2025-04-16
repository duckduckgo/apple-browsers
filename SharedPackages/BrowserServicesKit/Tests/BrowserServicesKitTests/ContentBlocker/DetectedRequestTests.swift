//
//  DetectedRequestTests.swift
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

import XCTest
import TrackerRadarKit
import BrowserServicesKit
@testable import ContentBlocking

final class DetectedRequestTests: XCTestCase {

    private struct Constants {
        static let aUrl = "www.example.com"
        static let anotherUrl = "www.anotherurl.com"
        static let aParentDomain = "adomain.com"
        static let anotherParentDomain = "anotherdomain.com"
    }

    func testWhenTrackerRequestsHaveSameEntityThenHashMatchesAndIsEqualsIsTrue() {
        let entity1 = Entity(displayName: "Entity", domains: nil, prevalence: nil)
        let entity2 = Entity(displayName: "Entity", domains: [ Constants.aParentDomain ], prevalence: 1)

        let tracker1 = DetectedRequest(url: Constants.aUrl, eTLDplus1: nil, knownTracker: nil, entity: entity1, state: .blocked, pageUrl: "")
        let tracker2 = DetectedRequest(url: Constants.anotherUrl, eTLDplus1: nil, knownTracker: nil, entity: entity2, state: .blocked, pageUrl: "")

        XCTAssertEqual(tracker1.hashValue, tracker2.hashValue)
        XCTAssertEqual(tracker1, tracker2)
    }

    func testWhenTrackerRequestsHaveSameEntityButDifferentBlockedStatusThenHashIsNotEqualAndIsEqualsIsFalse() {
        let entity = Entity(displayName: "Entity", domains: nil, prevalence: nil)

        let tracker1 = DetectedRequest(url: Constants.aUrl, eTLDplus1: nil, knownTracker: nil, entity: entity, state: .blocked, pageUrl: "")
        let tracker2 = DetectedRequest(url: Constants.anotherUrl, eTLDplus1: nil, knownTracker: nil, entity: entity, state: .allowed(reason: .ruleException), pageUrl: "")

        XCTAssertNotEqual(tracker1.hashValue, tracker2.hashValue)
        XCTAssertNotEqual(tracker1, tracker2)
    }

}
