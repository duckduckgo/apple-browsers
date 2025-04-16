//
//  EndpointTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Network
@testable import NetworkProtection

final class EndpointTests: XCTestCase {

    func testEndpointWithHostName_ShouldIncludePort() {
        let endpoint = self.endpointWithHostName()
        XCTAssertEqual(endpoint.description, "https://duckduckgo.com:443")
    }

    func testEndpointWithIPv4Address_ShouldIncludePort() {
        let endpoint = self.endpointWithIPv4()
        XCTAssertEqual(endpoint.description, "52.250.42.157:443")
    }

    func testEndpointWithIPv6Address_ShouldIncludePort() {
        let endpoint = self.endpointWithIPv6()
        XCTAssertEqual(endpoint.description, "[2001:db8:85a3::8a2e:370:7334]:443")
    }

    func testParsingEndpointFromIPv4Address() {
        let address = "52.250.42.157:443"
        let endpoint = Endpoint(from: address)!
        XCTAssertEqual(endpoint.description, address)
    }

    func testParsingEndpointFromIPv6Address() {
        let address = "[2001:0db8:85a3:0000:0000:8a2e:0370]:443"
        let endpoint = Endpoint(from: address)!
        XCTAssertEqual(endpoint.description, "2001:0db8:85a3:0000:0000:8a2e:0370:443")
    }

    private func endpointWithHostName() -> Endpoint {
        let host = NWEndpoint.Host.name("https://duckduckgo.com", nil)
        let port = NWEndpoint.Port.https
        return Endpoint(host: host, port: port)
    }

    private func endpointWithIPv4() -> Endpoint {
        let address = IPv4Address("52.250.42.157")!
        let host = NWEndpoint.Host.ipv4(address)
        let port = NWEndpoint.Port.https
        return Endpoint(host: host, port: port)
    }

    private func endpointWithIPv6() -> Endpoint {
        let address = IPv6Address("2001:0db8:85a3:0000:0000:8a2e:0370:7334")!
        let host = NWEndpoint.Host.ipv6(address)
        let port = NWEndpoint.Port.https
        return Endpoint(host: host, port: port)
    }

}
