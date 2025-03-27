//
//  AutofillUrlSort.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common

public protocol AutofillUrlSort {
    func firstCharacterForGrouping(_ account: SecureVaultModels.WebsiteAccount, tld: TLD) -> String?
    func compareAccountsForSortingAutofill(lhs: SecureVaultModels.WebsiteAccount,
                                           rhs: SecureVaultModels.WebsiteAccount,
                                           tld: TLD) -> ComparisonResult
}

public struct AutofillDomainNameUrlSort: AutofillUrlSort {

    private let autofillDomainNameUrlMatcher = AutofillDomainNameUrlMatcher()

    public init() {}

    public func firstCharacterForGrouping(_ account: SecureVaultModels.WebsiteAccount, tld: TLD) -> String? {
        if let firstChar = account.title?.first {
            return String(firstChar).lowercased()
        } else {
            guard let domain = account.domain,
                  let urlComponents = autofillDomainNameUrlMatcher.normalizeSchemeForAutofill(domain),
                  /// eTLDplus1 is nil if the domain is exact match to a domain in tlds.json in which case we default to host
                  let host = urlComponents.eTLDplus1(tld: tld) ?? urlComponents.host,
                  let firstChar = host.first
            else {
                return nil
            }

            return String(firstChar).lowercased()
        }
    }

    public func compareAccountsForSortingAutofill(lhs: SecureVaultModels.WebsiteAccount,
                                                  rhs: SecureVaultModels.WebsiteAccount,
                                                  tld: TLD) -> ComparisonResult {
        let identicalTitles = lhs.title?.lowercased() == rhs.title?.lowercased()

        let lhsUrlComponents = autofillDomainNameUrlMatcher.normalizeSchemeForAutofill(lhs.domain ?? "")
        let rhsUrlComponents = autofillDomainNameUrlMatcher.normalizeSchemeForAutofill(rhs.domain ?? "")

        let lhsBestMatch = bestPrimarySortField(title: lhs.title,
                                                rawDomain: lhs.domain,
                                                eTLDplus1: lhsUrlComponents?.eTLDplus1(tld: tld),
                                                identicalTitles: identicalTitles)
        let rhsBestMatch = bestPrimarySortField(title: rhs.title,
                                                rawDomain: rhs.domain,
                                                eTLDplus1: rhsUrlComponents?.eTLDplus1(tld: tld),
                                                identicalTitles: identicalTitles)

        let compareResult = compareFields(field1: lhsBestMatch, field2: rhsBestMatch)
        if compareResult != .orderedSame {
            return compareResult
        }
        return compareFields(field1: lhsUrlComponents?.subdomain(tld: tld),
                             field2: rhsUrlComponents?.subdomain(tld: tld))
    }

    private func compareFields(field1: String?, field2: String?) -> ComparisonResult {
        if let field1 = field1, field1.isEmpty, let field2 = field2, field2.isEmpty {
            return .orderedSame
        } else if let field1 = field1, field1.isEmpty {
            return .orderedAscending
        } else if let field2 = field2, field2.isEmpty {
            return .orderedDescending
        } else {
            return (field1 ?? "").localizedCaseInsensitiveCompare(field2 ?? "")
        }
    }

    private func bestPrimarySortField(title: String?,
                                      rawDomain: String?,
                                      eTLDplus1: String?,
                                      identicalTitles: Bool) -> String? {
        if !(title ?? "").isEmpty && !identicalTitles {
            return title
        } else if !(eTLDplus1 ?? "").isEmpty {
            return eTLDplus1
        } else {
            return rawDomain
        }
    }
}
