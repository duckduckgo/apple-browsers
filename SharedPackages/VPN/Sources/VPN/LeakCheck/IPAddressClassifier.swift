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
        if address.isLoopback || address.isLinkLocal || address.isMulticast {
            return .unknown
        }

        let bytes = [UInt8](address.rawValue)
        guard bytes.count == 4 else { return .unknown }
        let (b0, b1) = (bytes[0], bytes[1])

        // RFC1918 private ranges
        if b0 == 10 { return .private }
        if b0 == 172 && (16...31).contains(b1) { return .private }
        if b0 == 192 && b1 == 168 { return .private }

        // 0.0.0.0/8, CGNAT 100.64.0.0/10, class E 240.0.0.0/4
        if b0 == 0 || b0 >= 240 { return .unknown }
        if b0 == 100 && (64...127).contains(b1) { return .unknown }

        return .public
    }

    private static func classifyIPv6(_ address: IPv6Address) -> LeakIPType {
        if address.isAny || address.isLoopback || address.isLinkLocal || address.isMulticast {
            return .unknown
        }

        if address.isUniqueLocal {
            return .private
        }

        return .public
    }
}
