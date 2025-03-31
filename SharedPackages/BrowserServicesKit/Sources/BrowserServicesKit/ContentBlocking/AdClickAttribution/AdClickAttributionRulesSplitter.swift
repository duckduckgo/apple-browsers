//
//  AdClickAttributionRulesSplitter.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import TrackerRadarKit

public struct AdClickAttributionRulesSplitter {

    public enum Constants {
        public static let attributionRuleListNamePrefix = "Attribution_"
        public static let attributionRuleListETagPrefix = "A_"
    }

    private let rulesList: ContentBlockerRulesList
    private let allowlistedTrackerNames: [String]

    // MARK: - API

    /// - Parameters:
    ///   - rulesList: Rules list to be split
    ///   - allowlistedTrackerNames: Tracker names to split by
    public init(rulesList: ContentBlockerRulesList, allowlistedTrackerNames: [String]) {
        self.rulesList = rulesList
        self.allowlistedTrackerNames = allowlistedTrackerNames
    }

    static public func blockingAttributionRuleListName(forListNamed name: String) -> String {
        return "\(Constants.attributionRuleListNamePrefix)\(name)"
    }

    /// - Returns: Split rules only if the input rulesList contains given tracker names to split by
    public func split() -> (ContentBlockerRulesList, ContentBlockerRulesList)? {
        guard !allowlistedTrackerNames.isEmpty, rulesList.contains(allowlistedTrackerNames) else { return nil }

        let splitTDS = rulesList.trackerData != nil ? split(tds: rulesList.trackerData!) : nil
        return (ContentBlockerRulesList(name: rulesList.name, trackerData: splitTDS?.0,
                                        fallbackTrackerData: split(tds: rulesList.fallbackTrackerData).0),
                ContentBlockerRulesList(name: Self.blockingAttributionRuleListName(forListNamed: rulesList.name),
                                        trackerData: splitTDS?.1, fallbackTrackerData: split(tds: rulesList.fallbackTrackerData).1))
    }

    private func split(tds: TrackerDataManager.DataSet) -> (TrackerDataManager.DataSet, TrackerDataManager.DataSet) {
        let regularTrackerData = makeRegularTrackerData(from: tds.tds)
        let attributionTrackerData = makeTrackerDataForAttribution(from: tds.tds)

        // Tweak ETag to prevent caching issues between changed lists
        return ((tds: regularTrackerData,
                 etag: Constants.attributionRuleListETagPrefix + tds.etag),
                (tds: attributionTrackerData,
                 etag: Constants.attributionRuleListETagPrefix + tds.etag))
    }

    private func makeRegularTrackerData(from trackerData: TrackerData) -> TrackerData {
        let trackers = trackerData.trackers.filter { !allowlistedTrackerNames.contains($0.key) }
        return TrackerData(trackers: trackers,
                           entities: trackerData.entities,
                           domains: trackerData.domains,
                           cnames: trackerData.cnames)
    }

    private func makeTrackerDataForAttribution(from trackerData: TrackerData) -> TrackerData {
        let allowlistedTrackers = trackerData.trackers.filter { allowlistedTrackerNames.contains($0.key) }
        let allowlistedTrackersOwners = allowlistedTrackers.values.compactMap { $0.owner?.name }

        var entities = [String: Entity]()
        for ownerName in allowlistedTrackersOwners {
            if let entity = trackerData.entities[ownerName] {
                entities[ownerName] = entity
            }
        }

        var domains = [String: String]()
        for entity in entities {
            for domain in entity.value.domains ?? [] {
                domains[domain] = entity.key
            }
        }
        return TrackerData(trackers: allowlistedTrackers, entities: entities, domains: domains, cnames: nil)
    }

}

private extension ContentBlockerRulesList {

    func contains(_ trackerNames: [String]) -> Bool {
        trackerData?.tds.contains(trackerNames) ?? false || fallbackTrackerData.tds.contains(trackerNames)
    }

}

private extension TrackerData {

    func contains(_ trackerNames: [String]) -> Bool {
        !Set(trackers.keys).isDisjoint(with: Set(trackerNames))
    }

}
