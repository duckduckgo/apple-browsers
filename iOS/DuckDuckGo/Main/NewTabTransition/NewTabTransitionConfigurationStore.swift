//
//  NewTabTransitionConfigurationStore.swift
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
import Combine

/// Keeps the debug screen's transition values across launches.
final class NewTabTransitionConfigurationStore: ObservableObject {

    static let shared = NewTabTransitionConfigurationStore()

    private static let key = "com.duckduckgo.ios.newTabTransition.configuration.v10"

    @Published var configuration: NewTabTransitionConfiguration {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        configuration = Self.load(from: defaults)
    }

    func reset() {
        configuration = NewTabTransitionConfiguration()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func load(from defaults: UserDefaults) -> NewTabTransitionConfiguration {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(NewTabTransitionConfiguration.self, from: data) else {
            return NewTabTransitionConfiguration()
        }
        return stored
    }
}
