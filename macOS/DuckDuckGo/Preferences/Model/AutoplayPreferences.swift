//
//  AutoplayPreferences.swift
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
import PixelKit
import WebKit

enum AutoplayBlockingMode: String, CaseIterable, CustomStringConvertible {
    case allowAll
    case blockAudio
    case blockAll

    var description: String {
        switch self {
        case .allowAll: return UserText.autoplayModeAllowAll
        case .blockAudio: return UserText.autoplayModeBlockAudio
        case .blockAll: return UserText.autoplayModeBlockAll
        }
    }
}

protocol AutoplayPreferencesPersistor {
    var autoplayBlockingModeRawValue: String { get set }
    var seededDomains: [String] { get set }
}

struct AutoplayPreferencesUserDefaultsPersistor: AutoplayPreferencesPersistor {

    enum Key: String {
        case autoplayBlockingMode = "preferences.autoplay.blocking-mode"
        case seededDomains = "preferences.autoplay.seeded-domains"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var autoplayBlockingModeRawValue: String {
        get { keyValueStore.object(forKey: Key.autoplayBlockingMode.rawValue) as? String ?? AutoplayBlockingMode.blockAudio.rawValue }
        set { keyValueStore.set(newValue, forKey: Key.autoplayBlockingMode.rawValue) }
    }

    var seededDomains: [String] {
        get { keyValueStore.object(forKey: Key.seededDomains.rawValue) as? [String] ?? [] }
        set { keyValueStore.set(newValue, forKey: Key.seededDomains.rawValue) }
    }
}

final class AutoplayPreferences: ObservableObject {

    @Published var autoplayBlockingMode: AutoplayBlockingMode {
        didSet {
            guard oldValue != autoplayBlockingMode else {
                return
            }

            persistor.autoplayBlockingModeRawValue = autoplayBlockingMode.rawValue
            switch autoplayBlockingMode {
            case .allowAll:
                PixelKit.fire(GeneralPixel.autoplaySettingAllowAll, doNotEnforcePrefix: true)
            case .blockAudio:
                PixelKit.fire(GeneralPixel.autoplaySettingBlockAudio, doNotEnforcePrefix: true)
            case .blockAll:
                PixelKit.fire(GeneralPixel.autoplaySettingBlockAll, doNotEnforcePrefix: true)
            }
        }
    }

    init(persistor: AutoplayPreferencesPersistor = AutoplayPreferencesUserDefaultsPersistor()) {
        self.persistor = persistor
        self.autoplayBlockingMode = AutoplayBlockingMode(rawValue: persistor.autoplayBlockingModeRawValue) ?? .blockAudio
    }

    var seededDomains: [String] {
        get { persistor.seededDomains }
        set { persistor.seededDomains = newValue }
    }

    private var persistor: AutoplayPreferencesPersistor
}

extension AutoplayBlockingMode {

    var mediaTypesRequiringUserAction: WKAudiovisualMediaTypes {
        switch self {
        case .allowAll: return []
        case .blockAudio: return .audio
        case .blockAll: return .all
        }
    }
}
