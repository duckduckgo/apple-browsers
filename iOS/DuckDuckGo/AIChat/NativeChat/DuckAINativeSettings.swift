//
//  DuckAINativeSettings.swift
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

import Core
import FeatureFlags_iOS
import Foundation
import PrivacyConfig

final class DuckAINativeSettings: ObservableObject {

    enum Mode: String, CaseIterable {
        case web
        case native
    }

    enum ProviderChoice: String, CaseIterable {
        case automatic
        case stub
        case foundationModels
        case mlx
    }

    static let shared = DuckAINativeSettings()

    @Published var mode: Mode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    @Published var provider: ProviderChoice {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }

    private let defaults: UserDefaults
    private let featureFlagger: FeatureFlagger

    init(defaults: UserDefaults = .standard, featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.defaults = defaults
        self.featureFlagger = featureFlagger
        mode = defaults.string(forKey: Keys.mode).flatMap(Mode.init) ?? .web
        provider = defaults.string(forKey: Keys.provider).flatMap(ProviderChoice.init) ?? .automatic
    }

    var isFeatureAvailable: Bool {
        featureFlagger.isFeatureOn(.duckAINativeMode)
    }

    var opensNewChatsNatively: Bool {
        isFeatureAvailable && mode == .native
    }

    private enum Keys {
        static let mode = "duckAINative.mode"
        static let provider = "duckAINative.provider"
    }
}
