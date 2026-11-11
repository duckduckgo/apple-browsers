//
//  MaliciousSiteProtectionDebugPixel.swift
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
import MaliciousSiteProtection
import PixelKit

/// Debug pixels for Malicious Site Protection datasets.
///
/// Every value sits in the name:
///  - `m_debug_malicious-site-protection_<measure>_<category>_<type>_<bucket>`, for one dataset
///  - `m_debug_malicious-site-protection_<measure>_aggregate_<type>_<bucket>`, for a whole update round
enum MaliciousSiteProtectionDebugPixel: PixelKit.Event, Equatable {
    private static let namePrefix = "m_debug_malicious-site-protection"

    /// How long applying, encoding and writing a dataset update took.
    case updateTime(category: ThreatKind, type: DataManager.StoredDataType.Kind, bucket: MaliciousSiteProtection.Event.DurationBucketAggregation)
    /// The size of the dataset file written after an update.
    case datasetSize(category: ThreatKind, type: DataManager.StoredDataType.Kind, bucket: MaliciousSiteProtection.Event.DatasetSizeBucketAggregation)
    /// How long reading and decoding a stored dataset file took.
    case loadTime(category: ThreatKind, type: DataManager.StoredDataType.Kind, bucket: MaliciousSiteProtection.Event.DurationBucketAggregation)
    /// The total time spent applying, encoding and writing the datasets an update round wrote.
    case aggregateUpdateTime(type: DataManager.StoredDataType.Kind, bucket: MaliciousSiteProtection.Event.DurationBucketAggregation)
    /// The total size of the dataset files written in an update round.
    case aggregateDatasetSize(type: DataManager.StoredDataType.Kind, bucket: MaliciousSiteProtection.Event.DatasetSizeBucketAggregation)
    var name: String {
        switch self {
        case .updateTime(let category, let type, let bucket):
            return Self.name("update-time", category.rawValue, type, bucket.rawValue)
        case .datasetSize(let category, let type, let bucket):
            return Self.name("dataset-size", category.rawValue, type, bucket.rawValue)
        case .loadTime(let category, let type, let bucket):
            return Self.name("load-time", category.rawValue, type, bucket.rawValue)
        case .aggregateUpdateTime(let type, let bucket):
            return Self.name("update-time", "aggregate", type, bucket.rawValue)
        case .aggregateDatasetSize(let type, let bucket):
            return Self.name("dataset-size", "aggregate", type, bucket.rawValue)
        }
    }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

// MARK: - Private

private extension MaliciousSiteProtectionDebugPixel {

    static func name(_ measure: String, _ category: String, _ type: DataManager.StoredDataType.Kind, _ bucket: String) -> String {
        [namePrefix, measure, category, type.pixelSuffix, bucket].joined(separator: "_")
    }
}
