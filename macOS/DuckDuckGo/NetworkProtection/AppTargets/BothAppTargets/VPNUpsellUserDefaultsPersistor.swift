//
//  VPNUpsellUserDefaultsPersistor.swift
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

import Foundation
import Persistence

protocol VPNUpsellUserDefaultsPersisting {
    var vpnUpsellDismissed: Bool { get set }
    var vpnUpsellFirstPinnedDate: Date? { get set }
}

struct VPNUpsellUserDefaultsPersistor: VPNUpsellUserDefaultsPersisting {

    enum Key: String {
        case vpnUpsellDismissed = "vpn.upsell.dismissed"
        case vpnUpsellFirstPinnedDate = "vpn.upsell.first-pinned-date"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var vpnUpsellDismissed: Bool {
        get { keyValueStore.object(forKey: Key.vpnUpsellDismissed.rawValue) as? Bool ?? false }
        set { keyValueStore.set(newValue, forKey: Key.vpnUpsellDismissed.rawValue) }
    }

    var vpnUpsellFirstPinnedDate: Date? {
        get { keyValueStore.object(forKey: Key.vpnUpsellFirstPinnedDate.rawValue) as? Date }
        set {
            if let value = newValue {
                keyValueStore.set(value, forKey: Key.vpnUpsellFirstPinnedDate.rawValue)
            } else {
                keyValueStore.removeObject(forKey: Key.vpnUpsellFirstPinnedDate.rawValue)
            }
        }
    }
}
