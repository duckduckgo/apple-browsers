//
//  Navigate.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

struct NavigateAction: Action {
    let id: String
    let actionType: ActionType
    let url: String
    let ageRange: [String]?
    let dataSource: DataSource?
    let json: Data?

    enum CodingKeys: String, CodingKey {
        case id
        case actionType
        case url
        case ageRange
        case dataSource
    }

    init(id: String,
         actionType: ActionType,
         url: String,
         ageRange: [String]?,
         dataSource: DataSource?,
         json: Data? = nil) {
        self.id = id
        self.actionType = actionType
        self.url = url
        self.ageRange = ageRange
        self.dataSource = dataSource
        self.json = json
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        actionType = try container.decode(ActionType.self, forKey: .actionType)
        url = try container.decode(String.self, forKey: .url)
        ageRange = try container.decodeIfPresent([String].self, forKey: .ageRange)
        dataSource = try container.decodeIfPresent(DataSource.self, forKey: .dataSource)
        json = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(actionType, forKey: .actionType)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(ageRange, forKey: .ageRange)
        try container.encodeIfPresent(dataSource, forKey: .dataSource)
    }

    func with(json: Data?) -> NavigateAction {
        NavigateAction(id: id,
                       actionType: actionType,
                       url: url,
                       ageRange: ageRange,
                       dataSource: dataSource,
                       json: json)
    }
}
