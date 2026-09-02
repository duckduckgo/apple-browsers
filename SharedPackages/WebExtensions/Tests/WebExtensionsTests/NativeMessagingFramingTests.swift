//
//  NativeMessagingFramingTests.swift
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

@testable import WebExtensions

final class NativeMessagingFramingTests: XCTestCase {

    func testWhenMessageIsEncoded_ThenPrefixHoldsThePayloadLength() throws {
        let frame = try NativeMessagingFraming.encode(["command": "biometricUnlock"])

        let prefix = frame.prefix(NativeMessagingFraming.prefixSize)
        let length = try NativeMessagingFraming.decodeLength(Data(prefix))

        XCTAssertEqual(length, frame.count - NativeMessagingFraming.prefixSize)
    }

    func testWhenFrameIsDecoded_ThenItMatchesTheOriginalMessage() throws {
        let message: [String: Any] = ["command": "biometricUnlock", "messageId": 7]

        let frame = try NativeMessagingFraming.encode(message)
        let payload = frame.dropFirst(NativeMessagingFraming.prefixSize)
        let decoded = try NativeMessagingFraming.decodePayload(Data(payload))

        let dictionary = try XCTUnwrap(decoded as? [String: Any])
        XCTAssertEqual(dictionary["command"] as? String, "biometricUnlock")
        XCTAssertEqual(dictionary["messageId"] as? Int, 7)
    }

    func testWhenMessageIsNotJSON_ThenEncodeThrows() {
        XCTAssertThrowsError(try NativeMessagingFraming.encode(Date())) { error in
            XCTAssertEqual(error as? NativeMessagingFramingError, .invalidJSON)
        }
    }

    func testWhenLengthExceedsTheMaximum_ThenDecodeLengthThrows() {
        var prefix = Data()
        withUnsafeBytes(of: UInt32(NativeMessagingFraming.maximumMessageSize + 1)) {
            prefix.append(contentsOf: $0)
        }

        XCTAssertThrowsError(try NativeMessagingFraming.decodeLength(prefix)) { error in
            XCTAssertEqual(error as? NativeMessagingFramingError,
                           .messageTooLarge(length: NativeMessagingFraming.maximumMessageSize + 1))
        }
    }

    func testWhenPayloadIsEmpty_ThenDecodePayloadThrows() {
        XCTAssertThrowsError(try NativeMessagingFraming.decodePayload(Data()))
    }
}
