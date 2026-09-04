//
//  NetworkProtectionServerInfoTests.swift
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
import XCTest
@testable import VPN

final class NetworkProtectionServerInfoTests: XCTestCase {

    func testWhenGettingServerLocation_AndAttributesExist_notUS_ThenServerLocationIsCityCountry() {
        let serverInfo = NetworkProtectionServerInfo(name: "Server Name",
                                                     publicKey: "",
                                                     hostNames: [],
                                                     ips: [],
                                                     internalIP: AnyIPAddress("10.11.12.1")!,
                                                     port: 42,
                                                     attributes: .init(city: "Amsterdam", country: "nl", state: "na"))

        XCTAssertEqual(serverInfo.serverLocation, "Amsterdam, Netherlands")
    }

    func testWhenGettingServerLocation_AndAttributesExist_isUS_ThenServerLocationIsCityState() {
        let serverInfo = NetworkProtectionServerInfo(name: "Server Name",
                                                     publicKey: "",
                                                     hostNames: [],
                                                     ips: [],
                                                     internalIP: AnyIPAddress("10.11.12.1")!,
                                                     port: 42,
                                                     attributes: .init(city: "New York", country: "us", state: "ny"))

        XCTAssertEqual(serverInfo.serverLocation, "New York, United States")
    }

    func testWhenDecodingJSON_AndPortsArrayIsPresent_ThenPortsIsDecoded() throws {
        let json = """
        {
            "name": "egress.usw.1",
            "publicKey": "R/BMR6Rr5rzvp7vSIWdAtgAmOLK9m7CqTcDynblM3Us=",
            "hostnames": [],
            "ips": ["162.245.204.101"],
            "internalIp": "10.11.12.1",
            "port": 443,
            "ports": [443, 51820],
            "attributes": {
                "city": "El Segundo",
                "country": "us",
                "latitude": 33.9192,
                "longitude": -118.4165,
                "region": "North America",
                "state": "ca",
                "tzOffset": -28800
            }
        }
        """.data(using: .utf8)!

        let serverInfo = try JSONDecoder().decode(NetworkProtectionServerInfo.self, from: json)

        XCTAssertEqual(serverInfo.port, 443)
        XCTAssertEqual(serverInfo.ports, [443, 51820])
    }

    func testWhenDecodingJSON_AndPortsArrayIsAbsent_ThenPortsIsNil() throws {
        let json = """
        {
            "name": "egress.usw.1",
            "publicKey": "R/BMR6Rr5rzvp7vSIWdAtgAmOLK9m7CqTcDynblM3Us=",
            "hostnames": [],
            "ips": ["162.245.204.101"],
            "internalIp": "10.11.12.1",
            "port": 443,
            "attributes": {
                "city": "El Segundo",
                "country": "us",
                "latitude": 33.9192,
                "longitude": -118.4165,
                "region": "North America",
                "state": "ca",
                "tzOffset": -28800
            }
        }
        """.data(using: .utf8)!

        let serverInfo = try JSONDecoder().decode(NetworkProtectionServerInfo.self, from: json)

        XCTAssertEqual(serverInfo.name, "egress.usw.1")
        XCTAssertEqual(serverInfo.port, 443)
        XCTAssertNil(serverInfo.ports)
        XCTAssertEqual(serverInfo.serverLocation, "El Segundo, United States")
    }

}
