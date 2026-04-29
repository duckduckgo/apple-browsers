//
//  GetEmailData.swift
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

/// Native-only action that polls the backend for email-derived data (verification codes, links,
/// arbitrary extracted key/value pairs) tied to an email generated earlier in the current job by
/// a `generateEmail` action. Extracted values are stashed on `SubJobWebRunning.emailData` so
/// subsequent C-S-S actions (most commonly a `fillForm`) receive them under `data.emailData.{key}`
/// in the `onActionReceived` payload.
///
/// Polling is inline (action-scoped): the runner calls the V1 email-data endpoint once per
/// `pollingTime` seconds until the backend reports `status == .ready`, subject to the
/// wall-clock `getEmailDataTotalTimeout` on `BrokerJobExecutionConfig`. The action is
/// non-retryable — polling is itself the retry.
struct GetEmailDataAction: Action {
    let id: String
    let actionType: ActionType
    let pollingTime: TimeInterval
    let extract: [String]
    let json: Data?

    enum CodingKeys: CodingKey {
        case id
        case actionType
        case pollingTime
        case extract
    }

    init(id: String,
         actionType: ActionType,
         pollingTime: TimeInterval,
         extract: [String] = [],
         json: Data? = nil) {
        self.id = id
        self.actionType = actionType
        self.pollingTime = pollingTime
        self.extract = extract
        self.json = json
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        actionType = try container.decode(ActionType.self, forKey: .actionType)
        pollingTime = try container.decode(TimeInterval.self, forKey: .pollingTime)
        extract = try container.decodeIfPresent([String].self, forKey: .extract) ?? []
        json = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(actionType, forKey: .actionType)
        try container.encode(pollingTime, forKey: .pollingTime)
        if !extract.isEmpty {
            try container.encode(extract, forKey: .extract)
        }
    }

    func with(json: Data?) -> GetEmailDataAction {
        GetEmailDataAction(id: id,
                           actionType: actionType,
                           pollingTime: pollingTime,
                           extract: extract,
                           json: json)
    }
}
