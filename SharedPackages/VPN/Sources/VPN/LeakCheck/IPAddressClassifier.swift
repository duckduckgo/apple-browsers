//
//  IPAddressClassifier.swift
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
import Network

public enum LeakIPType: String, Codable, CaseIterable {
    case `public`
    case `private`
    case unknown
}

public enum IPAddressClassifier {

    public static func classify(_ address: String) -> LeakIPType {
        if let v4 = IPv4Address(address) {
            return classifyIPv4(v4)
        }
        if let v6 = IPv6Address(address) {
            return classifyIPv6(v6)
        }
        return .unknown
    }

    private static func classifyIPv4(_ address: IPv4Address) -> LeakIPType {
        let bytes = [UInt8](address.rawValue)
        guard bytes.count == 4 else { return .unknown }
        let (b0, b1) = (bytes[0], bytes[1])

        if b0 == 10 { return .private }
        if b0 == 172 && (16...31).contains(b1) { return .private }
        if b0 == 192 && b1 == 168 { return .private }

        if b0 == 127 { return .unknown }
        if b0 == 169 && b1 == 254 { return .unknown }
        if b0 == 100 && (64...127).contains(b1) { return .unknown }
        if b0 >= 224 { return .unknown }
        if b0 == 0 { return .unknown }

        return .public
    }

    private static func classifyIPv6(_ address: IPv6Address) -> LeakIPType {
        let bytes = [UInt8](address.rawValue)
        guard bytes.count == 16 else { return .unknown }

        if bytes == Array(repeating: 0, count: 15) + [1] { return .unknown }
        if bytes == Array(repeating: 0, count: 16) { return .unknown }
        if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return .unknown }
        if bytes[0] == 0xfc || bytes[0] == 0xfd { return .private }
        if bytes[0] == 0xff { return .unknown }

        return .public
    }
}
