//
//  NetworkProtectionServerInfoEndpointPortCandidatesTests.swift
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

import Foundation
import XCTest
@testable import VPN

final class NetworkProtectionServerInfoEndpointPortCandidatesTests: XCTestCase {

    private func makeServerInfo(port: UInt16, ports: [UInt16]? = nil) -> NetworkProtectionServerInfo {
        NetworkProtectionServerInfo(name: "Server Name",
                                    publicKey: "",
                                    hostNames: [],
                                    ips: [],
                                    internalIP: AnyIPAddress("10.11.12.1")!,
                                    port: port,
                                    ports: ports,
                                    attributes: .init(city: "City", country: "Country", state: "State"))
    }

    func testWhenPortsIsNil_AndRememberedPortIsNil_ThenCandidatesIsJustPort() {
        let serverInfo = makeServerInfo(port: 443)

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: nil), [443])
    }

    func testWhenPortsIsNil_AndRememberedPortEqualsPort_ThenCandidatesIsJustPort() {
        let serverInfo = makeServerInfo(port: 443)

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: 443), [443])
    }

    func testWhenPortsIsNil_AndRememberedPortDiffersFromPort_ThenRememberedPortIsDroppedAsNotAdvertised() {
        let serverInfo = makeServerInfo(port: 443)

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: 51820), [443])
    }

    func testWhenPortsIncludesPort_AndRememberedPortIsNil_ThenPortComesFirstFollowedByRemainingPorts() {
        let serverInfo = makeServerInfo(port: 443, ports: [443, 51820])

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: nil), [443, 51820])
    }

    func testWhenPortsIncludesPort_AndRememberedPortIsAdvertised_ThenRememberedPortComesFirst() {
        let serverInfo = makeServerInfo(port: 443, ports: [443, 51820])

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: 51820), [51820, 443])
    }

    func testWhenPortsIncludesPort_AndRememberedPortIsNotAdvertised_ThenRememberedPortIsDropped() {
        let serverInfo = makeServerInfo(port: 443, ports: [443, 51820])

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: 8443), [443, 51820])
    }

    func testWhenPortsDoesNotIncludePort_AndRememberedPortIsNil_ThenPortStillComesFirst() {
        let serverInfo = makeServerInfo(port: 443, ports: [51820, 4500])

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: nil), [443, 51820, 4500])
    }

    func testWhenPortsDoesNotIncludePort_AndRememberedPortIsAdvertised_ThenRememberedPortComesFirst() {
        let serverInfo = makeServerInfo(port: 443, ports: [51820, 4500])

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: 4500), [4500, 443, 51820])
    }

    func testWhenPortsHasDuplicates_ThenCandidatesAreDeduplicated() {
        let serverInfo = makeServerInfo(port: 443, ports: [443, 443, 51820, 51820])

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: nil), [443, 51820])
    }

    func testWhenRememberedPortIsZero_ThenItIsSkippedAsAnInvalidPort() {
        let serverInfo = makeServerInfo(port: 443, ports: [0, 51820])

        XCTAssertEqual(serverInfo.endpointPortCandidates(preferring: 0), [443, 51820])
    }

}
