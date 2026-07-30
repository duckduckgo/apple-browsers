//
//  PromoQueueFeatureState.swift
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

/// The resolved `modalPromptCoordination` flag reading.
enum PromoQueueFeatureTargetState: Equatable {
    case disabled
    case enabled

    init(isEnabled: Bool) {
        self = isEnabled ? .enabled : .disabled
    }
}

enum PromoQueueFeatureState: Equatable {
    /// Coordination is bypassed: the legacy modal and RMF paths are in force.
    case disabled
    /// The serialized flag-change barrier is up while moving to the carried target state: modal
    /// evaluation is deferred and public NTP admission cannot acquire a lease.
    case transitioning(to: PromoQueueFeatureTargetState)
    /// Coordinated admission is active.
    case enabled

    init(targetState: PromoQueueFeatureTargetState) {
        switch targetState {
        case .disabled:
            self = .disabled
        case .enabled:
            self = .enabled
        }
    }

    var isTransitioning: Bool {
        if case .transitioning = self {
            return true
        }
        return false
    }
}
