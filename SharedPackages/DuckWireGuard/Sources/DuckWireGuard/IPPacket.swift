//
//  IPPacket.swift
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

/// Reads the inner length so callers can distinguish IP bytes from WireGuard padding.
/// Authentication, routing and outgoing packet-size policy remain with the caller.
enum IPPacket {
    private typealias Failure = WireGuardPeer.Error

    // [RFC 791 §3.1](https://www.rfc-editor.org/rfc/rfc791.html#section-3.1).
    private static let ipv4MinimumHeaderLength = 20
    // [RFC 8200 §3](https://www.rfc-editor.org/rfc/rfc8200.html#section-3).
    private static let ipv6HeaderLength = 40

    static func length(of packet: Data) throws -> Int {
        guard let first = packet.first else { throw Failure.invalidPacket }
        let start = packet.startIndex
        switch first >> 4 {
        case 4:
            guard packet.count >= ipv4MinimumHeaderLength else { throw Failure.invalidPacket }
            let headerLength = Int(first & 0x0f) * 4
            let length = Int(packet[start + 2]) << 8 | Int(packet[start + 3])
            guard headerLength >= ipv4MinimumHeaderLength, length >= headerLength, length <= packet.count else { throw Failure.invalidPacket }
            return length
        case 6:
            guard packet.count >= ipv6HeaderLength else { throw Failure.invalidPacket }
            let length = ipv6HeaderLength + (Int(packet[start + 4]) << 8 | Int(packet[start + 5]))
            guard length <= packet.count else { throw Failure.invalidPacket }
            return length
        default:
            throw Failure.invalidPacket
        }
    }
}
