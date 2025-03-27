//
//  FilterDictionary.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

struct FilterDictionary: Codable, Equatable {

    /// Filter set revision
    var revision: Int

    /// [Hash: [RegEx]] mapping
    ///
    /// - **Key**: SHA256 hash sum of a canonical host name
    /// - **Value**: An array of regex patterns used to match whole URLs
    ///
    /// ```
    /// {
    ///     "3aeb002460381c6f258e8395d3026f571f0d9a76488dcd837639b13aed316560" : [
    ///         "(?i)^https?\\:\\/\\/[\\w\\-\\.]+(?:\\:(?:80|443))?[\\/\\\\]+BETS1O\\-GIRIS[\\/\\\\]+BETS1O(?:[\\/\\\\]+|\\?|$)"
    ///     ],
    ///     ...
    /// }
    /// ```
    var filters: [String: Set<String>]

    /// Subscript to access regex patterns by SHA256 host name hash
    subscript(hash: String) -> Set<String>? {
        filters[hash]
    }

    mutating func subtract<Seq: Sequence>(_ itemsToDelete: Seq) where Seq.Element == Filter {
        for filter in itemsToDelete {
            // Remove the filter from the Set stored in the Dictionary by hash used as a key.
            // If the Set becomes empty – remove the Set value from the Dictionary.
            //
            // The following code is equivalent to this one but without the Set value being copied
            // or key being searched multiple times:
            /*
             if var filterSet = self.filters[filter.hash] {
                filterSet.remove(filter.regex)
                if filterSet.isEmpty {
                    self.filters[filter.hash] = nil
                } else {
                    self.filters[filter.hash] = filterSet
                }
             }
            */
            withUnsafeMutablePointer(to: &filters[filter.hash]) { item in
                item.pointee?.remove(filter.regex)
                if item.pointee?.isEmpty == true {
                    item.pointee = nil
                }
            }
        }
    }

    mutating func formUnion<Seq: Sequence>(_ itemsToAdd: Seq) where Seq.Element == Filter {
        for filter in itemsToAdd {
            filters[filter.hash, default: []].insert(filter.regex)
        }
    }

}
