//
//  InstallOriginVariantResolver.swift
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

public enum InstallOriginVariantResolver {
    static let requiredEntry = "home"
    static let maxDaysSinceInstall = 28

    /// Returns the install-origin `content` field when eligibility gates pass.
    ///
    /// Eligibility gates:
    /// 1.  Max 28 days since install.
    /// 2. Origin entry is `home`.
    /// 3. Origin campaign matches the requested campaign.
    ///
    /// Origin format: `funnel_entry_source_campaign_content` (see `InstallOriginParser`).
    public static func variant(origin: String,
                               requestedCampaign: String,
                               installDate: Date,
                               referenceDate: Date) -> String? {
        let daysSinceInstall = QuantisedTimePast.daysBetween(from: installDate, to: referenceDate)
        guard daysSinceInstall <= maxDaysSinceInstall,
              let components = InstallOriginParser.parse(origin),
              components.entry == requiredEntry,
              components.campaign == requestedCampaign,
              let content = components.content,
              !content.isEmpty else {
            return nil
        }

        return content
    }
}
