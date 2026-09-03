//
//  MultiTabAttachmentHackFeature.swift
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
import Persistence

/// Local switch for the multi-tab attachment hack phase.
///
/// Deliberately not a privacy config flag: the hack phase ships to nobody, so the gate stays on
/// the device and is flipped from the AI Chat debug screen. Production replaces this with a
/// privacy config feature flag.
struct MultiTabAttachmentHackFeature {

    enum Key: String {
        case isEnabled = "ai-chat.multi-tab-attachment.hack-phase.enabled"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var isMultiTabAttachmentHackPhaseEnabled: Bool {
        get { keyValueStore.object(forKey: Key.isEnabled.rawValue) as? Bool ?? false }
        nonmutating set { keyValueStore.set(newValue, forKey: Key.isEnabled.rawValue) }
    }
}
