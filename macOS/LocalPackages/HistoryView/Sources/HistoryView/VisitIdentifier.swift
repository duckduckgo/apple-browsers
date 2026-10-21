//
//  VisitIdentifier.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/**
 * This struct is used to identify a single visit in the History View.
 *
 * It implements `LosslessStringConvertible` in order to be exchanged with the web Frontend.
 *
 * Pipe (`|`) is used as components separator in `description` because:
 * - `uuid` field is an actual UUID (see `HistoryEntry`) and it's guaranteed to not contain pipes,
 * - `url` doesn't allow pipe characters (they must be escaped) as per the RFC,
 * - `date`'s time interval is a number.
 */
public struct VisitIdentifier: Hashable, LosslessStringConvertible, Codable {
    public init?(_ description: String) {
        let components = description.components(separatedBy: "|").filter { !$0.isEmpty }
        guard components.count == 3, let url = URL(string: components[1]), let timeInterval = TimeInterval(components[2]) else {
            return nil
        }
        self.init(uuid: components[0], url: url, date: .init(timeIntervalSince1970: timeInterval))
    }

    public init(uuid: String, url: URL, date: Date) {
        self.uuid = uuid
        self.url = url.absoluteString
        self.date = date
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let visitIdentifier = Self(value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Failed to decode VisitIdentifier from \(value)")
        }
        self = visitIdentifier
    }

    public var description: String {
        [uuid, url, String(date.timeIntervalSince1970)].joined(separator: "|")
    }

    public let uuid: String
    public let url: String
    public let date: Date

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public static func == (_ lhs: VisitIdentifier, _ rhs: VisitIdentifier) -> Bool {
        /// Second precision is enough for comparing `VisitIdentifier`s, because visits themselves are looked up with day precision.
        lhs.uuid == rhs.uuid && lhs.url == rhs.url && Int64(lhs.date.timeIntervalSince1970) == Int64(rhs.date.timeIntervalSince1970)
    }
}
