//
//  AutoconsentManagement.swift
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

import EventHub
import Foundation
import PixelKit
import WebExtensions

final class AutoconsentManagement {

    var sitesNotifiedCache = Set<String>()

    var pixelCounter = [CPMSiteRank?: [String: Int]]()

    var detectedByPatternsCache = Set<String>()
    var detectedByBothCache = Set<String>()
    var detectedOnlyRulesCache = Set<String>()

    /// Set once Event Hub exists, which is after this object is created.
    var eventHub: EventHubManaging?

    func fireSummaryPixels(additionalParameters: [String: String]) {
        for (siteRank, events) in pixelCounter {
            var parameters = additionalParameters
            parameters["siteRank"] = siteRank?.rawValue
            PixelKit.fire(AutoconsentPixel.summary(events: events), frequency: .standard, withAdditionalParameters: parameters)
            CPMCoverageReporter.report(summary: events, siteRank: siteRank) { eventHub?.handleNativeEvent($0) }
        }
        pixelCounter = [:]
        detectedByPatternsCache.removeAll()
        detectedByBothCache.removeAll()
        detectedOnlyRulesCache.removeAll()
    }

    func clearCache() {
        dispatchPrecondition(condition: .onQueue(.main))
        sitesNotifiedCache.removeAll()
        detectedByPatternsCache.removeAll()
        detectedByBothCache.removeAll()
        detectedOnlyRulesCache.removeAll()
    }

}
