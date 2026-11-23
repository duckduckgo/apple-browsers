//
//  AIChatDebugURLSettings.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import Persistence

struct AIChatDebugURLSettings: StoringKeys {
    let customURL = StorageKey<String>(.aiChatDebugURLSettings)
}

extension KeyedStoring where Keys == AIChatDebugURLSettings {

    // TEMP: preset dev server for test builds. Remove before merging.
    var customURLOrTempDevURL: String? {
        self.customURL ?? "http://euw-serp-dev-testing14.duck.ai/"
    }

    var customURLHostname: String? {
        if let customURL = self.customURLOrTempDevURL,
            let url = URL(string: customURL) {
            return url.host
        }
        return nil
    }

    func resetCustomURL() {
        self.customURL = nil
    }
}
