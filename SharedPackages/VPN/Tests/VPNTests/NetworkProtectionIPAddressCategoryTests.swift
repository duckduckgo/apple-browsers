//
//  NetworkProtectionIPAddressCategoryTests.swift
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

final class NetworkProtectionIPAddressCategoryTests: XCTestCase {

    func testIPv4Categories() {
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("8.8.8.8"), .ipv4Public)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("10.0.0.1"), .ipv4Private10)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("172.16.0.1"), .ipv4Private172)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("192.168.0.1"), .ipv4Private192)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("100.64.0.1"), .ipv4CGNAT)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("169.254.1.1"), .ipv4LinkLocal)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("127.0.0.1"), .ipv4Loopback)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("224.0.0.1"), .ipv4Multicast)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("240.0.0.1"), .ipv4Reserved)
    }

    func testIPv6Categories() {
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("2001:4860:4860::8888"), .ipv6Public)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("fd00::1"), .ipv6UniqueLocal)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("fc00::1"), .ipv6UniqueLocal)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("fe80::1"), .ipv6LinkLocal)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("::1"), .ipv6Loopback)
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("ff02::1"), .ipv6Multicast)
    }

    func testUnknownCategory() {
        XCTAssertEqual(NetworkProtectionIPAddressClassifier.classify("not-an-ip"), .unknown)
    }

    func testUniqueCategories() {
        XCTAssertEqual(
            NetworkProtectionIPAddressClassifier.uniqueCategories(for: ["8.8.8.8", "1.1.1.1", "10.0.0.1"]),
            [.ipv4Private10, .ipv4Public]
        )
    }
}
