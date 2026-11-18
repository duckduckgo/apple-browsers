//
//  Event+Performance.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

// MARK: - Duration and Size Pixel Buckets

public extension Event {

    /// How long something took: `100ms`, `250ms`, `500ms`, `1s` … `10s`, `15s` … `30s`, `more`.
    enum DurationBucketAggregation: String, CaseIterable, Sendable {
        case upTo100ms = "100ms"
        case upTo250ms = "250ms"
        case upTo500ms = "500ms"
        case upTo1s = "1s"
        case upTo2s = "2s"
        case upTo3s = "3s"
        case upTo4s = "4s"
        case upTo5s = "5s"
        case upTo6s = "6s"
        case upTo7s = "7s"
        case upTo8s = "8s"
        case upTo9s = "9s"
        case upTo10s = "10s"
        case upTo15s = "15s"
        case upTo20s = "20s"
        case upTo25s = "25s"
        case upTo30s = "30s"
        case more

        public init(seconds: TimeInterval) {
            switch seconds {
            case ...0.1: self = .upTo100ms
            case ...0.25: self = .upTo250ms
            case ...0.5: self = .upTo500ms
            case ...1: self = .upTo1s
            case ...2: self = .upTo2s
            case ...3: self = .upTo3s
            case ...4: self = .upTo4s
            case ...5: self = .upTo5s
            case ...6: self = .upTo6s
            case ...7: self = .upTo7s
            case ...8: self = .upTo8s
            case ...9: self = .upTo9s
            case ...10: self = .upTo10s
            case ...15: self = .upTo15s
            case ...20: self = .upTo20s
            case ...25: self = .upTo25s
            case ...30: self = .upTo30s
            default: self = .more
            }
        }
    }

    /// The size of a dataset file, in megabytes (1 MB = 1,000,000 bytes): `500kb`, `1mb` … `100mb`, `more`.
    enum DatasetSizeBucketAggregation: String, CaseIterable, Sendable {
        case upTo500kb = "500kb"
        case upTo1mb = "1mb"
        case upTo2mb = "2mb"
        case upTo3mb = "3mb"
        case upTo4mb = "4mb"
        case upTo5mb = "5mb"
        case upTo6mb = "6mb"
        case upTo8mb = "8mb"
        case upTo10mb = "10mb"
        case upTo15mb = "15mb"
        case upTo20mb = "20mb"
        case upTo25mb = "25mb"
        case upTo30mb = "30mb"
        case upTo35mb = "35mb"
        case upTo40mb = "40mb"
        case upTo50mb = "50mb"
        case upTo60mb = "60mb"
        case upTo75mb = "75mb"
        case upTo100mb = "100mb"
        case more

        public init(bytes: Int) {
            switch bytes.toMegabytes {
            case ...0.5: self = .upTo500kb
            case ...1: self = .upTo1mb
            case ...2: self = .upTo2mb
            case ...3: self = .upTo3mb
            case ...4: self = .upTo4mb
            case ...5: self = .upTo5mb
            case ...6: self = .upTo6mb
            case ...8: self = .upTo8mb
            case ...10: self = .upTo10mb
            case ...15: self = .upTo15mb
            case ...20: self = .upTo20mb
            case ...25: self = .upTo25mb
            case ...30: self = .upTo30mb
            case ...35: self = .upTo35mb
            case ...40: self = .upTo40mb
            case ...50: self = .upTo50mb
            case ...60: self = .upTo60mb
            case ...75: self = .upTo75mb
            case ...100: self = .upTo100mb
            default: self = .more
            }
        }
    }

}

// MARK: Helpers

private extension Int {

    var toMegabytes: Double {
        Measurement(value: Double(self), unit: UnitInformationStorage.bytes).converted(to: .megabytes).value
    }

}

// MARK: - Pixel Suffixes

public extension DataManager.StoredDataType.Kind {

    /// The dataset type as it appears in a pixel name: `hash-prefix` or `filter-set`.
    var pixelSuffix: String {
        switch self {
        case .hashPrefixSet: "hash-prefix"
        case .filterSet: "filter-set"
        }
    }

}
