//
//  AIChatBonusMessageLog.swift
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

/// The recent bonus offer messages between native and Duck.ai, shown in the Duck.ai storage debug dashboard.
///
/// Records nothing until enabled: the debug server enables it while it runs. Kept in memory only, and every
/// Bonus ID is masked to its last 4 characters before it's stored.
public final class AIChatBonusMessageLog: @unchecked Sendable {

    public static let shared = AIChatBonusMessageLog()

    public enum Kind: String {
        /// Duck.ai asked and native replied.
        case request
        /// Duck.ai sent a message that expects no reply.
        case notification
        /// Native sent the record to Duck.ai after a change.
        case push
    }

    public struct Entry {
        public let date: Date
        public let kind: Kind
        public let method: String
        /// The message params, as a JSON object with Bonus IDs masked.
        public let params: Any?
        /// The reply or the pushed payload, as a JSON object with Bonus IDs masked.
        public let body: Any?
        /// Why native didn't reply or handle the message, if it didn't.
        public let note: String?
    }

    private let capacity: Int
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var enabled = false

    init(capacity: Int = 100) {
        self.capacity = capacity
    }

    /// Turning it off also clears the log.
    public var isEnabled: Bool {
        get { locked { enabled } }
        set {
            locked {
                enabled = newValue
                if !newValue { entries.removeAll() }
            }
        }
    }

    /// The recorded messages, newest first.
    public var recentEntries: [Entry] {
        locked { entries.reversed() }
    }

    public func clear() {
        locked { entries.removeAll() }
    }

    private func locked<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func record(_ kind: Kind, method: String, params: Any? = nil, body: Encodable? = nil, note: String? = nil) {
        // Checked first, so a disabled log doesn't encode anything.
        guard isEnabled else { return }

        let entry = Entry(
            date: Date(),
            kind: kind,
            method: method,
            params: params.flatMap { Self.maskedJSONObject(from: $0) },
            body: body.flatMap { Self.maskedJSONObject(encoding: $0) },
            note: note
        )
        locked {
            entries.append(entry)
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }
    }
}

// MARK: - Masking

extension AIChatBonusMessageLog {

    /// `encodable` as a JSON object with every Bonus ID masked, or `nil` if it doesn't encode.
    public static func maskedJSONObject(encoding encodable: Encodable) -> Any? {
        guard let data = try? JSONEncoder().encode(encodable),
              let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return nil
        }
        return masked(object)
    }

    static func maskedJSONObject(from object: Any) -> Any? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return masked(object)
    }

    /// Replaces every `bonusId` value with its last 4 characters, like a card number: `•••• c7e9`.
    static func masked(_ object: Any) -> Any {
        switch object {
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: [String: Any]()) { result, element in
                if element.key == "bonusId", let bonusId = element.value as? String {
                    result[element.key] = maskedBonusId(bonusId)
                } else {
                    result[element.key] = masked(element.value)
                }
            }
        case let array as [Any]:
            return array.map(masked)
        default:
            return object
        }
    }

    static func maskedBonusId(_ bonusId: String) -> String {
        guard bonusId.count > 4 else { return "••••" }
        return "•••• " + bonusId.suffix(4)
    }
}
