//
//  Click.swift
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

struct ClickAction: Action {
    let id: String
    let actionType: ActionType
    let json: Data?

    init(id: String,
         actionType: ActionType,
         json: Data? = nil) {
       self.id = id
       self.actionType = actionType
       self.json = json
   }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.actionType = try container.decode(ActionType.self, forKey: .actionType)
        self.json = nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case actionType
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.actionType, forKey: .actionType)
    }

    func with(json: Data?) -> ClickAction {
        ClickAction(id: id,
                    actionType: actionType,
                    json: json)
    }
}
