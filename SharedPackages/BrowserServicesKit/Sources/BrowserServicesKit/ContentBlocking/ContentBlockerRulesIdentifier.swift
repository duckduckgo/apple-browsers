//
//  ContentBlockerRulesIdentifier.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public class ContentBlockerRulesIdentifier: Equatable, Codable {

    let name: String
    let tdsEtag: String
    let tempListId: String
    let allowListId: String
    let unprotectedSitesHash: String
    /// Whether the rules leave requests that have a surrogate unblocked. Saved identifiers from before this existed
    /// decode as `false`.
    public let unblockSurrogateRules: Bool

    /// Only changes when `unblockSurrogateRules` is on, so rules compiled before it existed still match.
    public var stringValue: String {
        let base = name + tdsEtag + tempListId + allowListId + unprotectedSitesHash
        return unblockSurrogateRules ? base + Self.unblockSurrogateRulesSuffix : base
    }

    private static let unblockSurrogateRulesSuffix = "\"unblockSurrogateRules\""

    public struct Difference: OptionSet, CustomDebugStringConvertible, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let tdsEtag = Difference(rawValue: 1 << 0)
        public static let tempListId = Difference(rawValue: 1 << 1)
        public static let allowListId = Difference(rawValue: 1 << 2)
        public static let unprotectedSites = Difference(rawValue: 1 << 3)
        public static let unblockSurrogateRules = Difference(rawValue: 1 << 4)

        public static let all: Difference = [.tdsEtag, .tempListId, .allowListId, .unprotectedSites, .unblockSurrogateRules]

        public var debugDescription: String {
            if self == .all {
                return "all"
            }
            var result = "["
            for i in 0...Int(log2(Double(max(self.rawValue, Self.all.rawValue)))) where self.contains(Self(rawValue: 1 << i)) {
                if result.count > 1 {
                    result += ", "
                }
                result += {
                    switch Self(rawValue: 1 << i) {
                    case .tdsEtag: ".tdsEtag"
                    case .tempListId: ".tempListId"
                    case .allowListId: ".allowListId"
                    case .unprotectedSites: ".unprotectedSites"
                    case .unblockSurrogateRules: ".unblockSurrogateRules"
                    default: "1<<\(i)"
                    }
                }()
            }
            result += "]"
            return result
        }
    }

    private class func normalize(identifier: String?) -> String {
        // Ensure identifier is in double quotes
        guard var identifier = identifier else {
            return "\"\""
        }

        if !identifier.hasSuffix("\"") {
            identifier += "\""
        }

        if !identifier.hasPrefix("\"") || identifier.count == 1 {
            identifier = "\"" + identifier
        }

        return identifier
    }

    public class func hash(domains: [String]?) -> String {
        guard let domains = domains, !domains.isEmpty else {
            return ""
        }

        return domains.joined().sha1
    }

    public init(name: String,
                tdsEtag: String,
                tempListId: String?,
                allowListId: String?,
                unprotectedSitesHash: String?,
                unblockSurrogateRules: Bool = false) {

        self.name = Self.normalize(identifier: name)
        self.tdsEtag = Self.normalize(identifier: tdsEtag)
        self.tempListId = Self.normalize(identifier: tempListId)
        self.allowListId = Self.normalize(identifier: allowListId)
        self.unprotectedSitesHash = Self.normalize(identifier: unprotectedSitesHash)
        self.unblockSurrogateRules = unblockSurrogateRules
    }

    private enum CodingKeys: String, CodingKey {
        case name, tdsEtag, tempListId, allowListId, unprotectedSitesHash, unblockSurrogateRules
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        tdsEtag = try container.decode(String.self, forKey: .tdsEtag)
        tempListId = try container.decode(String.self, forKey: .tempListId)
        allowListId = try container.decode(String.self, forKey: .allowListId)
        unprotectedSitesHash = try container.decode(String.self, forKey: .unprotectedSitesHash)
        unblockSurrogateRules = try container.decodeIfPresent(Bool.self, forKey: .unblockSurrogateRules) ?? false
    }

    public func compare(with id: ContentBlockerRulesIdentifier) -> Difference {

        var result = Difference()
        if tdsEtag != id.tdsEtag {
            result.insert(.tdsEtag)
        }
        if tempListId != id.tempListId {
            result.insert(.tempListId)
        }
        if allowListId != id.allowListId {
            result.insert(.allowListId)
        }
        if unprotectedSitesHash != id.unprotectedSitesHash {
            result.insert(.unprotectedSites)
        }
        if unblockSurrogateRules != id.unblockSurrogateRules {
            result.insert(.unblockSurrogateRules)
        }

        return result
    }

    public static func == (lhs: ContentBlockerRulesIdentifier, rhs: ContentBlockerRulesIdentifier) -> Bool {
        return lhs.compare(with: rhs).isEmpty
    }
}
