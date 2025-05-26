//
//  ContentBlockingRulesHelper.swift
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

import Foundation
import TrackerRadarKit
import BrowserServicesKit
import WebKit

@MainActor
final class ContentBlockingRulesHelper {

    func makeFakeTDS() -> TrackerData {

        let tracker = KnownTracker(domain: "tracker.com",
                                   defaultAction: .block,
                                   owner: KnownTracker.Owner(name: "Tracker", displayName: "Tracker", ownedBy: nil),
                                   prevalence: 0.1,
                                   subdomains: nil,
                                   categories: nil,
                                   rules: nil)

        let entity = Entity(displayName: "Tracker", domains: ["tracker.com"], prevalence: 0.1)

        let tds = TrackerData(trackers: ["tracker.com": tracker],
                              entities: ["Tracker": entity],
                              domains: ["tracker.com": "Tracker"],
                              cnames: nil)

        return tds
    }

    func makeFakeRules(name: String) async -> ContentBlockerRulesManager.Rules? {
        return await makeFakeRules(name: name,
                                   tdsEtag: UUID().uuidString)
    }

    func makeFakeRules(name: String,
                       tdsEtag: String,
                       tempListId: String? = nil,
                       allowListId: String? = nil,
                       unprotectedSitesHash: String? = nil) async -> ContentBlockerRulesManager.Rules? {

        let identifier = ContentBlockerRulesIdentifier(name: name,
                                                       tdsEtag: tdsEtag,
                                                       tempListId: tempListId,
                                                       allowListId: allowListId,
                                                       unprotectedSitesHash: unprotectedSitesHash)
        let tds = makeFakeTDS()

        let builder = ContentBlockerRulesBuilder(trackerData: tds)
        let rules = builder.buildRules()

        let data: Data
        do {
            data = try JSONEncoder().encode(rules)
        } catch {
            return nil
        }

        let ruleList = String(data: data, encoding: .utf8)!

        guard let compiledRules = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier.stringValue,
                                                                                               encodedContentRuleList: ruleList) else {
            return nil
        }

        return .init(name: name,
                     rulesList: compiledRules,
                     trackerData: tds,
                     encodedTrackerData: "",
                     etag: tdsEtag,
                     identifier: identifier)
    }
}
