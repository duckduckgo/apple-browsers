//
//  Classifier.swift
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
import URLPredictorRust

// C symbols are assumed imported via modulemap/bridging header:
// char *ddg_up_classify_json(const char *input, const char *policy_json);
// void ddg_up_free_string(char *ptr);

public enum Classifier {
    // MARK: - Policy (mirrors Rust struct)
    public struct Policy: Codable, Sendable {
        public var allowIntranetMultiLabel: Bool
        public var allowIntranetSingleLabel: Bool
        public var allowPrivateSuffix: Bool
        public var allowedSchemes: Set<String>

        public init(
            allowIntranetMultiLabel: Bool,
            allowIntranetSingleLabel: Bool,
            allowPrivateSuffix: Bool,
            allowedSchemes: Set<String>
        ) {
            self.allowIntranetMultiLabel = allowIntranetMultiLabel
            self.allowIntranetSingleLabel = allowIntranetSingleLabel
            self.allowPrivateSuffix = allowPrivateSuffix
            self.allowedSchemes = allowedSchemes
        }

        public static let `default`: Self = .init(
            allowIntranetMultiLabel: true,
            allowIntranetSingleLabel: false,
            allowPrivateSuffix: true,
            allowedSchemes: ["http", "https", "ftp", "file", "about", "duck", "mailto"]
        )
    }

    // MARK: - Decision (mirrors Rust enum)
    public enum Decision: Equatable, Sendable {
        case navigate(url: URL)
        case search(query: String)

        public var url: URL? {
            switch self {
            case .navigate(let url):
                return url
            case .search:
                return nil
            }
        }

        public var query: String? {
            switch self {
            case .navigate:
                return nil
            case .search(let query):
                return query
            }
        }
    }

    // MARK: - Errors
    public enum Error: Swift.Error {
        case policyEncodingFailed
        case nativeReturnedNull
        case resultNotUTF8
        case resultDecodingFailed(underlying: Swift.Error)
    }

    // MARK: - Core native call → raw JSON
    static func classifyRawJSON(input: String, policy: Policy?) throws -> String {
        // Encode policy with snake_case to match Rust field names.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let policyData = try? encoder.encode(policy),
              let policyJSON = String(data: policyData, encoding: .utf8)
        else {
            throw Error.policyEncodingFailed
        }

        let jsonString: String = try input.withCString { inputPtr in
            try policyJSON.withCString { policyPtr in
                guard let raw = ddg_up_classify_json(inputPtr, policyPtr) else {
                    throw Error.nativeReturnedNull
                }
                defer { ddg_up_free_string(raw) }
                guard let s = String(validatingUTF8: raw) else {
                    throw Error.resultNotUTF8
                }
                return s
            }
        }
        return jsonString
    }

    // MARK: - Typed helpers

    /// Decode the result into the `Decision` enum.
    public static func classify(input: String, policy: Policy? = .default) throws -> Decision {
        let json = try classifyRawJSON(input: input, policy: policy)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Decision.self, from: Data(json.utf8))
        } catch {
            throw Error.resultDecodingFailed(underlying: error)
        }
    }
}

// Codable for the externally tagged enum:
// {"Navigate":{"url":"..."}}  or  {"Search":{"query":"..."}}
// We only need Decodable, but Encodable provided for symmetry.
extension Classifier.Decision: Codable {
    public init(from decoder: Decoder) throws {
        // Try decoding as { "Navigate": { "url": "..." } } or { "Search": { "query": "..." } }
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: [String: String]].self)

        if let nav = raw["Navigate"], let urlStr = nav["url"], let url = URL(string: urlStr) {
            self = .navigate(url: url)
            return
        }
        if let sea = raw["Search"], let query = sea["query"] {
            self = .search(query: query)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unexpected decision shape: \(raw)"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .navigate(let url):
            try container.encode(["Navigate": ["url": url.absoluteString]])
        case .search(let query):
            try container.encode(["Search": ["query": query]])
        }
    }
}
