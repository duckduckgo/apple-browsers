//
//  TabContentCapabilityTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class TabContentCapabilityTests: XCTestCase {

    private let url = URL(string: "https://example.com")!

    // MARK: - canBeDuplicated

    func testCanBeDuplicated() {
        let cases: [(Tab.TabContent, Bool)] = [
            (.newtab, true),
            (.url(.duckDuckGo, source: .link), true),
            (.settings(pane: nil), false),
            (.bookmarks, true),
            (.history(pane: nil), true),
            (.onboarding, false),
            (.none, true),
            (.dataBrokerProtection, false),
            (.subscription(url), false),
            (.identityTheftRestoration(url), false),
            (.releaseNotes, false),
            (.webExtensionUrl(url), true),
            (.aiChat(url), true),
        ]
        for (content, expected) in cases {
            XCTAssertEqual(content.canBeDuplicated, expected, "\(content)")
        }
    }

    // MARK: - canBePinned

    func testCanBePinned() {
        let cases: [(Tab.TabContent, Bool)] = [
            (.newtab, true),
            (.url(.duckDuckGo, source: .link), true),
            (.settings(pane: nil), true),
            (.bookmarks, true),
            (.history(pane: nil), true),
            (.onboarding, false),
            (.none, false),
            (.dataBrokerProtection, true),
            (.subscription(url), true),
            (.identityTheftRestoration(url), true),
            (.releaseNotes, false),
            (.webExtensionUrl(url), false),
            (.aiChat(url), true),
        ]
        for (content, expected) in cases {
            XCTAssertEqual(content.canBePinned, expected, "\(content)")
        }
    }

    // MARK: - canBeBookmarked

    func testCanBeBookmarked() {
        let cases: [(Tab.TabContent, Bool)] = [
            (.newtab, false),
            (.url(.duckDuckGo, source: .link), true),
            (.settings(pane: nil), false),
            (.bookmarks, false),
            (.history(pane: nil), false),
            (.onboarding, false),
            (.none, false),
            (.dataBrokerProtection, true),
            (.subscription(url), true),
            (.identityTheftRestoration(url), true),
            (.releaseNotes, true),
            (.webExtensionUrl(url), true),
            (.aiChat(url), true),
        ]
        for (content, expected) in cases {
            XCTAssertEqual(content.canBeBookmarked, expected, "\(content)")
        }
    }
}
