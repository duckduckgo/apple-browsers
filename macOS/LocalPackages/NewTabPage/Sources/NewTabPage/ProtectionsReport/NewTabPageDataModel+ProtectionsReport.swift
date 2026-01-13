//
//  NewTabPageDataModel+ProtectionsReport.swift
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

extension NewTabPageDataModel {

    struct ProtectionsData: Encodable, Equatable {
        let totalCount: Int64
        let totalCookiePopUpsBlocked: Int64?

        enum CodingKeys: String, CodingKey {
            case totalCount, totalCookiePopUpsBlocked
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(totalCount, forKey: .totalCount)

            if let totalCookiePopUpsBlocked {
                try container.encode(totalCookiePopUpsBlocked, forKey: .totalCookiePopUpsBlocked)
            } else {
                try container.encodeNil(forKey: .totalCookiePopUpsBlocked)
            }
        }
    }

    struct ProtectionsDataLegacy: Encodable, Equatable {
        let totalCount: Int64
    }

    struct ProtectionsConfig: Codable, Equatable {
        let expansion: NewTabPageUserScript.WidgetConfig.Expansion
        let feed: Feed
        let showBurnAnimation: Bool
        let showProtectionsReportNewLabel: Bool
    }

    public enum Feed: String, Codable {
        case activity, privacyStats = "privacy-stats"
    }
}
