//
//  Customisation.swift
//  DuckDuckGo
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

import Persistence
import BrowserServicesKit
import Core

/// The intention is that this becomes a central location for customisation / personalisation configuration, but it's only for a PoC for one
/// item right now, so  am trying to minimise the amount of code touched as this could well get yeeted.
final class Customisation {

    protocol Storage {
        var omnibarAccessoryType: String { get set }
    }

    var isAvailable: Bool {
        return featureFlagger.isFeatureOn(.customizableActionButton)
    }

    var omnibarAccessoryType: OmniBarAccessoryType {
        get {
            guard isAvailable else { return .share }
            return OmniBarAccessoryType(rawValue: storage.omnibarAccessoryType) ?? .share
        }

        set {
            storage.omnibarAccessoryType = newValue.rawValue
            triggerSettingsChangedNotification()
        }
    }

    var storage: Storage
    let notificationCenter: NotificationCenter
    let featureFlagger: FeatureFlagger

    init(storage: Storage = DefaultCustomisationStorage(),
          notificationCenter: NotificationCenter = .default,
          featureFlagger: FeatureFlagger) {
        self.storage = storage
        self.notificationCenter = notificationCenter
        self.featureFlagger = featureFlagger
    }

    private func triggerSettingsChangedNotification() {
        notificationCenter.post(name: .customisationSettingsChanged, object: nil)
    }
}

class DefaultCustomisationStorage: Customisation.Storage {

    static let omnibarAccessoryTypeKey = "customisationOmnibarAccessory"

    let storage: KeyValueStoring

    init(storage: KeyValueStoring = UserDefaults.standard) {
        self.storage = storage
    }

    var omnibarAccessoryType: String {
        set {
            storage.set(newValue, forKey: Self.omnibarAccessoryTypeKey)
        }
        get {
            (storage.object(forKey: Self.omnibarAccessoryTypeKey) as? String) ?? OmniBarAccessoryType.share.rawValue
        }
    }

}

public extension NSNotification.Name {
    static let customisationSettingsChanged = Notification.Name("com.duckduckgo.customisation.settings.changed")
}
