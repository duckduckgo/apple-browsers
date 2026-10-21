//
//  IPAddressClassifierTests.swift
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

final class IPAddressClassifierTests: XCTestCase {

    func testPrivateIPv4_10Range() {
        XCTAssertEqual(IPAddressClassifier.classify("10.0.0.1"), .private)
        XCTAssertEqual(IPAddressClassifier.classify("10.255.255.255"), .private)
    }

    func testPrivateIPv4_172Range() {
        XCTAssertEqual(IPAddressClassifier.classify("172.16.0.1"), .private)
        XCTAssertEqual(IPAddressClassifier.classify("172.31.255.254"), .private)
        XCTAssertEqual(IPAddressClassifier.classify("172.15.0.1"), .public)
        XCTAssertEqual(IPAddressClassifier.classify("172.32.0.1"), .public)
    }

    func testPrivateIPv4_192Range() {
        XCTAssertEqual(IPAddressClassifier.classify("192.168.0.1"), .private)
        XCTAssertEqual(IPAddressClassifier.classify("192.169.0.1"), .public)
    }

    func testPublicIPv4() {
        XCTAssertEqual(IPAddressClassifier.classify("8.8.8.8"), .public)
        XCTAssertEqual(IPAddressClassifier.classify("1.1.1.1"), .public)
    }

    func testUnknownIPv4_CGNAT() {
        XCTAssertEqual(IPAddressClassifier.classify("100.64.0.1"), .unknown)
        XCTAssertEqual(IPAddressClassifier.classify("100.127.255.254"), .unknown)
    }

    func testUnknownIPv4_LinkLocal() {
        XCTAssertEqual(IPAddressClassifier.classify("169.254.1.1"), .unknown)
    }

    func testUnknownIPv4_Loopback() {
        XCTAssertEqual(IPAddressClassifier.classify("127.0.0.1"), .unknown)
    }

    func testPublicIPv6() {
        XCTAssertEqual(IPAddressClassifier.classify("2001:4860:4860::8888"), .public)
    }

    func testUnknownIPv6_LinkLocal() {
        XCTAssertEqual(IPAddressClassifier.classify("fe80::1"), .unknown)
    }

    func testUnknownIPv6_Loopback() {
        XCTAssertEqual(IPAddressClassifier.classify("::1"), .unknown)
    }

    func testPrivateIPv6_UniqueLocal() {
        XCTAssertEqual(IPAddressClassifier.classify("fd00::1"), .private)
        XCTAssertEqual(IPAddressClassifier.classify("fc00::1"), .private)
    }

    func testMalformedInput() {
        XCTAssertEqual(IPAddressClassifier.classify("not-an-ip"), .unknown)
        XCTAssertEqual(IPAddressClassifier.classify(""), .unknown)
    }
}
