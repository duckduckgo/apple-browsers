//
//  NativeMessagingFraming.swift
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

/// Errors of the native messaging wire format.
public enum NativeMessagingFramingError: Error, Equatable {

    /// The declared length is larger than `NativeMessagingFraming.maximumMessageSize`.
    case messageTooLarge(length: Int)

    /// The payload is not a JSON object.
    case invalidJSON
}

/// The wire format that browsers use to talk to a native messaging host.
///
/// Every message carries a 4-byte length prefix in the host's byte order, and then the
/// message itself as UTF-8 JSON. Chrome, Firefox and Safari all use this format, so a host
/// such as Bitwarden's `desktop_proxy` needs no change to talk to us.
public enum NativeMessagingFraming {

    /// Upper bound for one message. It guards against a hostile or broken host.
    public static let maximumMessageSize = 64 * 1024 * 1024

    /// The size of the length prefix.
    public static let prefixSize = 4

    /// Encodes one message for the host.
    public static func encode(_ message: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(message) else {
            throw NativeMessagingFramingError.invalidJSON
        }

        let payload = try JSONSerialization.data(withJSONObject: message)
        guard payload.count <= maximumMessageSize else {
            throw NativeMessagingFramingError.messageTooLarge(length: payload.count)
        }

        var frame = Data(capacity: prefixSize + payload.count)
        withUnsafeBytes(of: UInt32(payload.count)) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }

    /// Reads the length prefix of a frame.
    public static func decodeLength(_ prefix: Data) throws -> Int {
        precondition(prefix.count == prefixSize, "A length prefix is \(prefixSize) bytes")

        let length = Int(prefix.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard length <= maximumMessageSize else {
            throw NativeMessagingFramingError.messageTooLarge(length: length)
        }
        return length
    }

    /// Decodes the payload of a frame.
    public static func decodePayload(_ payload: Data) throws -> Any {
        let message = try JSONSerialization.jsonObject(with: payload)
        return message
    }
}
