//
//  BrokenSiteReportEntry.swift
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
import CryptoKit

/// Storage for the last time a BrokenSiteReport has been sent
public struct BrokenSiteReportEntry {

    /// first 6 chars of the sha256 hash of www.example.com
    let identifier: String
    /// yyyy-mm-dd
    let lastSentDayString: String
    /// Object Creation + 30 days
    let expiryDate: Date?

    public init?(report: BrokenSiteReport, currentDate: Date, daysToExpiry: Int) {

        guard let domainIdentifier = report.siteUrl.privacySafeDomainIdentifier,
              let expiryDate = Calendar.current.date(byAdding: .day, value: daysToExpiry, to: currentDate) else {
            return nil
        }
        self.identifier = domainIdentifier
        self.lastSentDayString = currentDate.formattedDateString
        self.expiryDate = expiryDate
    }

    /// To be used when the entry is created from a UserDefault key value pair
    public init(safeDomainIdentifier: String, lastSentDayString: String) {

        self.identifier = safeDomainIdentifier
        self.lastSentDayString = lastSentDayString
        self.expiryDate = nil
    }

}

public extension URL {

    /// A string containing the first 6 chars of the sha256 hash of the URL's domain part
    var privacySafeDomainIdentifier: String? {
        guard let domain = self.host else {
            return nil
        }

        guard let utf8Data = domain.data(using: .utf8) else {
            return nil
        }

        let sha256Digest = SHA256.hash(data: utf8Data)
        let sha256Hex = sha256Digest.compactMap { String(format: "%02x", $0) }.joined()

        let startIndex = sha256Hex.startIndex
        let endIndex = sha256Hex.index(startIndex, offsetBy: 6)
        let firstSixCharacters = sha256Hex[startIndex..<endIndex]

        return String(firstSixCharacters)
    }
}

fileprivate extension Date {

    /// A string with the date formatted as `yyyy-MM-dd`
    var formattedDateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: self)
    }

}
