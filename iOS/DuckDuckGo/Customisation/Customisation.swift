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

final class Customisation {

    protocol Storage {
        var omnibarAccessoryType: String { get set }
    }

    var omnibarAccessoryType: OmniBarAccessoryType {
        guard featureFlagger.isFeatureOn(.customizableActionButton) else {
            return .share
        }
        return .share
    }

    let storage: Storage
    let featureFlagger: FeatureFlagger

    init(storage: Storage = DefaultCustomisationStorage(), featureFlagger: FeatureFlagger) {
        self.storage = storage
        self.featureFlagger = featureFlagger
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
