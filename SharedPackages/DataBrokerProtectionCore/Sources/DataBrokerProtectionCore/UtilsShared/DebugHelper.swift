//
//  DebugHelper.swift
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

public enum DebugHelper {
    public static func djb2Hash(_ text: String) -> Int64 {
        var hash: Int64 = 5381
        for char in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int64(char)
        }
        return hash
    }

    public static func stableId(for broker: DataBroker) -> Int64 {
        djb2Hash(broker.url)
    }

    public static func stableId(for profileQuery: ProfileQuery) -> Int64 {
        let profileQueryText = "\(profileQuery.firstName) \(profileQuery.lastName) x \(profileQuery.city) \(profileQuery.state)"
        return djb2Hash(profileQueryText)
    }

    public static func stableId(for profile: ExtractedProfile) -> Int64 {
        if let identifier = profile.identifier, !identifier.isEmpty {
            return djb2Hash(identifier)
        }

        let name = profile.name ?? profile.fullName
        let addresses = profile.addresses?.map { $0.fullAddress }.sorted().joined(separator: ",")
        let relatives = profile.relatives?.sorted().joined(separator: ",")
        let alternativeNames = profile.alternativeNames?.sorted().joined(separator: ",")

        let fallbackComponents = [
            name,
            profile.age,
            addresses,
            relatives,
            alternativeNames
        ].compactMap { $0 }.filter { !$0.isEmpty }

        return djb2Hash(fallbackComponents.joined(separator: "|"))
    }

    public static func prettyJSONString(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formattedData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }

        return String(data: formattedData, encoding: .utf8)
    }

    static func prettyPrintedJSON(from value: Any) -> String {
        let encoder = JSONEncoder()
        let fallback = String(describing: value)

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encodable = value as? Encodable,
           let data = try? encoder.encode(AnyEncodable(encodable)) {
            return String(data: data, encoding: .utf8) ?? fallback
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
            return String(data: data, encoding: .utf8) ?? fallback
        }

        return fallback
    }

    static func prettyPrintedJSON(from profiles: [ExtractedProfile], meta: [String: Any]?) -> String {
        let profiles = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(profiles)))

        return prettyPrintedJSON(from: [
            "profiles": profiles ?? "unknown",
            "meta": meta ?? [:]
        ])
    }

    static func prettyPrintedActionPayload(action: Action, data: CCFRequestData) -> String {
        prettyPrintedJSON(from: Params(state: ActionRequest(action: action, data: data)))
    }
}

private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encode = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
