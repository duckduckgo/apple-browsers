//
//  SystemPermissionManager.swift
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
import CoreLocation

/// Represents the authorization state for a system permission
enum SystemPermissionAuthorizationState {
    /// Permission has not been requested yet
    case notDetermined
    /// Permission has been granted
    case authorized
    /// Permission has been denied by the user
    case denied
    /// Permission is restricted (parental controls, MDM, etc.)
    case restricted
    /// Services are disabled system-wide (e.g., Location Services off in System Settings)
    case systemDisabled
}

/// Protocol for managing system-level permissions required before website permissions can be granted
protocol SystemPermissionManagerProtocol: AnyObject {

    /// Returns the current authorization state for the given permission type
    func authorizationState(for permissionType: PermissionType) -> SystemPermissionAuthorizationState

    /// Returns true if system authorization is required for the given permission type
    func isAuthorizationRequired(for permissionType: PermissionType) -> Bool

    /// Requests system authorization for the given permission type
    /// - Parameters:
    ///   - permissionType: The permission type to request authorization for
    ///   - completion: Called with the resulting authorization state
    /// - Returns: A cancellable that can be used to cancel the observation (for permissions that support it)
    @discardableResult
    func requestAuthorization(for permissionType: PermissionType, completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable?
}

/// Manages system-level permissions required before website permissions can be granted
final class SystemPermissionManager: SystemPermissionManagerProtocol {

    private let geolocationService: GeolocationServiceProtocol

    init(geolocationService: GeolocationServiceProtocol = GeolocationService.shared) {
        self.geolocationService = geolocationService
    }

    // MARK: - Public Methods

    /// Returns the current authorization state for the given permission type
    func authorizationState(for permissionType: PermissionType) -> SystemPermissionAuthorizationState {
        switch permissionType {
        case .geolocation:
            return geolocationAuthorizationState
        case .camera, .microphone, .popups, .externalScheme:
            return .authorized // These don't require system permission through our two-step flow
        }
    }

    /// Returns true if system authorization is required for the given permission type
    func isAuthorizationRequired(for permissionType: PermissionType) -> Bool {
        switch permissionType {
        case .geolocation:
            return isGeolocationAuthorizationRequired
        case .camera, .microphone, .popups, .externalScheme:
            return false // These don't require system permission through our two-step flow
        }
    }

    /// Requests system authorization for the given permission type
    @discardableResult
    func requestAuthorization(for permissionType: PermissionType, completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable? {
        switch permissionType {
        case .geolocation:
            return requestGeolocationAuthorization(completion: completion)
        case .camera, .microphone, .popups, .externalScheme:
            // These don't require system permission through our two-step flow
            completion(.authorized)
            return nil
        }
    }

    // MARK: - Private Geolocation Implementation

    private var geolocationAuthorizationState: SystemPermissionAuthorizationState {
        guard geolocationService.locationServicesEnabled() else {
            return .systemDisabled
        }

        switch geolocationService.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized, .authorizedAlways:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .notDetermined
        }
    }

    private var isGeolocationAuthorizationRequired: Bool {
        switch geolocationAuthorizationState {
        case .notDetermined, .systemDisabled:
            return true
        case .authorized, .denied, .restricted:
            return false
        }
    }

    @discardableResult
    private func requestGeolocationAuthorization(completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable {
        // If already determined, return current state immediately
        guard geolocationAuthorizationState == .notDetermined else {
            completion(geolocationAuthorizationState)
            return AnyCancellable {}
        }

        // Use a holder class to ensure proper capture semantics
        // This avoids the issue of capturing a nil variable before assignment
        let cancellableHolder = CancellableHolder()

        // Subscribe to authorization status publisher to observe changes
        let authorizationCancellable = geolocationService.authorizationStatusPublisher
            .dropFirst() // Skip initial value, we want to observe changes
            .first() // Only need the first change
            .sink { [weak self, cancellableHolder] _ in
                let state = self?.geolocationAuthorizationState ?? .notDetermined
                // Cancel location subscription once we have the authorization result
                cancellableHolder.cancellable?.cancel()
                completion(state)
            }

        // Subscribe to location publisher to trigger authorization request
        // The GeolocationService calls requestWhenInUseAuthorization() when first subscribed
        // We keep this subscription alive until authorization is determined
        cancellableHolder.cancellable = geolocationService.locationPublisher
            .sink { _ in }

        return AnyCancellable {
            authorizationCancellable.cancel()
            cancellableHolder.cancellable?.cancel()
        }
    }
}

/// Helper class to hold a cancellable reference for proper capture semantics in closures
private final class CancellableHolder {
    var cancellable: AnyCancellable?
}
