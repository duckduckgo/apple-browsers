//
//  ExecuteScript.swift
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

struct ExecuteScriptAction: Action {
    let id: String
    let actionType: ActionType
    let script: String
    let failSilently: Bool
    let json: Data?

    enum CodingKeys: String, CodingKey {
        case id
        case actionType
        case script
        case failSilently
    }

    init(id: String,
         actionType: ActionType,
         script: String,
         failSilently: Bool = false,
         json: Data? = nil) {
        self.id = id
        self.actionType = actionType
        self.script = script
        self.failSilently = failSilently
        self.json = json
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        actionType = try container.decode(ActionType.self, forKey: .actionType)
        script = try container.decode(String.self, forKey: .script)
        failSilently = try container.decodeIfPresent(Bool.self, forKey: .failSilently) ?? false
        json = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(actionType, forKey: .actionType)
        try container.encode(script, forKey: .script)
        try container.encode(failSilently, forKey: .failSilently)
    }

    func with(json: Data?) -> ExecuteScriptAction {
        ExecuteScriptAction(id: id,
                            actionType: actionType,
                            script: script,
                            failSilently: failSilently,
                            json: json)
    }
}
