//
//  NextStepsItemsVisibilityTests.swift
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
@_spi(Testing) import Persistence
import Testing
@testable import DuckDuckGo

@Suite("Next steps items visibility")
struct NextStepsItemsVisibilityTests {

    private let oneDay: TimeInterval = 24 * 60 * 60

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func everyItemShowsBeforeTheUserActsOnIt() {
        let visibility = NextStepsItemsVisibility(keyValueStore: MockThrowingKeyValueStore())
        #expect(visibility.isSetAsDefaultVisible)
        #expect(visibility.isAddToDockVisible)
        #expect(visibility.isAddWidgetVisible)
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func dockAndWidgetHideADayAfterTheFirstTap() {
        let store = MockThrowingKeyValueStore()
        var now: TimeInterval = 1_000_000
        let visibility = NextStepsItemsVisibility(keyValueStore: store, now: { now })

        visibility.recordAddToDockTapped()
        visibility.recordAddWidgetTapped()
        #expect(visibility.isAddToDockVisible)
        #expect(visibility.isAddWidgetVisible)

        now += oneDay + 1
        #expect(!visibility.isAddToDockVisible)
        #expect(!visibility.isAddWidgetVisible)
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func dockAndWidgetHideWhenTheNextStepsSectionIsHidden() throws {
        let store = MockThrowingKeyValueStore()
        try store.set(true, forKey: SettingsViewModel.Constants.nextStepsSectionHiddenKey)
        let visibility = NextStepsItemsVisibility(keyValueStore: store)
        #expect(!visibility.isAddToDockVisible)
        #expect(!visibility.isAddWidgetVisible)
        #expect(visibility.isSetAsDefaultVisible)
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func setAsDefaultHidesOnceDismissed() throws {
        let store = MockThrowingKeyValueStore()
        try store.set(true, forKey: SettingsViewModel.Constants.didDismissSetAsDefaultBrowserKey)
        #expect(!NextStepsItemsVisibility(keyValueStore: store).isSetAsDefaultVisible)
    }

    @available(iOS 16, *)
    @Test(.timeLimit(.minutes(1)))
    func tappingSetAsDefaultSchedulesTheDefaultBrowserCheck() throws {
        let store = MockThrowingKeyValueStore()
        NextStepsItemsVisibility(keyValueStore: store).recordSetAsDefaultTapped()
        #expect(try store.object(forKey: SettingsViewModel.Constants.shouldCheckIfDefaultBrowserKey) as? Bool == true)
    }

}
