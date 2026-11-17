//
//  VPNStartupGuard.swift
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

/// Persists startup blocking until a manual start clears it.
struct VPNStartupGuard {
    enum StartupDecision: Equatable {
        case allowed
        case blocked
    }

    private static let shutdownKey = "com.duckduckgo.vpn.shutdown"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private var isStartupBlocked: Bool {
        get { defaults.bool(forKey: Self.shutdownKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.shutdownKey) }
    }

    func prepareForStartup(startupMethod: StartupOptions.StartupMethod) -> StartupDecision {
        guard startupMethod == .automaticOnDemand else {
            isStartupBlocked = false
            return .allowed
        }

        return isStartupBlocked ? .blocked : .allowed
    }

    func blockStartup() {
        isStartupBlocked = true
    }
}
