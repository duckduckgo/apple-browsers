//
//  BucketCounter.swift
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

/// A bucket range: matches when `count >= gte` and (`lt` is nil or `count < lt`). Upper bound exclusive.
public struct BucketConfig: Equatable, Sendable {
    public let gte: Int
    public let lt: Int?

    public init(gte: Int, lt: Int? = nil) {
        self.gte = gte
        self.lt = lt
    }
}

/// A single (name, config) pair. JSON object key order determines bucket evaluation order
/// (first-match-wins), so buckets are carried as an ordered list rather than `[String: BucketConfig]`
/// (Swift's `Dictionary` does not preserve insertion order).
public struct OrderedBucket: Equatable, Sendable {
    public let name: String
    public let config: BucketConfig

    public init(name: String, config: BucketConfig) {
        self.name = name
        self.config = config
    }
}

public typealias BucketList = [OrderedBucket]

/// Maps a counter value onto a configured, ordered set of named buckets, and decides when further
/// counting can no longer change the outcome (the value has reached the open-ended bucket).
public enum BucketCounter {
    /// Returns the name of the first bucket matching `count`, or `nil` if no bucket matches. Buckets
    /// are evaluated in list order; the first whose range contains the count wins.
    public static func bucketCount(_ count: Int, buckets: BucketList) -> String? {
        for bucket in buckets {
            if count >= bucket.config.gte && (bucket.config.lt == nil || count < bucket.config.lt!) {
                return bucket.name
            }
        }
        return nil
    }

    /// Returns `true` when no bucket has a lower bound greater than `count`, i.e. the value is in the
    /// highest (open-ended) bucket and further counting cannot change which bucket it falls into.
    public static func shouldStopCounting(_ count: Int, buckets: BucketList) -> Bool {
        buckets.allSatisfy { count >= $0.config.gte }
    }
}
