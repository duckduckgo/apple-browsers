//
//  FillForm.swift
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

struct FillFormAction: Action {
    let id: String
    let actionType: ActionType
    let selector: String
    let elements: [PageElement]
    let dataSource: DataSource?
    let json: Data?

    enum CodingKeys: CodingKey {
        case id
        case actionType
        case selector
        case elements
        case dataSource
    }

    init(id: String,
         actionType: ActionType,
         selector: String,
         elements: [PageElement],
         dataSource: DataSource?,
         json: Data? = nil) {
        self.id = id
        self.actionType = actionType
        self.selector = selector
        self.elements = elements
        self.dataSource = dataSource
        self.json = json
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        actionType = try container.decode(ActionType.self, forKey: .actionType)
        selector = try container.decode(String.self, forKey: .selector)
        elements = try container.decode([PageElement].self, forKey: .elements)
        dataSource = try container.decodeIfPresent(DataSource.self, forKey: .dataSource)
        json = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(actionType, forKey: .actionType)
        try container.encode(selector, forKey: .selector)
        try container.encode(elements, forKey: .elements)
        try container.encodeIfPresent(dataSource, forKey: .dataSource)
    }

    var needsEmail: Bool {
        elements.contains { $0.type == "email" }
    }

    func with(json: Data?) -> FillFormAction {
        FillFormAction(id: id,
                       actionType: actionType,
                       selector: selector,
                       elements: elements,
                       dataSource: dataSource,
                       json: json)
    }
}
