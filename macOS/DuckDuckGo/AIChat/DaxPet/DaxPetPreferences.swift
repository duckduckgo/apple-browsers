//
//  DaxPetPreferences.swift
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
import Persistence
import PrivacyConfig

final class DaxPetPreferences: ObservableObject {

    @Published var isEnabled: Bool {
        didSet { persistor.isEnabled = isEnabled }
    }

    /// Whether the setting is offered at all.
    var isAvailable: Bool {
        featureFlagger.isFeatureOn(.aiChatDaxPet)
    }

    /// Dax talks to Duck.ai, so he stays away while Duck.ai is off.
    var isEffectivelyEnabledPublisher: AnyPublisher<Bool, Never> {
        let aiChatMenuConfiguration = self.aiChatMenuConfiguration
        let featureFlagger = self.featureFlagger
        let changes = Publishers.Merge(aiChatMenuConfiguration.valuesChangedPublisher, featureFlagger.updatesPublisher)
            .map { _ in () }
            .prepend(())

        return Publishers.CombineLatest($isEnabled, changes)
            .map { isEnabled, _ in
                isEnabled && featureFlagger.isFeatureOn(.aiChatDaxPet) && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private var persistor: DaxPetPreferencesPersistor
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private let featureFlagger: FeatureFlagger

    init(persistor: DaxPetPreferencesPersistor,
         aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
         featureFlagger: FeatureFlagger) {
        self.persistor = persistor
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.featureFlagger = featureFlagger
        isEnabled = persistor.isEnabled
    }
}

protocol DaxPetPreferencesPersistor {
    var isEnabled: Bool { get set }
    /// Where Dax stands: the bottom-centre of his window, in screen coordinates.
    var position: CGPoint? { get set }
}

struct DaxPetPreferencesUserDefaultsPersistor: DaxPetPreferencesPersistor {

    enum Key: String {
        case isEnabled = "dax-pet.is-enabled"
        case position = "dax-pet.position"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var isEnabled: Bool {
        get { (try? keyValueStore.object(forKey: Key.isEnabled.rawValue) as? Bool) ?? false }
        nonmutating set { try? keyValueStore.set(newValue, forKey: Key.isEnabled.rawValue) }
    }

    var position: CGPoint? {
        get {
            guard let values = (try? keyValueStore.object(forKey: Key.position.rawValue)) as? [Double],
                  values.count == 2 else { return nil }
            return CGPoint(x: values[0], y: values[1])
        }
        nonmutating set {
            try? keyValueStore.set(newValue.map { [Double($0.x), Double($0.y)] }, forKey: Key.position.rawValue)
        }
    }
}
