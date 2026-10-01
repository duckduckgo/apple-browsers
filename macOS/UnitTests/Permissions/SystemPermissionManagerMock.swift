//
//  SystemPermissionManagerMock.swift
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

import Combine
import Foundation
@testable import DuckDuckGo_Privacy_Browser

final class SystemPermissionManagerMock: SystemPermissionManagerProtocol {

    /// The authorization state to return for each permission type
    var authorizationStates: [PermissionType: SystemPermissionAuthorizationState] = [:]

    /// Default authorization state when not explicitly set
    var defaultAuthorizationState: SystemPermissionAuthorizationState = .authorized

    /// Track authorization requests for verification
    var authorizationRequestedFor: [PermissionType] = []

    /// Completion to call when authorization is requested (simulates async response)
    var authorizationRequestCompletion: ((PermissionType) -> SystemPermissionAuthorizationState)?

    /// When true, `requestAuthorization` keeps the completion in `pendingAuthorizationCompletions` instead of calling it
    var defersAuthorizationResponse = false
    private(set) var pendingAuthorizationCompletions: [(SystemPermissionAuthorizationState) -> Void] = []

    /// Suspends fresh status reads so tests can arrange refreshes racing system permission callbacks.
    var defersAuthorizationStateResponse = false
    private(set) var authorizationStateResponseCount = 0
    private(set) var pendingAuthorizationStateCompletions: [(SystemPermissionAuthorizationState) -> Void] = []

    /// Subject for controlling notification authorization state in tests
    var notificationAuthorizationStateSubject = CurrentValueSubject<SystemPermissionAuthorizationState, Never>(.notDetermined)

    @MainActor
    func authorizationState(for permissionType: PermissionType) async -> SystemPermissionAuthorizationState {
        if defersAuthorizationStateResponse {
            let state: SystemPermissionAuthorizationState = await withCheckedContinuation { continuation in
                pendingAuthorizationStateCompletions.append { continuation.resume(returning: $0) }
            }
            authorizationStateResponseCount += 1
            return state
        }
        if permissionType == .notification {
            return notificationAuthorizationStateSubject.value
        }
        return authorizationStates[permissionType] ?? defaultAuthorizationState
    }

    func cachedAuthorizationState(for permissionType: PermissionType) -> SystemPermissionAuthorizationState {
        if permissionType == .notification {
            return notificationAuthorizationStateSubject.value
        }
        return authorizationStates[permissionType] ?? defaultAuthorizationState
    }

    func isAuthorizationRequired(for permissionType: PermissionType) -> Bool {
        if permissionType == .notification {
            let state = notificationAuthorizationStateSubject.value
            switch state {
            case .notDetermined, .systemDisabled:
                return true
            case .authorized, .denied, .restricted:
                return false
            }
        }
        let state = authorizationStates[permissionType] ?? defaultAuthorizationState
        switch state {
        case .notDetermined, .systemDisabled:
            return true
        case .authorized, .denied, .restricted:
            return false
        }
    }

    @discardableResult
    func requestAuthorization(for permissionType: PermissionType, completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable? {
        authorizationRequestedFor.append(permissionType)

        if defersAuthorizationResponse {
            pendingAuthorizationCompletions.append(completion)
            return AnyCancellable {}
        }

        if let customCompletion = authorizationRequestCompletion {
            let state = customCompletion(permissionType)
            completion(state)
        } else {
            let state: SystemPermissionAuthorizationState
            if permissionType == .notification {
                state = notificationAuthorizationStateSubject.value
            } else {
                state = authorizationStates[permissionType] ?? defaultAuthorizationState
            }
            completion(state)
        }

        return AnyCancellable {}
    }
}
