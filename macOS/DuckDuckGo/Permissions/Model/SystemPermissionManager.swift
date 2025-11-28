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

    // MARK: - Geolocation

    /// Returns the current geolocation authorization state
    var geolocationAuthorizationState: SystemPermissionAuthorizationState { get }

    /// Publisher that emits the current geolocation authorization state whenever it changes
    var geolocationAuthorizationStatePublisher: AnyPublisher<SystemPermissionAuthorizationState, Never> { get }

    /// Returns true if geolocation authorization has been granted
    var isGeolocationAuthorized: Bool { get }

    /// Returns true if geolocation authorization needs to be requested
    var isGeolocationAuthorizationRequired: Bool { get }

    /// Requests geolocation authorization from the system
    /// - Parameter completion: Called with the resulting authorization state after the user responds
    /// - Returns: A cancellable that can be used to cancel the observation
    @discardableResult
    func requestGeolocationAuthorization(completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable

    /// Requests geolocation authorization from the system using async/await
    /// - Returns: The authorization state after the user responds
    func requestGeolocationAuthorization() async -> SystemPermissionAuthorizationState
}

/// Manages system-level permissions required before website permissions can be granted
final class SystemPermissionManager: SystemPermissionManagerProtocol {

    private let geolocationService: GeolocationServiceProtocol

    init(geolocationService: GeolocationServiceProtocol = GeolocationService.shared) {
        self.geolocationService = geolocationService
    }

    // MARK: - Geolocation Authorization

    /// Returns the current geolocation authorization state
    var geolocationAuthorizationState: SystemPermissionAuthorizationState {
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

    /// Publisher that emits the current geolocation authorization state whenever it changes
    var geolocationAuthorizationStatePublisher: AnyPublisher<SystemPermissionAuthorizationState, Never> {
        geolocationService.authorizationStatusPublisher
            .map { [weak self] _ in
                self?.geolocationAuthorizationState ?? .notDetermined
            }
            .eraseToAnyPublisher()
    }

    /// Returns true if geolocation authorization has been granted
    var isGeolocationAuthorized: Bool {
        geolocationAuthorizationState == .authorized
    }

    /// Returns true if geolocation authorization needs to be requested
    var isGeolocationAuthorizationRequired: Bool {
        switch geolocationAuthorizationState {
        case .notDetermined, .systemDisabled:
            return true
        case .authorized, .denied, .restricted:
            return false
        }
    }

    /// Requests geolocation authorization from the system
    /// - Parameter completion: Called with the resulting authorization state after the user responds
    /// - Returns: A cancellable that can be used to cancel the observation
    @discardableResult
    func requestGeolocationAuthorization(completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable {
        // If already determined, return current state immediately
        guard geolocationAuthorizationState == .notDetermined else {
            completion(geolocationAuthorizationState)
            return AnyCancellable {}
        }

        var locationCancellable: AnyCancellable?

        // Subscribe to authorization status publisher to observe changes
        let authorizationCancellable = geolocationService.authorizationStatusPublisher
            .dropFirst() // Skip initial value, we want to observe changes
            .first() // Only need the first change
            .sink { [weak self] _ in
                let state = self?.geolocationAuthorizationState ?? .notDetermined
                // Cancel location subscription once we have the authorization result
                locationCancellable?.cancel()
                completion(state)
            }

        // Subscribe to location publisher to trigger authorization request
        // The GeolocationService calls requestWhenInUseAuthorization() when first subscribed
        // We keep this subscription alive until authorization is determined
        locationCancellable = geolocationService.locationPublisher
            .sink { _ in }

        return AnyCancellable {
            authorizationCancellable.cancel()
            locationCancellable?.cancel()
        }
    }

    /// Requests geolocation authorization from the system using async/await
    /// - Returns: The authorization state after the user responds
    func requestGeolocationAuthorization() async -> SystemPermissionAuthorizationState {
        // If already determined, return current state immediately
        guard geolocationAuthorizationState == .notDetermined else {
            return geolocationAuthorizationState
        }

        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = requestGeolocationAuthorization { state in
                continuation.resume(returning: state)
                cancellable?.cancel()
            }
        }
    }
}
