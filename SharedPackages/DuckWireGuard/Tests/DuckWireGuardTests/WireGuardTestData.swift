//
//  WireGuardTestData.swift
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

enum WireGuardTestData {
    enum HexDecodingError: Error {
        case oddHexLength
        case invalidHexByte(offset: Int)
    }

    static func handshakeJSON() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "handshake", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func handshakeVectors() throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: handshakeJSON()) as? [[String: Any]])
    }

    static func hexBytes(_ hex: String) throws -> Data {
        let characters = Array(hex)
        guard characters.count.isMultiple(of: 2) else { throw HexDecodingError.oddHexLength }
        var result = Data()
        for offset in stride(from: 0, to: characters.count, by: 2) {
            guard let high = characters[offset].hexDigitValue,
                  let low = characters[offset + 1].hexDigitValue else {
                throw HexDecodingError.invalidHexByte(offset: offset / 2)
            }
            result.append(UInt8(high << 4 | low))
        }
        return result
    }
}
