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
        public static let fromRevision = "fromRevision"
        public static let toRevision = "toRevision"
        public static let updateFrequencyMinutes = "updateFrequencyMinutes"
        public static let isFullReplacement = "isFullReplacement"
        public static let numberOfDataSetsProcessed = "numberOfDatasetsProcessed"
        public static let numberOfSuccessfulDataSetsUpdated = "numberOfSuccessfulDatasetsUpdated"
        public static let performanceBucket = "performanceBucket"
        public static let diskUsageBucket = "diskUsageBucket"
    }
}

public enum Event: PixelKitEvent {
    case errorPageShown(category: ThreatKind, clientSideHit: Bool?)
    case visitSite(category: ThreatKind)
    case iframeLoaded(category: ThreatKind)
    case settingToggled(to: Bool)
    case matchesApiTimeout
    case matchesApiFailure(Error)
    case failedToDownloadInitialDataSets(category: ThreatKind, type: DataManager.StoredDataType.Kind)
    #if os(iOS)
    case singleDataSetUpdatePerformance(SingleDataSetUpdatePerformanceInfo)
    case singleDataSetUpdateDiskUsage(SingleDataSetUpdateDiskUsageInfo)
    case aggregateDataSetUpdatePerformance(AggregateDataSetPerformanceInfo)
    case aggregateDataSetUpdateDiskUsage(AggregateDataSetUpdateDiskUsageInfo)
    #endif

    public var name: String {
        switch self {
        case .errorPageShown:
            return "malicious-site-protection_error-page-shown"
        case .visitSite:
            return "malicious-site-protection_visit-site"
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
        case .singleDataSetUpdatePerformance:
            return "malicious-site-protection_single-dataset-update-performance"
        case .singleDataSetUpdateDiskUsage:
            return "malicious-site-protection_single-dataset-update-disk-usage"
        case .aggregateDataSetUpdatePerformance:
            return "malicious-site-protection_aggregate-dataset-update-performance"
        case .aggregateDataSetUpdateDiskUsage:
            return "malicious-site-protection_aggregate-dataset-update-disk-usage"
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
        case .singleDataSetUpdatePerformance(let info):
            return [
                PixelKit.Parameters.category: info.category.rawValue,
                PixelKit.Parameters.datasetType: info.type.rawValue,
                PixelKit.Parameters.fromRevision: String(info.fromRevision),
                PixelKit.Parameters.toRevision: String(info.toRevision),
                PixelKit.Parameters.isFullReplacement: String(info.isFullReplacement),
                PixelKit.Parameters.updateFrequencyMinutes: String(info.updateFrequencyMinutes),
                PixelKit.Parameters.performanceBucket: info.performanceBucket
            ]
        case .singleDataSetUpdateDiskUsage(let info):
            return [
                PixelKit.Parameters.category: info.category.rawValue,
                PixelKit.Parameters.datasetType: info.type.rawValue,
                PixelKit.Parameters.toRevision: String(info.toRevision),
                PixelKit.Parameters.updateFrequencyMinutes: String(info.updateFrequencyMinutes),
                PixelKit.Parameters.diskUsageBucket: info.diskUsageBucket
            ]
        case .aggregateDataSetUpdatePerformance(let info):
            return [
                PixelKit.Parameters.datasetType: info.type.rawValue,
                PixelKit.Parameters.updateFrequencyMinutes: String(info.updateFrequencyMinutes),
                PixelKit.Parameters.performanceBucket: info.performanceBucket
            ]
        case .aggregateDataSetUpdateDiskUsage(let info):
            return [
                PixelKit.Parameters.datasetType: info.type.rawValue,
                PixelKit.Parameters.updateFrequencyMinutes: String(info.updateFrequencyMinutes),
                PixelKit.Parameters.diskUsageBucket: info.diskUsageBucket
            ]
        #endif
        }
    }

    public var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        #if os(iOS)
        case .errorPageShown,
                .visitSite,
                .iframeLoaded,
                .settingToggled,
                .matchesApiTimeout,
                .matchesApiFailure,
                .failedToDownloadInitialDataSets,
                .singleDataSetUpdatePerformance,
                .singleDataSetUpdateDiskUsage,
                .aggregateDataSetUpdatePerformance,
                .aggregateDataSetUpdateDiskUsage:
            return [.pixelSource]
        #else
        case .errorPageShown,
                .visitSite,
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
