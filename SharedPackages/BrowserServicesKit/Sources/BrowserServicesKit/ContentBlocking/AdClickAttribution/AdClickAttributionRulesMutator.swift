//
//  AdClickAttributionRulesMutator.swift
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
import Foundation

public class AdClickAttributionRulesMutator {

    var trackerData: TrackerData
    var config: AdClickAttributing

    public init(trackerData: TrackerData, config: AdClickAttributing) {
        self.trackerData = trackerData
        self.config = config
    }

    public func addException(vendorDomain: String) -> TrackerData {
        guard config.isEnabled else { return trackerData }

        let attributedMatching = KnownTracker.Rule.Matching(domains: [vendorDomain.droppingWwwPrefix()], types: nil)

        var attributedTrackers = [TrackerData.TrackerDomain: KnownTracker]()

        for (entity, tracker) in trackerData.trackers {
            let allowlistEntries = config.allowlist.filter { $0.entity == entity }
            guard !allowlistEntries.isEmpty else {
                attributedTrackers[entity] = tracker
                continue
            }

            var updatedRules = tracker.rules ?? []
            for allowlistEntry in allowlistEntries {
                updatedRules.insert(KnownTracker.Rule(rule: normalizeRule(allowlistEntry.host),
                                                      surrogate: nil,
                                                      action: .block,
                                                      options: nil,
                                                      exceptions: attributedMatching),
                                    at: 0)
            }

            attributedTrackers[entity] = KnownTracker(domain: tracker.domain,
                                                      defaultAction: tracker.defaultAction,
                                                      owner: tracker.owner,
                                                      prevalence: tracker.prevalence,
                                                      subdomains: tracker.subdomains,
                                                      categories: tracker.categories,
                                                      rules: updatedRules)
        }

        return TrackerData(trackers: attributedTrackers,
                           entities: trackerData.entities,
                           domains: trackerData.domains,
                           cnames: trackerData.cnames)
    }

    private func normalizeRule(_ rule: String) -> String {
        var rule = rule.hasSuffix("/") ? rule : rule + "/"
        let index = rule.firstIndex(of: "/")
        if let index = index {
            rule.insert(contentsOf: "(:[0-9]+)?", at: index)
        }
        rule = rule.replacingOccurrences(of: ".", with: "\\.")
        return rule + ".*"
    }
}
