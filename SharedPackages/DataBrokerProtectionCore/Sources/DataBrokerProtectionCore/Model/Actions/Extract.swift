//
//  Extract.swift
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

public struct ExtractAction: Action {
    public let id: String
    public let actionType: ActionType
    public let json: Data?

    init(id: String,
         actionType: ActionType,
         json: Data? = nil) {
        self.id = id
        self.actionType = actionType
        self.json = json
    }

    enum CodingKeys: CodingKey {
        case id
        case actionType
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        actionType = try container.decode(ActionType.self, forKey: .actionType)
        json = nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(actionType, forKey: .actionType)
    }

    public func with(json: Data?) -> ExtractAction {
        ExtractAction(id: id,
                      actionType: actionType,
                      json: json)
    }
}
