//
//  AfterInactivityOptionAdapter.swift
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
import SwiftUI
import Persistence

/// Owns the "Opening Screen" option's in-memory state, its SwiftUI binding, and the write-through to `AfterInactivitySettingKeys.afterInactivityOption` storage.
/// Consumers observe the published value or drive it through `afterInactivityOptionBinding`; they don't talk to storage directly.
final class AfterInactivityOptionAdapter: ObservableObject {

    @Published var afterInactivityOption: AfterInactivityOption
    private let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>

    init(initialOption: AfterInactivityOption, keyValueStore: ThrowingKeyValueStoring) {
        self.afterInactivityOption = initialOption
        self.storage = keyValueStore.throwingKeyedStoring()
    }

    convenience init(keyValueStore: ThrowingKeyValueStoring, idleReturnEligibilityManager: IdleReturnEligibilityManaging) {
        self.init(initialOption: idleReturnEligibilityManager.effectiveAfterInactivityOption(),
                  keyValueStore: keyValueStore)
    }

    var afterInactivityOptionBinding: Binding<AfterInactivityOption> {
        Binding<AfterInactivityOption>(
            get: {
                self.afterInactivityOption
            },
            set: { newValue in
                self.afterInactivityOption = newValue
                try? self.storage.set(newValue.rawValue, for: \AfterInactivitySettingKeys.afterInactivityOption)
            }
        )
    }
}
