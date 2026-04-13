//
//  JavaScriptTrackerData.swift
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
import TrackerRadarKit

/// JavaScript-specific tracker data payload used for C-S-S injection.
///
/// Native code still relies on full `TrackerData`, but JavaScript only consumes a
/// subset of the serialized fields. Trimming the payload here avoids shipping
/// unused nested data such as `entities[*].domains`.
struct JavaScriptTrackerData: Encodable {

    private let value: JSONValue

    init(from trackerData: TrackerData) throws {
        let encoded = try JSONEncoder().encode(trackerData)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw EncodingError.invalidValue(trackerData,
                                             .init(codingPath: [],
                                                   debugDescription: "TrackerData did not encode to a JSON object"))
        }

        if var entities = object["entities"] as? [String: Any] {
            entities = entities.mapValues { value in
                guard var entity = value as? [String: Any] else { return value }
                entity.removeValue(forKey: "domains")
                return entity
            }
            object["entities"] = entities
        }

        if var trackers = object["trackers"] as? [String: Any] {
            trackers = trackers.mapValues { value in
                guard var tracker = value as? [String: Any] else { return value }
                tracker.removeValue(forKey: "domain")
                tracker.removeValue(forKey: "prevalence")

                if var owner = tracker["owner"] as? [String: Any] {
                    owner.removeValue(forKey: "ownedBy")
                    tracker["owner"] = owner
                }

                return tracker
            }
            object["trackers"] = trackers
        }

        self.value = try JSONValue(jsonObject: object)
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

private enum JSONValue: Encodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(jsonObject: Any) throws {
        switch jsonObject {
        case let value as [String: Any]:
            self = .object(try value.mapValues(JSONValue.init(jsonObject:)))
        case let value as [Any]:
            self = .array(try value.map(JSONValue.init(jsonObject:)))
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case _ as NSNull:
            self = .null
        default:
            throw EncodingError.invalidValue(jsonObject,
                                             .init(codingPath: [],
                                                   debugDescription: "Unsupported JSON value: \(type(of: jsonObject))"))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let value):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, nestedValue) in value {
                try container.encode(nestedValue, forKey: DynamicCodingKey(stringValue: key))
            }
        case .array(let value):
            var container = encoder.unkeyedContainer()
            try container.encode(contentsOf: value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
