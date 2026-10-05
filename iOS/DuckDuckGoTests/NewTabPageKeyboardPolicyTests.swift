//
//  NewTabPageKeyboardPolicyTests.swift
//  DuckDuckGo
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
import Testing
@testable import DuckDuckGo

struct NewTabPageKeyboardPolicyTests {

    @available(iOS 16, macOS 13, *)
    @Test(
        "App open follows New Tab on a New Tab Page, and App Launch elsewhere",
        .timeLimit(.minutes(1)),
        arguments: [false, true]
    )
    func whenAppOpensThenKeyboardFollowsTheSettingsTable(onNewTab: Bool) {
        let onAppLaunch = !onNewTab
        let policy = NewTabPageKeyboardPolicy(onNewTab: onNewTab, onAppLaunch: onAppLaunch)

        #expect(policy.showsKeyboardOnAppOpen(onNewTabPage: true) == onNewTab)
        #expect(policy.showsKeyboardOnAppOpen(onNewTabPage: false) == onAppLaunch)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "App open is a cold start or a return after more than 20 seconds in the background",
        .timeLimit(.minutes(1)),
        arguments: [
            (nil, true),
            (21, true),
            (20, false)
        ] as [(TimeInterval?, Bool)]
    )
    func whenReturningAfterTimeInBackgroundThenItIsAnAppOpenOnlyPastTheThreshold(secondsInBackground: TimeInterval?, isAppOpen: Bool) {
        let now = Date()
        let lastBackgroundDate = secondsInBackground.map { now.addingTimeInterval(-$0) }

        #expect(NewTabPageKeyboardPolicy.isAppOpen(lastBackgroundDate: lastBackgroundDate, now: now) == isAppOpen)
    }

}
