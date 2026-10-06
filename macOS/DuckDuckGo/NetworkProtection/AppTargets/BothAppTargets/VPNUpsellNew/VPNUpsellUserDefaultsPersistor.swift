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

/// Flags written by the pre-Promo-Queue VPN upsell. Production code only reads them to retire the promos for
/// users who already dismissed or timed out the legacy upsell; only the debug reset writes them.
protocol VPNUpsellUserDefaultsPersisting {
    var legacyUpsellDismissed: Bool { get set }
    var legacyPopoverViewed: Bool { get set }
    var legacyFirstPinnedDate: Date? { get set }
    var expectedUpsellTimeInterval: TimeInterval { get set }
}

extension VPNUpsellUserDefaultsPersisting {

    /// The legacy upsell dismissed itself this long after the button was first pinned.
    private var legacyAutoDismissInterval: TimeInterval { .days(7) }

    func isLegacyUpsellFinished(asOf now: Date) -> Bool {
        if legacyUpsellDismissed {
            return true
        }
        guard let firstPinnedDate = legacyFirstPinnedDate else {
            return false
        }
        return now.timeIntervalSince(firstPinnedDate) >= legacyAutoDismissInterval
    }
}

struct VPNUpsellUserDefaultsPersistor: VPNUpsellUserDefaultsPersisting {

    enum Key: String {
        case vpnUpsellDismissed = "vpn.upsell.dismissed"
        case vpnUpsellPopoverViewed = "vpn.upsell.popover.viewed"
        case vpnUpsellFirstPinnedDate = "vpn.upsell.first-pinned-date"
        case expectedUpsellTimeInterval = "vpn.upsell.expected.time.interval"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var legacyUpsellDismissed: Bool {
        get { (try? keyValueStore.object(forKey: Key.vpnUpsellDismissed.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.vpnUpsellDismissed.rawValue) }
    }

    var legacyPopoverViewed: Bool {
        get { (try? keyValueStore.object(forKey: Key.vpnUpsellPopoverViewed.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.vpnUpsellPopoverViewed.rawValue) }
    }

    var legacyFirstPinnedDate: Date? {
        get { try? keyValueStore.object(forKey: Key.vpnUpsellFirstPinnedDate.rawValue) as? Date }
        set {
            if let value = newValue {
                try? keyValueStore.set(value, forKey: Key.vpnUpsellFirstPinnedDate.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.vpnUpsellFirstPinnedDate.rawValue)
            }
        }
    }

    var expectedUpsellTimeInterval: TimeInterval {
        get { (try? keyValueStore.object(forKey: Key.expectedUpsellTimeInterval.rawValue) as? TimeInterval) ?? 10 * 60 }
        set { try? keyValueStore.set(newValue, forKey: Key.expectedUpsellTimeInterval.rawValue) }
    }
}
