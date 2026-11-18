//
//  BLAKE2sTests.swift
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
@testable import DuckWireGuard

final class BLAKE2sTests: XCTestCase {
    // RFC 7693 parameters; independently generated using Python hashlib.blake2s.
    private let vectors: [(length: Int, digest: String, mac: String)] = [
        (0, "69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9", "9536f9b267655743dee97b8a670f9f53"),
        (63, "e57cb79487dd57902432b250733813bd96a84efce59f650fac26e6696aefafc3", "ece382a8bd5018f1de5da44b72cea75b"),
        (64, "56f34e8b96557e90c1f24b52d0c89d51086acf1b00f634cf1dde9233b8eaaa3e", "f1efa90d2547036841ecd3627fafbc36"),
        (65, "1b53ee94aaf34e4b159d48de352c7f0661d0a40edff95a0b1639b4090e974472", "811ff8686d23a435ecbd0bdafcd27b1b"),
        (128, "1fa877de67259d19863a2a34bcc6962a2b25fcbf5cbecd7ede8f1fa36688a796", "8c09f698d03eaf88abf69f8147865ef6"),
        (255, "f03f5789d3336b80d002d59fdf918bdb775b00956ed5528e86aa994acb38fe2d", "cd075928ab7e6883e697fe7fd3ac43ee")
    ]

    func testUnkeyedDigestsAtBlockBoundaries() throws {
        for (length, digest, _) in vectors {
            let input = Data((0..<length).map(UInt8.init))
            XCTAssertEqual(BLAKE2s.hash(input), try bytes(digest), "length \(length)")
        }
    }

    func testKeyedSixteenByteDigestsAtBlockBoundaries() throws {
        let key = Data((0..<32).map(UInt8.init))
        for (length, _, mac) in vectors {
            let input = Data((0..<length).map(UInt8.init))
            XCTAssertEqual(BLAKE2s.hash(input, key: key, outputLength: 16), try bytes(mac), "length \(length)")
        }
    }

    func testRFC7693ABCExample() throws {
        // RFC 7693 appendix B.
        XCTAssertEqual(BLAKE2s.hash(Data("abc".utf8)),
                       try bytes("508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982"))
    }

    func testCookieSizedKeysAgainstIndependentVectors() throws {
        let key = Data((0..<16).map(UInt8.init))
        let expected = [
            (0, "af4e5d3bb230e9ff9096ca6f7c501f76"),
            (64, "dd55c51c98f8ab96ed272882941f0b6a"),
            (65, "9018c671bb7e94a6d540a91765bbecad")
        ]
        for (length, digest) in expected {
            let input = Data((0..<length).map(UInt8.init))
            XCTAssertEqual(BLAKE2s.hash(input, key: key, outputLength: 16), try bytes(digest), "length \(length)")
        }
    }

    func testKeyedEmptyMessageFinalizesTheCompleteKeyBlock() throws {
        let key = Data((0..<32).map(UInt8.init))
        XCTAssertEqual(BLAKE2s.hash(Data(), key: key),
                       try bytes("48a8997da407876b3d79c0d92325ad3b89cbb754d86ab71aee047ad345fd2c49"))
    }

    private func bytes(_ hex: String) throws -> Data {
        try WireGuardTestData.hexBytes(hex)
    }
}
