//
//  UserText.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

public struct UserText {
    public enum BrowsersComparison {
        public enum Features {
            public static let privateSearch = NSLocalizedString("onboarding.browsers.features.privateSearch.title", bundle: Bundle.module, value: "Search privately by default", comment: "Message to highlight browser capability of private searches")
            public static let trackerBlockers = NSLocalizedString("onboarding.highlights.browsers.features.trackerBlocker.title", bundle: Bundle.module, value: "Block 3rd-party trackers", comment: "Message to highlight browser capability of blocking 3rd-party trackers")
            public static let cookiePopups = NSLocalizedString("onboarding.highlights.browsers.features.cookiePopups.title", bundle: Bundle.module, value: "Block cookie pop-ups", comment: "Message to highlight how the browser allows you to block cookie pop-ups")
            public static let creepyAds = NSLocalizedString("onboarding.highlights.browsers.features.creepyAds.title", bundle: Bundle.module, value: "Block targeted ads", comment: "Message to highlight browser capability of blocking creepy ads")
            public static let eraseBrowsingData = NSLocalizedString("onboarding.highlights.browsers.features.eraseBrowsingData.title", bundle: Bundle.module, value: "Delete browsing data with one button", comment: "Message to highlight browser capability of swiftly erase browsing data")
        }
    }
}
