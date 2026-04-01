//
//  AutoplaySettingsTests.swift
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

import Testing
import Persistence
import PersistenceTestingUtils

@testable import DuckDuckGo

@Suite
struct AutoplaySettingsTests {

    private func makeSettings() -> (store: InMemoryKeyValueStore, settings: DefaultAutoplaySettings) {
        let store = InMemoryKeyValueStore()
        let storage: any KeyedStoring<AutoplaySettingKeys> = store.keyedStoring()
        let settings = DefaultAutoplaySettings(storage: storage)
        return (store, settings)
    }

    @Test("When no value is stored then default is block audio")
    func whenNoValueStoredThenDefaultIsBlockAudio() {
        // GIVEN
        let (_, settings) = makeSettings()

        // THEN
        #expect(settings.currentAutoplayBlockingMode == .blockAudio)
    }

    @Test("When mode is set then it is persisted")
    func whenModeIsSetThenItIsPersisted() {
        // GIVEN
        let (_, settings) = makeSettings()

        // WHEN
        settings.currentAutoplayBlockingMode = .blockAll

        // THEN
        #expect(settings.currentAutoplayBlockingMode == .blockAll)
    }

    @Test("When stored value is invalid then block audio is returned")
    func whenStoredValueIsInvalidThenBlockAudioIsReturned() {
        // GIVEN
        let (store, settings) = makeSettings()
        store.set("invalidValue", forKey: AutoplayStorageKeys.autoplayBlockingMode.rawValue)

        // THEN
        #expect(settings.currentAutoplayBlockingMode == .blockAudio)
    }
}
