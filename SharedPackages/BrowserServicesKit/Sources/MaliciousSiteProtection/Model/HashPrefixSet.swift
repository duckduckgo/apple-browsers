//
//  HashPrefixSet.swift
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

/// Structure storing a Set of hash prefixes ["6fe1e7c8","1d760415",...] and a revision of the set.
struct HashPrefixSet: Codable, Equatable {

    var revision: Int
    var set: Set<Element>

    init(revision: Int, items: some Sequence<Element>) {
        self.revision = revision
        self.set = Set(items)
    }

    mutating func subtract<Seq: Sequence>(_ itemsToDelete: Seq) where Seq.Element == String {
        set.subtract(itemsToDelete)
    }

    mutating func formUnion<Seq: Sequence>(_ itemsToAdd: Seq) where Seq.Element == String {
        set.formUnion(itemsToAdd)
    }

    @inline(__always)
    func contains(_ item: String) -> Bool {
        set.contains(item)
    }

}
