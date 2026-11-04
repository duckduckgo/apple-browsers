//
//  WebExtensionEventsListenerTests.swift
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

import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionEventsListenerTests: XCTestCase {

    private final class Tab: NSObject, WKWebExtensionTab {}

    func testWhenTheUserSwitchesTabsOrATabNavigates_ThenBrowsingActivityIsReported() {
        let listener = WebExtensionEventsListener()
        var activityCount = 0
        listener.onBrowsingActivity = { activityCount += 1 }

        listener.didActivateTab(Tab(), previousActiveTab: nil)
        listener.didChangeTabProperties(.URL, for: Tab())
        listener.didChangeTabProperties([.loading, .title], for: Tab())

        XCTAssertEqual(activityCount, 2)
    }
}
