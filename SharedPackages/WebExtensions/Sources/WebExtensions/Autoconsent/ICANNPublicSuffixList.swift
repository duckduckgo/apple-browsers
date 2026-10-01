//
//  ICANNPublicSuffixList.swift
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

import Common
import Foundation

/// The ICANN section of the Public Suffix List, to find the registrable domain of a host the same way as
/// `getDomain()` of the `tldts` npm package with its default options, which the DDG extension uses.
///
/// This is different from `TLD`, which also uses the private section of the list: for `user.github.io`,
/// this gives `github.io`, and `TLD` gives `user.github.io`. It also supports wildcard and exception rules.
struct ICANNPublicSuffixList: Sendable {

    private let rules: Set<String>
    /// `*.ck` is stored as `ck`
    private let wildcardRules: Set<String>
    /// `!www.ck` is stored as `www.ck`
    private let exceptionRules: Set<String>

    /// - Parameter pslData: the text of `public_suffix_list.dat`. Only the rules before the end of the ICANN section are used.
    init(pslData: String) {
        var rules = Set<String>()
        var wildcardRules = Set<String>()
        var exceptionRules = Set<String>()
        pslData.enumerateLines { line, stop in
            if line.contains("===END ICANN DOMAINS===") {
                stop = true
                return
            }
            // A rule is the first word of a line
            guard let word = line.split(whereSeparator: \.isWhitespace).first, !word.hasPrefix("//") else { return }
            let rule = word.lowercased()
            if rule.hasPrefix("*.") {
                wildcardRules.insert(Self.asciiRule(rule.dropFirst(2)))
            } else if rule.hasPrefix("!") {
                exceptionRules.insert(Self.asciiRule(rule.dropFirst()))
            } else {
                rules.insert(Self.asciiRule(rule[...]))
            }
        }
        self.rules = rules
        self.wildcardRules = wildcardRules
        self.exceptionRules = exceptionRules
    }

    /// - Returns: the public suffix of the host with one more label, or `nil` if the host is an IP address, a single label or a public suffix.
    func registrableDomain(of host: String) -> String? {
        var host = host.lowercased()
        if host.hasSuffix(".") {
            host.removeLast()
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count > 1,
              !labels.contains(where: \.isEmpty),
              !host.contains(":"), // IPv6
              !labels.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }) // IPv4
        else {
            return nil
        }

        // Find the longest matching rule. Without one, the public suffix is the last label (the implicit "*" rule).
        var suffixLabelCount = 1
        for start in labels.indices {
            let candidate = labels[start...].joined(separator: ".")
            let candidateLabelCount = labels.count - start
            if exceptionRules.contains(candidate) {
                suffixLabelCount = candidateLabelCount - 1
                break
            }
            if rules.contains(candidate) || (candidateLabelCount > 1 && wildcardRules.contains(labels[(start + 1)...].joined(separator: "."))) {
                suffixLabelCount = candidateLabelCount
                break
            }
        }

        guard suffixLabelCount < labels.count else { return nil }
        return labels.suffix(suffixLabelCount + 1).joined(separator: ".")
    }

    /// Hosts are in punycode, and the list has IDN rules in Unicode
    private static func asciiRule(_ rule: Substring) -> String {
        rule.allSatisfy(\.isASCII) ? String(rule) : rule.punycodeEncodedHostname
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
