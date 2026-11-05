//
//  UserAssist.swift
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

/// Waits in C-S-S until `completeWhen` passes, handing the page to the user (`userTurnNeeded`) if it hasn't after `handOffAfterMs`.
struct UserAssistAction: Action {
    let id: String
    let actionType: ActionType
    let highlight: String?
    let handOffAfterMs: Int?
    let json: Data?

    enum CodingKeys: String, CodingKey {
        case id, actionType, highlight, handOffAfterMs
    }

    init(id: String,
         actionType: ActionType = .userAssist,
         highlight: String? = nil,
         handOffAfterMs: Int? = nil,
         json: Data? = nil) {
        self.id = id
        self.actionType = actionType
        self.highlight = highlight
        self.handOffAfterMs = handOffAfterMs
        self.json = json
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.actionType = try container.decode(ActionType.self, forKey: .actionType)
        self.highlight = try container.decodeIfPresent(String.self, forKey: .highlight)
        self.handOffAfterMs = try container.decodeIfPresent(Int.self, forKey: .handOffAfterMs)
        self.json = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(actionType, forKey: .actionType)
        try container.encodeIfPresent(highlight, forKey: .highlight)
        try container.encodeIfPresent(handOffAfterMs, forKey: .handOffAfterMs)
    }

    func with(json: Data?) -> UserAssistAction {
        UserAssistAction(id: id, actionType: actionType, highlight: highlight, handOffAfterMs: handOffAfterMs, json: json)
    }
}
