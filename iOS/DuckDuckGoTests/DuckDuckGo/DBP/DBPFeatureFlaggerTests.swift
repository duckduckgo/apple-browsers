//
//  DBPFeatureFlaggerTests.swift
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

import DataBrokerProtection_iOS
import FeatureFlags_iOS
@_spi(Testing) import Persistence
import Testing
@testable import DuckDuckGo

@Suite("DBP feature flagger")
struct DBPFeatureFlaggerTests {

    private func makeFlagger(enabledFeatureFlags: [FeatureFlag]) -> DBPFeatureFlagger {
        DBPFeatureFlagger(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFeatureFlags),
                          freemiumPIRDebugSettings: FreemiumPIRDebugSettings(keyValueStore: MockKeyValueFileStore()))
    }

    @available(iOS 16, *)
    @Test("Email opt-out is on when the dbpEmailOptOut flag is on", .timeLimit(.minutes(1)))
    func emailOptOutIsOnWhenTheFlagIsOn() {
        #expect(makeFlagger(enabledFeatureFlags: [.dbpEmailOptOut]).isEmailOptOutEnabled)
    }

    @available(iOS 16, *)
    @Test("Email opt-out is off when the dbpEmailOptOut flag is off", .timeLimit(.minutes(1)))
    func emailOptOutIsOffWhenTheFlagIsOff() {
        #expect(!makeFlagger(enabledFeatureFlags: []).isEmailOptOutEnabled)
    }
}
