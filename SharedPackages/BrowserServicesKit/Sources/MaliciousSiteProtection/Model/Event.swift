//
//  Event.swift
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
import PixelKit

public extension PixelKit {
    enum Parameters: Hashable {
        public static let clientSideHit = "clientSideHit"
        public static let category = "category"
        public static let settingToggledTo = "newState"
        public static let datasetType = "type"
    }
}

public enum Event: PixelKit.Event {
    /// This pixel signature is non-standard and not aligned to the current PixelKit defaults. This policy freezes the signature by not sending the platform marker suffix.
    public var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyOmitted }

    case errorPageShown(category: ThreatKind, clientSideHit: Bool?)
    case visitSite(category: ThreatKind)
    case leaveSite(category: ThreatKind)
    case iframeLoaded(category: ThreatKind)
    case settingToggled(to: Bool)
    case matchesApiTimeout
    case matchesApiFailure(Error)
    case failedToDownloadInitialDataSets(category: ThreatKind, type: DataManager.StoredDataType.Kind)
    #if os(iOS)
    /// How long applying, encoding and writing a dataset update took.
    case dataSetUpdateTime(category: ThreatKind, type: DataManager.StoredDataType.Kind, bucket: DurationBucketAggregation)
    /// The size of the dataset file written after an update.
    case dataSetSize(category: ThreatKind, type: DataManager.StoredDataType.Kind, bucket: DatasetSizeBucketAggregation)
    /// The total time spent applying, encoding and writing the datasets an update round of `type` wrote.
    case dataSetAggregateUpdateTime(type: DataManager.StoredDataType.Kind, bucket: DurationBucketAggregation)
    /// The total size of the dataset files written in an update round of `type`.
    case dataSetAggregateSize(type: DataManager.StoredDataType.Kind, bucket: DatasetSizeBucketAggregation)
    #endif

    public var name: String {
        switch self {
        case .errorPageShown:
            return "malicious-site-protection_error-page-shown"
        case .visitSite:
            return "malicious-site-protection_visit-site"
        case .leaveSite:
            return "malicious-site-protection_leave-site"
        case .iframeLoaded:
            return "malicious-site-protection_iframe-loaded"
        case .settingToggled:
            return "malicious-site-protection_feature-toggled"
        case .matchesApiTimeout:
            return "malicious-site-protection_client-timeout"
        case .matchesApiFailure:
            return "malicious-site-protection_matches-api-error"
        case .failedToDownloadInitialDataSets:
            return "malicious-site-protection_failed-to-fetch-initial-datasets"
        #if os(iOS)
        case .dataSetUpdateTime(let category, let type, let bucket):
            return "malicious-site-protection_update-time_\(category.rawValue)_\(type.pixelSuffix)_\(bucket.rawValue)"
        case .dataSetSize(let category, let type, let bucket):
            return "malicious-site-protection_dataset-size_\(category.rawValue)_\(type.pixelSuffix)_\(bucket.rawValue)"
        case .dataSetAggregateUpdateTime(let type, let bucket):
            return "malicious-site-protection_update-time_aggregate_\(type.pixelSuffix)_\(bucket.rawValue)"
        case .dataSetAggregateSize(let type, let bucket):
            return "malicious-site-protection_dataset-size_aggregate_\(type.pixelSuffix)_\(bucket.rawValue)"
        #endif
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case .errorPageShown(category: let category, clientSideHit: let clientSideHit):
            let parameters = if let clientSideHit {
                [
                    PixelKit.Parameters.category: category.rawValue,
                    PixelKit.Parameters.clientSideHit: String(clientSideHit),
                ]
            } else {
                [
                    PixelKit.Parameters.category: category.rawValue,
                ]
            }
            return parameters
        case .visitSite(category: let category),
                .leaveSite(category: let category),
                .iframeLoaded(category: let category):
            return [
                PixelKit.Parameters.category: category.rawValue,
            ]
        case .settingToggled(let state):
            return [
                PixelKit.Parameters.settingToggledTo: String(state)
            ]
        case .matchesApiTimeout,
             .matchesApiFailure:
            return [:]
        case .failedToDownloadInitialDataSets(let category, let datasetType):
            return [
                PixelKit.Parameters.category: category.rawValue,
                PixelKit.Parameters.datasetType: datasetType.rawValue,
            ]
        #if os(iOS)
        case .dataSetUpdateTime,
             .dataSetSize,
             .dataSetAggregateUpdateTime,
             .dataSetAggregateSize:
            // Every value is in the name.
            return [:]
        #endif
        }
    }

    public var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        #if os(iOS)
        case .errorPageShown,
                .visitSite,
                .leaveSite,
                .iframeLoaded,
                .settingToggled,
                .matchesApiTimeout,
                .matchesApiFailure,
                .failedToDownloadInitialDataSets:
            return [.pixelSource]
        case .dataSetUpdateTime,
             .dataSetSize,
             .dataSetAggregateUpdateTime,
             .dataSetAggregateSize:
            return nil
        #else
        case .errorPageShown,
                .visitSite,
                .leaveSite,
                .iframeLoaded,
                .settingToggled,
                .matchesApiTimeout,
                .matchesApiFailure,
                .failedToDownloadInitialDataSets:
            return [.pixelSource]
        #endif
        }
    }
}
