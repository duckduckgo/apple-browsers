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
import Common
import Persistence

struct AIChatDebugURLSettings: StoringKeys {
    let customURL = StorageKey<String>(.aiChatDebugURLSettings)

    /// Testing builds of the local model select POC must reach the Duck.ai build that sends `select`,
    /// without anyone setting it in the Debug menu. Branch only: remove before merging.
    /// Tests keep their own custom URLs.
    static var forcedURL: String? {
        [.unitTests, .integrationTests].contains(AppVersion.runType) ? nil : "https://euw-serp-dev-testing3.duck.ai/"
    }
}

extension KeyedStoring where Keys == AIChatDebugURLSettings {

    /// The Debug menu's custom URL, unless this build forces one.
    var effectiveCustomURL: String? {
        AIChatDebugURLSettings.forcedURL ?? self.customURL
    }

    var customURLHostname: String? {
        if let customURL = effectiveCustomURL,
            let url = URL(string: customURL) {
            return url.host
        }
        return nil
    }

    func resetCustomURL() {
        self.customURL = nil
    }
}
