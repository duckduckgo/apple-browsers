//
//  EndpointPortSelectionTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
@testable import VPN

final class EndpointPortSelectionTests: XCTestCase {

    func testFirstRespondingCandidateWins_WhenItIsNotTheDefault() {
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820, 8080],
            currentPort: 443,
            serverDefaultPort: 443,
            responding: [51820]
        )

        XCTAssertEqual(decision.port, 51820)
        XCTAssertEqual(decision.automaticPort, 51820)
        XCTAssertEqual(decision.rememberedPort, 51820)
    }

    func testServerDefaultWins_WhenItRespondsFirst() {
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 51820,
            serverDefaultPort: 443,
            responding: [443, 51820]
        )

        XCTAssertEqual(decision.port, 443)
        XCTAssertNil(decision.automaticPort)
        XCTAssertEqual(decision.rememberedPort, 443)
    }

    func testNothingResponds_CurrentPortAdvertisedAndNotTheDefault_KeepsCurrentPortAsAutomaticPort() {
        // Nothing answered, but currentPort (51820) still advertised by the server, so the next
        // regeneration must keep using it rather than falling back to the server default.
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 51820,
            serverDefaultPort: 443,
            responding: []
        )

        XCTAssertEqual(decision.port, 51820)
        XCTAssertEqual(decision.automaticPort, 51820)
        XCTAssertNil(decision.rememberedPort)
    }

    func testNothingResponds_CurrentPortIsTheDefault_AutomaticPortStaysNil() {
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 443,
            serverDefaultPort: 443,
            responding: []
        )

        XCTAssertEqual(decision.port, 443)
        XCTAssertNil(decision.automaticPort)
        XCTAssertNil(decision.rememberedPort)
    }

    func testNothingResponds_CurrentPortNotAdvertised_FallsBackToServerDefault() {
        // currentPort (12345) is stale, carried over from a different server; it must not be forced
        // on a server that never advertised it.
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 12345,
            serverDefaultPort: 443,
            responding: []
        )

        XCTAssertEqual(decision.port, 443)
        XCTAssertNil(decision.automaticPort)
        XCTAssertNil(decision.rememberedPort)
    }

    func testRememberedPortFirstInCandidates_WinsOverDefault() {
        // The remembered port (51820) is ordered first by endpointPortCandidates(preferring:), so it wins
        // even though the server default (443) also answered.
        let decision = EndpointPortSelection.decide(
            candidates: [51820, 443],
            currentPort: 443,
            serverDefaultPort: 443,
            responding: [443, 51820]
        )

        XCTAssertEqual(decision.port, 51820)
        XCTAssertEqual(decision.automaticPort, 51820)
        XCTAssertEqual(decision.rememberedPort, 51820)
    }

    func testRespondingPortsOutsideCandidates_AreIgnored() {
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 443,
            serverDefaultPort: 443,
            responding: [9999]
        )

        XCTAssertEqual(decision.port, 443)
        XCTAssertNil(decision.automaticPort)
        XCTAssertNil(decision.rememberedPort)
    }

}
