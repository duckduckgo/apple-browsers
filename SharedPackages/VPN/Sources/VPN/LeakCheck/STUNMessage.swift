//
//  STUNMessage.swift
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

enum STUNMessage {

    static let magicCookie: UInt32 = 0x2112A442
    static let magicCookieBytes: [UInt8] = [0x21, 0x12, 0xA4, 0x42]
    static let bindingRequestType: UInt16 = 0x0001
    static let bindingResponseType: UInt16 = 0x0101
    static let xorMappedAddressAttribute: UInt16 = 0x0020

    enum Family: UInt8 {
        case ipv4 = 0x01
        case ipv6 = 0x02
    }

    static func bindingRequest(transactionID: Data = randomTransactionID()) -> Data {
        precondition(transactionID.count == 12)
        var data = Data(capacity: 20)
        data.append(UInt8(bindingRequestType >> 8))
        data.append(UInt8(bindingRequestType & 0xFF))
        data.append(0x00)
        data.append(0x00)
        data.append(contentsOf: magicCookieBytes)
        data.append(transactionID)
        return data
    }

    static func randomTransactionID() -> Data {
        var bytes = [UInt8](repeating: 0, count: 12)
        for i in 0..<bytes.count {
            bytes[i] = UInt8.random(in: 0...255)
        }
        return Data(bytes)
    }
}
