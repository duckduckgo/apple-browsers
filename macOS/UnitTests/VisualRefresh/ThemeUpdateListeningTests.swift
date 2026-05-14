//
//  ThemeUpdateListeningTests.swift
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

import Combine
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class ThemeUpdateListeningTests: XCTestCase {

    func testSwitchingThemesTriggerApplyThemeInvocation() async {
        let themeManager = MockThemeManager()
        let sample = SampleUpdateListener(themeManager: themeManager)

        let nextTheme = ThemeStyle.buildThemeStyle(themeName: .green, featureFlagger: MockFeatureFlagger())
        let expectation = expectation(description: "Apply ThemeStyle Invocation")

        sample.onThemeUpdate = { theme in
            XCTAssert(Thread.isMainThread)
            XCTAssertEqual(theme.name, nextTheme.name)
            expectation.fulfill()
        }

        sample.subscribeToThemeChanges()
        themeManager.theme = nextTheme

        await fulfillment(of: [expectation], timeout: 1)
    }
}

// MARK: - ThemeUpdateListening Sample Implementation
//
private class SampleUpdateListener: ThemeUpdateListening {
    private(set) var themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    var onThemeUpdate: ((_ theme: ThemeStyleProviding) -> Void)?

    init(themeManager: ThemeManaging) {
        self.themeManager = themeManager
    }

    func applyThemeStyle(theme: ThemeStyleProviding) {
        onThemeUpdate?(theme)
    }
}
