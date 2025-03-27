//
//  BloomFilterWrapper.swift
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
@_implementationOnly import BloomFilterObjC

public final class BloomFilterWrapper {
    private let bloomFilter: BloomFilterObjC

    public init(fromPath path: String, withBitCount bitCount: Int32, andTotalItems totalItems: Int32) {
        bloomFilter = BloomFilterObjC(fromPath: path, withBitCount: bitCount, andTotalItems: totalItems)
    }

    public init(totalItems count: Int32, errorRate: Double) {
        bloomFilter = BloomFilterObjC(totalItems: count, errorRate: errorRate)
    }

    public func add(_ entry: String) {
        bloomFilter.add(entry)
    }

    public func contains(_ entry: String) -> Bool {
        bloomFilter.contains(entry)
    }
}
