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

// MARK: - Performance Event Info

/// Information about dataset update performance (time-based metrics only).
public struct SingleDataSetUpdatePerformanceInfo: Equatable, CustomDebugStringConvertible {
    /// The threat category being updated (malware, phishing, or scam)
    public let category: ThreatKind
    /// The type of dataset being updated (hashPrefixSet or filterSet)
    public let type: DataManager.StoredDataType.Kind
    /// The revision number before the update
    public let fromRevision: Int
    /// The revision number after the update
    public let toRevision: Int
    /// Whether this was a full dataset replacement (true) or incremental update (false)
    public let isFullReplacement: Bool
    /// The configured update frequency for this dataset type, in minutes
    public let updateFrequencyMinutes: Double
    /// Performance bucket classification (fast, normal, slow, outlier)
    public let performanceBucket: String

    public init(
        category: ThreatKind,
        type: DataManager.StoredDataType.Kind,
        fromRevision: Int,
        toRevision: Int,
        isFullReplacement: Bool,
        updateFrequencyMinutes: Double,
        performanceBucket: String
    ) {
        self.category = category
        self.type = type
        self.fromRevision = fromRevision
        self.toRevision = toRevision
        self.isFullReplacement = isFullReplacement
        self.updateFrequencyMinutes = updateFrequencyMinutes
        self.performanceBucket = performanceBucket
    }

    public var debugDescription: String {
        let updateType = isFullReplacement ? "replace" : "incremental"
        return "SingleDataSetUpdatePerformanceInfo(category: \(category.rawValue), type: \(type.rawValue), rev: \(fromRevision)→\(toRevision), updateType: \(updateType), frequency: \(updateFrequencyMinutes)min, bucket: \(performanceBucket))"
    }
}

/// Information about dataset update disk usage (disk-based metrics only).
public struct SingleDataSetUpdateDiskUsageInfo: Equatable, CustomDebugStringConvertible {
    /// The threat category being updated (malware, phishing, or scam)
    public let category: ThreatKind
    /// The type of dataset being updated (hashPrefixSet or filterSet)
    public let type: DataManager.StoredDataType.Kind
    /// The revision number after the update
    public let toRevision: Int
    /// The configured update frequency for this dataset type, in minutes
    public let updateFrequencyMinutes: Double
    /// Disk usage bucket classification (small, medium, large, xlarge)
    public let diskUsageBucket: String

    public init(
        category: ThreatKind,
        type: DataManager.StoredDataType.Kind,
        toRevision: Int,
        updateFrequencyMinutes: Double,
        diskUsageBucket: String
    ) {
        self.category = category
        self.type = type
        self.toRevision = toRevision
        self.updateFrequencyMinutes = updateFrequencyMinutes
        self.diskUsageBucket = diskUsageBucket
    }

    public var debugDescription: String {
        return "SingleDataSetUpdateDiskUsageInfo(category: \(category.rawValue), type: \(type.rawValue), rev: \(toRevision), frequency: \(updateFrequencyMinutes)min, bucket: \(diskUsageBucket))"
    }
}

/// Information about aggregate dataset update performance across all threat categories.
public struct AggregateDataSetPerformanceInfo: Equatable, CustomDebugStringConvertible {
    /// The type of dataset being updated (hashPrefixSet or filterSet)
    public let type: DataManager.StoredDataType.Kind
    /// The configured update frequency for this dataset type, in minutes
    public let updateFrequencyMinutes: Double
    /// Performance bucket classification (fast, normal, slow, outlier)
    public let performanceBucket: String

    public init(
        type: DataManager.StoredDataType.Kind,
        updateFrequencyMinutes: Double,
        performanceBucket: String
    ) {
        self.type = type
        self.updateFrequencyMinutes = updateFrequencyMinutes
        self.performanceBucket = performanceBucket
    }

    public var debugDescription: String {
        return "AggregateDataSetPerformanceInfo(type: \(type.rawValue), bucket: \(performanceBucket))"
    }
}

/// Information about aggregate dataset update disk usage across all threat categories.
public struct AggregateDataSetUpdateDiskUsageInfo: Equatable, CustomDebugStringConvertible {
    /// The type of dataset being updated (hashPrefixSet or filterSet)
    public let type: DataManager.StoredDataType.Kind
    /// The configured update frequency for this dataset type, in minutes
    public let updateFrequencyMinutes: Double
    /// Disk usage bucket classification (small, medium, large, xlarge)
    public let diskUsageBucket: String

    public init(
        type: DataManager.StoredDataType.Kind,
        updateFrequencyMinutes: Double,
        diskUsageBucket: String
    ) {
        self.type = type
        self.updateFrequencyMinutes = updateFrequencyMinutes
        self.diskUsageBucket = diskUsageBucket
    }

    public var debugDescription: String {
        return "AggregateUpdateDiskUsageInfo(type: \(type.rawValue), bucket: \(diskUsageBucket))"
    }
}

// MARK: - Performance Buckets

/// Performance bucket categorisation for malicious site protection dataset updates.
enum DataSetUpdatePerformanceBucket: String {
    case fast
    case normal
    case slow
    case outlier

    /// Performance thresholds for malicious site protection dataset updates.
    ///
    /// All thresholds based on pure I/O time measurements (excluding network API calls)
    /// from performance tests running on iPhone 15 Pro with current production dataset sizes
    /// (as of Jan 2026, revision `1813852`).
    ///
    /// Current Dataset Sizes:
    /// - HashPrefix: 567K items total (29K scam, 84K malware, 454K phishing)
    /// - FilterSet: 165K items total (12K scam, 18K malware, 135K phishing)
    ///
    /// Performance Test Results (iPhone 15 Pro, pure I/O time):
    /// - HashPrefix aggregate: 0.219s (device test), 0.323s (production, 1.47× overhead)
    /// - FilterSet aggregate: 0.228s (device test), 0.478s (production, 2.10× overhead)
    ///
    /// Key Performance Findings:
    /// - Incremental and full replacement updates have identical performance (both load/save entire dataset)
    /// - Small vs large incremental updates perform identically (time dominated by dataset I/O)
    /// - Production overhead (1.5-2×) comes from main thread contention, background tasks, and I/O contention
    ///
    /// Bucket Design Philosophy:
    /// - fast: Optimal performance (near device test baseline)
    /// - normal: Normal performance (accounts for device age, storage fullness, I/O contention)
    /// - slow: Degraded performance (device under load, thermal throttling, or heavy I/O)
    /// - outlier: Severe performance issues requiring investigation
    private enum Thresholds {
        /// Single HashPrefix update (per threat)
        /// Device test baseline: ~0.073s per threat (0.219s aggregate ÷ 3 threats)
        /// Production observed: ~0.108s per threat (0.323s aggregate ÷ 3 threats, iPhone 15 Pro)
        enum HashPrefixSingle {
            static let fast: TimeInterval = 0.25       // Optimal performance
            static let normal: TimeInterval = 0.5      // Normal performance
            static let slow: TimeInterval = 1.0        // Degraded performance
        }

        /// Single FilterSet update (per threat)
        /// Device test baseline: ~0.076s per threat (0.228s aggregate ÷ 3 threats)
        /// Production observed: ~0.159s per threat (0.478s aggregate ÷ 3 threats, iPhone 15 Pro)
        enum FilterSetSingle {
            static let fast: TimeInterval = 0.5        // Optimal performance
            static let normal: TimeInterval = 1.0      // Normal performance
            static let slow: TimeInterval = 2.0        // Degraded performance
        }

        /// Aggregate HashPrefix update (all 3 threats combined)
        /// Device test baseline: 0.219s
        /// Production observed: 0.323s (iPhone 15 Pro, 1.47× overhead)
        enum HashPrefixAggregate {
            static let fast: TimeInterval = 0.25       // Optimal performance
            static let normal: TimeInterval = 2.0      // Normal performance
            static let slow: TimeInterval = 4.0        // Degraded performance
        }

        /// Aggregate FilterSet update (all 3 threats combined)
        /// Device test baseline: 0.228s
        /// Production observed: 0.478s (iPhone 15 Pro, 2.10× overhead)
        enum FilterSetAggregate {
            static let fast: TimeInterval = 0.5        // Optimal performance
            static let normal: TimeInterval = 2.5      // Normal performance
            static let slow: TimeInterval = 4.0        // Degraded performance
        }
    }

    /// Determines the performance bucket for a dataset update.
    ///
    /// Note: Both incremental and full replacement updates use the same thresholds because
    /// processing time is dominated by loading/saving the entire dataset, not by the number
    /// of items being added or replaced.
    static func bucketForSingleDataSetUpdate(
        type: DataManager.StoredDataType.Kind,
        processingTime: TimeInterval
    ) -> DataSetUpdatePerformanceBucket {
        switch type {
        case .hashPrefixSet:
            if processingTime < Thresholds.HashPrefixSingle.fast {
                return .fast
            } else if processingTime < Thresholds.HashPrefixSingle.normal {
                return .normal
            } else if processingTime < Thresholds.HashPrefixSingle.slow {
                return .slow
            } else {
                return .outlier
            }

        case .filterSet:
            if processingTime < Thresholds.FilterSetSingle.fast {
                return .fast
            } else if processingTime < Thresholds.FilterSetSingle.normal {
                return .normal
            } else if processingTime < Thresholds.FilterSetSingle.slow {
                return .slow
            } else {
                return .outlier
            }
        }
    }

    /// Determines the performance bucket for an aggregate update (all 3 threat categories combined).
    static func bucketForAggregateDataSetsUpdate(
        type: DataManager.StoredDataType.Kind,
        totalProcessingTime: TimeInterval
    ) -> DataSetUpdatePerformanceBucket {
        switch type {
        case .hashPrefixSet:
            if totalProcessingTime < Thresholds.HashPrefixAggregate.fast {
                return .fast
            } else if totalProcessingTime < Thresholds.HashPrefixAggregate.normal {
                return .normal
            } else if totalProcessingTime < Thresholds.HashPrefixAggregate.slow {
                return .slow
            } else {
                return .outlier
            }

        case .filterSet:
            if totalProcessingTime < Thresholds.FilterSetAggregate.fast {
                return .fast
            } else if totalProcessingTime < Thresholds.FilterSetAggregate.normal {
                return .normal
            } else if totalProcessingTime < Thresholds.FilterSetAggregate.slow {
                return .slow
            } else {
                return .outlier
            }
        }
    }

}

// MARK: - Disk Usage Buckets

/// Disk usage bucket categorisation for malicious site protection dataset updates.
enum DataSetUpdateDiskUsageBucket: String {
    case small
    case medium
    case large
    case xlarge

    /// Disk usage thresholds for malicious site protection dataset updates.
    ///
    /// All thresholds based on production JSON file sizes (as of Jan 2026, revision `1813852`).
    ///
    /// Current Production Dataset Sizes:
    /// - HashPrefix: 6.6 MB total (0.62 MB scam, 0.86 MB malware, 5.1 MB phishing)
    /// - FilterSet: 29.5 MB total (1.4 MB scam, 2.5 MB malware, 25.6 MB phishing)
    ///
    /// Bucket Design Philosophy:
    /// - small: Typical size for scam datasets (smallest threat category)
    /// - medium: Typical size for malware datasets (mid-sized threat category)
    /// - large: Typical size for phishing datasets (largest threat category)
    /// - xlarge: Indicates dataset growth or anomaly requiring investigation
    ///
    /// The thresholds use production JSON file sizes to establish realistic baselines,
    /// with headroom for growth before triggering the next bucket tier.
    private enum DiskThresholds {
        /// Single HashPrefix update (per threat)
        /// Production sizes: scam 0.62 MB, malware 0.86 MB, phishing 5.1 MB
        enum HashPrefixSingle {
            static let small: Double = 0.5      // < 0.5 MB (below scam)
            static let medium: Double = 2.0     // < 2.0 MB (malware range)
            static let large: Double = 8.0      // < 8.0 MB (phishing range with headroom)
        }

        /// Single FilterSet update (per threat)
        /// Production sizes: scam 1.4 MB, malware 2.5 MB, phishing 25.6 MB
        enum FilterSetSingle {
            static let small: Double = 2.0      // < 2.0 MB (scam range)
            static let medium: Double = 5.0     // < 5.0 MB (malware range with headroom)
            static let large: Double = 30.0     // < 30 MB (phishing range with headroom)
        }

        /// Aggregate HashPrefix update (all 3 threats combined)
        /// Production total: 6.6 MB
        enum HashPrefixAggregate {
            static let small: Double = 3.0      // < 3.0 MB (significantly below current)
            static let medium: Double = 6.0     // < 6.0 MB (slightly below current baseline)
            static let large: Double = 12.0     // < 12.0 MB (2× current, significant growth)
        }

        /// Aggregate FilterSet update (all 3 threats combined)
        /// Production total: 29.5 MB
        enum FilterSetAggregate {
            static let small: Double = 15.0     // < 15.0 MB (significantly below current)
            static let medium: Double = 30.0    // < 30.0 MB (current production baseline)
            static let large: Double = 50.0     // < 50.0 MB (2× current, significant growth)
        }
    }

    /// Determines the disk usage bucket for a single dataset update (per threat).
    static func bucketForSingleDataSetUpdate(
        type: DataManager.StoredDataType.Kind,
        diskWritesMB: Double
    ) -> DataSetUpdateDiskUsageBucket {
        switch type {
        case .hashPrefixSet:
            if diskWritesMB < DiskThresholds.HashPrefixSingle.small {
                return .small
            } else if diskWritesMB < DiskThresholds.HashPrefixSingle.medium {
                return .medium
            } else if diskWritesMB < DiskThresholds.HashPrefixSingle.large {
                return .large
            } else {
                return .xlarge
            }

        case .filterSet:
            if diskWritesMB < DiskThresholds.FilterSetSingle.small {
                return .small
            } else if diskWritesMB < DiskThresholds.FilterSetSingle.medium {
                return .medium
            } else if diskWritesMB < DiskThresholds.FilterSetSingle.large {
                return .large
            } else {
                return .xlarge
            }
        }
    }

    /// Determines the disk usage bucket for an aggregate update (all 3 threat categories combined).
    static func bucketForAggregateDataSetsUpdate(
        type: DataManager.StoredDataType.Kind,
        totalDiskWritesMB: Double
    ) -> DataSetUpdateDiskUsageBucket {
        switch type {
        case .hashPrefixSet:
            if totalDiskWritesMB < DiskThresholds.HashPrefixAggregate.small {
                return .small
            } else if totalDiskWritesMB < DiskThresholds.HashPrefixAggregate.medium {
                return .medium
            } else if totalDiskWritesMB < DiskThresholds.HashPrefixAggregate.large {
                return .large
            } else {
                return .xlarge
            }

        case .filterSet:
            if totalDiskWritesMB < DiskThresholds.FilterSetAggregate.small {
                return .small
            } else if totalDiskWritesMB < DiskThresholds.FilterSetAggregate.medium {
                return .medium
            } else if totalDiskWritesMB < DiskThresholds.FilterSetAggregate.large {
                return .large
            } else {
                return .xlarge
            }
        }
    }
}
