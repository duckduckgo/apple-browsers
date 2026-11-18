//
//  NativeWireGuardPolicyTests.swift
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

#if DEBUG && (os(macOS) || os(iOS))
import Foundation
import VPN
import XCTest
@testable import VPNDebug

final class NativeWireGuardPolicyTests: XCTestCase {
    func testIPv4SourceAndDestinationUseDifferentAddresses() throws {
        let range = try XCTUnwrap(IPAddressRange(from: "10.20.30.0/24"))
        var packet = Data(repeating: 0, count: 20)
        packet[0] = 0x45
        packet.replaceSubrange(12..<16, with: [10, 20, 30, 255])
        packet.replaceSubrange(16..<20, with: [10, 20, 31, 0])
        XCTAssertTrue(NativeWireGuardAdapter.permits(packet, source: true, ranges: [range]))
        XCTAssertFalse(NativeWireGuardAdapter.permits(packet, source: false, ranges: [range]))
        let host = try XCTUnwrap(IPAddressRange(from: "10.20.30.254/32"))
        XCTAssertFalse(NativeWireGuardAdapter.permits(packet, source: true, ranges: [host]))
    }

    func testIPv6NonByteAlignedPrefixAndAddressFamily() throws {
        let range = try XCTUnwrap(IPAddressRange(from: "2001:db8::/33"))
        let ipv4 = try XCTUnwrap(IPAddressRange(from: "0.0.0.0/0"))
        var packet = Data(repeating: 0, count: 40)
        packet[0] = 0x60
        packet.replaceSubrange(8..<13, with: [0x20, 0x01, 0x0d, 0xb8, 0x7f])
        packet.replaceSubrange(24..<29, with: [0x20, 0x01, 0x0d, 0xb8, 0x80])
        XCTAssertTrue(NativeWireGuardAdapter.permits(packet, source: true, ranges: [range]))
        XCTAssertFalse(NativeWireGuardAdapter.permits(packet, source: false, ranges: [range]))
        XCTAssertFalse(NativeWireGuardAdapter.permits(packet, source: true, ranges: [ipv4]))
    }

    func testMissingPolicyAndTruncatedPacketsAreRejected() throws {
        let range = try XCTUnwrap(IPAddressRange(from: "0.0.0.0/0"))
        let packet = Data([0x45]) + Data(repeating: 0, count: 19)
        XCTAssertFalse(NativeWireGuardAdapter.permits(packet, source: true, ranges: []))
        XCTAssertFalse(NativeWireGuardAdapter.permits(Data(), source: false, ranges: [range]))
        XCTAssertFalse(NativeWireGuardAdapter.permits(Data([0x45]), source: true, ranges: [range]))
        XCTAssertFalse(NativeWireGuardAdapter.permits(Data([0x70]), source: true, ranges: [range]))
    }
}
#endif
