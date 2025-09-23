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

/// This namespace wraps API provided by `URLPredictorRust` framework.
///
/// ```c
/// char *ddg_up_classify_json(const char *input, const char *policy_json);
/// void ddg_up_free_string(char *ptr);
/// ```
public enum Classifier {

    /// This function classifies `input` as either `Decision.navigate` or `Decision.search`.
    public static func classify(input: String, policy: Policy? = .default) throws -> Decision {
        let json = try classifyRawJSON(input: input, policy: policy)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Decision.self, from: Data(json.utf8))
        } catch {
            throw Error.resultDecodingFailed(underlying: error)
        }
    }

    /// This struct describes the policy to be used when classifying the input.
    public struct Policy: Codable, Sendable {
        /// Treat any host-like strings as URLs (e.g. `package.json`) without consulting Public Suffix List.
        public var allowIntranetMultiLabel: Bool

        /// Whether to allow single-label domains (e.g. `test` or `dev`).
        public var allowIntranetSingleLabel: Bool

        /// When checking Public Suffix List, whether to consult private suffixes (e.g. `appspot.com` or `github.io`).
        public var allowPrivateSuffix: Bool

        /// Defines schemes recognized by the app/
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

        /// The default policy used when not specified
        public static let `default`: Self = .init(
            allowIntranetMultiLabel: true,
            allowIntranetSingleLabel: false,
            allowPrivateSuffix: true,
            allowedSchemes: ["http", "https", "file", "about", "data", "duck", "mailto", "x-safari-https"]
        )
    }

    public enum Decision: Equatable, Sendable, Decodable {
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

        // MARK: - Decodable

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let navigation = try container.decodeIfPresent(Navigation.self, forKey: .navigate) {
                self = .navigate(url: navigation.url)
            } else if let search = try container.decodeIfPresent(Search.self, forKey: .search) {
                self = .search(query: search.query)
            } else {
                throw DecodingError.dataCorruptedError(forKey: CodingKeys.navigate, in: container, debugDescription: "Couldn't decode Navigate nor Search from Decision")
            }
        }

        // MARK: - Internal

        enum CodingKeys: String, CodingKey {
            case navigate = "Navigate"
            case search = "Search"
        }

        struct Navigation: Equatable, Sendable, Decodable {
            public let url: URL
        }

        struct Search: Equatable, Sendable, Decodable {
            public let query: String
        }
    }

    public enum Error: Swift.Error {
        case policyEncodingFailed
        case resultNil
        case resultNotUTF8
        case resultDecodingFailed(underlying: Swift.Error)
    }

    // MARK: - Internal

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
                    throw Error.resultNil
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
}
