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

    static let magicCookieBytes: [UInt8] = [0x21, 0x12, 0xA4, 0x42]
    static let bindingRequestType: UInt16 = 0x0001
    static let bindingResponseType: UInt16 = 0x0101
    static let xorMappedAddressAttribute: UInt16 = 0x0020

    enum Family: UInt8 {
        case ipv4 = 0x01
        case ipv6 = 0x02
    }

    static func bindingRequest(transactionID: Data) -> Data {
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

extension STUNMessage {

    enum DecodeError: Error, Equatable {
        case headerTooShort
        case wrongMessageType
        case transactionIDMismatch
        case attributeNotFound
        case malformedAttribute
        case unsupportedFamily
    }

    static func extractMappedAddress(from data: Data, transactionID: Data) throws -> String {
        guard data.count >= 20 else { throw DecodeError.headerTooShort }
        let bytes = [UInt8](data)

        let messageType = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        guard messageType == bindingResponseType else { throw DecodeError.wrongMessageType }

        guard data[8..<20] == transactionID else {
            throw DecodeError.transactionIDMismatch
        }

        let bodyLength = (Int(bytes[2]) << 8) | Int(bytes[3])
        guard data.count >= 20 + bodyLength else { throw DecodeError.malformedAttribute }

        var cursor = 20
        while cursor + 4 <= 20 + bodyLength {
            let attrType = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
            let attrLen = (Int(bytes[cursor + 2]) << 8) | Int(bytes[cursor + 3])
            let valueStart = cursor + 4
            guard valueStart + attrLen <= 20 + bodyLength else {
                throw DecodeError.malformedAttribute
            }
            if attrType == xorMappedAddressAttribute {
                return try decodeXORMappedAddress(
                    bytes: Array(bytes[valueStart..<valueStart + attrLen]),
                    transactionID: [UInt8](transactionID)
                )
            }
            let padded = (attrLen + 3) & ~3
            cursor = valueStart + padded
        }
        throw DecodeError.attributeNotFound
    }

    private static func decodeXORMappedAddress(bytes: [UInt8], transactionID: [UInt8]) throws -> String {
        guard bytes.count >= 4 else { throw DecodeError.malformedAttribute }
        guard let family = Family(rawValue: bytes[1]) else { throw DecodeError.unsupportedFamily }

        switch family {
        case .ipv4:
            guard bytes.count == 8 else { throw DecodeError.malformedAttribute }
            let xorBytes = [UInt8](bytes[4..<8])
            let plain = zip(xorBytes, magicCookieBytes).map { $0 ^ $1 }
            return plain.map { String($0) }.joined(separator: ".")
        case .ipv6:
            guard bytes.count == 20 else { throw DecodeError.malformedAttribute }
            let xorBytes = [UInt8](bytes[4..<20])
            let key = magicCookieBytes + transactionID
            let plain = zip(xorBytes, key).map { $0 ^ $1 }
            return formatIPv6(Data(plain))
        }
    }

    private static func formatIPv6(_ data: Data) -> String {
        guard let address = IPv6Address(data) else {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        return address.debugDescription
    }
}
