//
//  TestSettingsProviding.swift
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

import Combine
import Foundation
@testable import EventHub

/// Test `EventHubSettingsProviding`. Take the publisher initialiser to drive enablement and settings
/// yourself mid-test (`EventHubFixture` pushes onto `CurrentValueSubject`s); take the JSON one for a
/// config that is fixed for the lifetime of the test.
struct TestSettingsProviding: EventHubSettingsProviding {
    let enabledPublisher: AnyPublisher<Bool, Never>
    let settingsPublisher: AnyPublisher<[String: Any]?, Never>

    init(enabled: AnyPublisher<Bool, Never>, settings: AnyPublisher<[String: Any]?, Never>) {
        enabledPublisher = enabled
        settingsPublisher = settings
    }

    init(json: String, enabled: AnyPublisher<Bool, Never> = Just(true).eraseToAnyPublisher()) {
        self.init(enabled: enabled, settings: Just(settingsDictionary(json)).eraseToAnyPublisher())
    }
}
