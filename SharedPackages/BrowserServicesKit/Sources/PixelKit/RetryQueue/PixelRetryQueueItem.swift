//
//  PixelRetryQueueItem.swift
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

/// A failed pixel fire awaiting retry.
///
/// Captures the fully-resolved network request exactly as it would have been sent (pixel name, headers,
/// parameters and `allowedQueryReservedCharacters`), plus the time it was first enqueued — which drives the
/// 28-day expiry. `CharacterSet` is not `Codable`, so it is encoded as its `bitmapRepresentation`.
struct PixelRetryQueueItem: Codable, Equatable, Identifiable {

    public let id: UUID
    public let pixelName: String
    public let headers: [String: String]
    public let parameters: [String: String]
    public let allowedQueryReservedCharacters: CharacterSet?
    public let timestamp: Date

    public init(id: UUID = UUID(),
                pixelName: String,
                headers: [String: String],
                parameters: [String: String],
                allowedQueryReservedCharacters: CharacterSet?,
                timestamp: Date) {
        self.id = id
        self.pixelName = pixelName
        self.headers = headers
        self.parameters = parameters
        self.allowedQueryReservedCharacters = allowedQueryReservedCharacters
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id, pixelName, headers, parameters, allowedQueryReservedCharacters, timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pixelName = try container.decode(String.self, forKey: .pixelName)
        headers = try container.decode([String: String].self, forKey: .headers)
        parameters = try container.decode([String: String].self, forKey: .parameters)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        if let bitmap = try container.decodeIfPresent(Data.self, forKey: .allowedQueryReservedCharacters) {
            allowedQueryReservedCharacters = CharacterSet(bitmapRepresentation: bitmap)
        } else {
            allowedQueryReservedCharacters = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pixelName, forKey: .pixelName)
        try container.encode(headers, forKey: .headers)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(allowedQueryReservedCharacters?.bitmapRepresentation, forKey: .allowedQueryReservedCharacters)
    }
}
