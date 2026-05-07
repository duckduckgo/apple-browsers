//
//  GenerateEmail.swift
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

/// Native-only action that generates an email for the current job and stashes it on the runner
/// (`SubJobWebRunning.fetchedEmail`) so subsequent actions — most notably `fillForm` — can reuse
/// it instead of fetching a fresh one. Expected to run at most once per job; the runner treats a
/// second invocation as an error.
struct GenerateEmailAction: Action {
    let id: String
    let actionType: ActionType
    let json: Data?

    enum CodingKeys: CodingKey {
        case id
        case actionType
    }

    init(id: String,
         actionType: ActionType,
         json: Data? = nil) {
        self.id = id
        self.actionType = actionType
        self.json = json
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        actionType = try container.decode(ActionType.self, forKey: .actionType)
        json = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(actionType, forKey: .actionType)
    }

    func with(json: Data?) -> GenerateEmailAction {
        GenerateEmailAction(id: id, actionType: actionType, json: json)
    }
}
