//
//  PermissionsPolicy.swift
//  DuckDuckGo
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
import RawStructuredFieldValues

/// Interprets the response header restrictions used by the native permission bridges.
/// This does not evaluate iframe inheritance, document security, or user authorization.
public struct PermissionsPolicy {
    private let directives: OrderedMap<String, ItemOrInnerList>

    public init(header: String?) {
        var parser = StructuredFieldValueParser(Array((header ?? "").utf8))
        // A malformed structured dictionary contributes no declared policy.
        directives = (try? parser.parseDictionaryFieldValue()) ?? OrderedMap()
    }

    /// Evaluates geolocation for the response's own origin, not a descendant frame.
    public func blocksGeolocation(for pageURL: URL?) -> Bool {
        guard let directive = directives["geolocation"] else { return false }
        let values: [RFC9651BareItem]
        switch directive {
        case .item(let item):
            switch item.rfc9651BareItem {
            case .token("self"), .token("*"), .string:
                values = [item.rfc9651BareItem]
            default:
                // Section 5.2 ignores unsupported dictionary member values.
                return false
            }
        case .innerList(let list):
            values = list.bareInnerList.map(\.rfc9651BareItem)
        }

        return !values.contains { value in
            switch value {
            case .token("self"), .token("*"):
                return true
            case .string(let expression):
                return Self.sourceExpression(expression, matches: pageURL)
            default:
                return false
            }
        }
    }

    /// Native media preflight recognizes explicit empty lists; WebKit handles other media policy restrictions.
    public var blockedMediaTypes: Set<SitePermissionType> {
        Set([SitePermissionType.camera, .microphone].filter { type in
            guard case .innerList(let list) = directives[type.rawValue] else { return false }
            return list.bareInnerList.isEmpty
        })
    }

    // https://www.w3.org/TR/permissions-policy/#allowlists uses CSP source-expression matching.
    // This evaluates HTTP(S) response origins, not arbitrary resource URLs or inherited frame policies.
    private static func sourceExpression(_ expression: String, matches pageURL: URL?) -> Bool {
        guard let pageURL, let pageScheme = pageURL.scheme?.lowercased(),
              ["http", "https"].contains(pageScheme), let pageHost = pageURL.host?.lowercased() else { return false }
        if expression == "*" { return true }

        if expression.hasSuffix(":"), !expression.contains("/") {
            return scheme(String(expression.dropLast()).lowercased(), matches: pageScheme)
        }

        let schemeAndAuthority = expression.components(separatedBy: "://")
        guard schemeAndAuthority.count <= 2 else { return false }
        let hasExplicitScheme = schemeAndAuthority.count == 2
        let sourceScheme = hasExplicitScheme ? schemeAndAuthority[0].lowercased() : pageScheme
        guard scheme(sourceScheme, matches: pageScheme) else { return false }

        let authority = hasExplicitScheme ? schemeAndAuthority[1] : schemeAndAuthority[0]
        let authorityAndPath = authority.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        // Permissions Policy matches the serialized origin, whose path is always empty or '/'.
        guard let hostAndPortSource = authorityAndPath.first,
              authorityAndPath.count == 1 || authorityAndPath[1].isEmpty else { return false }
        let hostAndPort = hostAndPortSource.split(separator: ":", omittingEmptySubsequences: false)
        guard let hostPart = hostAndPort.first, hostAndPort.count <= 2 else { return false }

        let sourceHost = hostPart.lowercased()
        let isWildcardSubdomain = sourceHost.hasPrefix("*.")
        let hostWithoutWildcard = isWildcardSubdomain ? String(sourceHost.dropFirst(2)) : sourceHost
        let labelCharacters = "abcdefghijklmnopqrstuvwxyz0123456789-"
        let hostLabels = (hostWithoutWildcard.hasSuffix(".") ? hostWithoutWildcard.dropLast() : hostWithoutWildcard[...])
            .split(separator: ".", omittingEmptySubsequences: false)
        guard sourceHost == "*" || (!hostWithoutWildcard.isEmpty && hostLabels.allSatisfy({
            !$0.isEmpty && $0.allSatisfy(labelCharacters.contains)
        })) else { return false }

        let matchesExactHost = sourceHost == pageHost
        let matchesWildcardSubdomain = isWildcardSubdomain && pageHost.hasSuffix(String(sourceHost.dropFirst()))
        guard sourceHost == "*" || matchesExactHost || matchesWildcardSubdomain else { return false }

        return sourcePortMatches(hostAndPort, pageURL: pageURL, pageScheme: pageScheme)
    }

    private static func sourcePortMatches(_ hostAndPort: [Substring], pageURL: URL, pageScheme: String) -> Bool {
        let defaultPort = pageScheme == "https" ? 443 : 80
        let pagePort = pageURL.port ?? defaultPort
        guard hostAndPort.count == 2 else { return pagePort == defaultPort }
        if hostAndPort[1] == "*" { return true }
        let portDigits = "0123456789"
        guard !hostAndPort[1].isEmpty, hostAndPort[1].allSatisfy(portDigits.contains),
              let sourcePort = UInt16(hostAndPort[1]) else { return false }
        return Int(sourcePort) == pagePort
    }

    private static func scheme(_ source: String, matches target: String) -> Bool {
        source == target || (source == "http" && target == "https")
            || (source == "ws" && ["http", "https"].contains(target))
            || (source == "wss" && target == "https")
    }
}
