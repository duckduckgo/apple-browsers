//
//  SystemPermissionClient.swift
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

import AVFoundation
import CoreLocation
import UIKit

/// A common authorization state for camera, microphone, and location permissions.
public enum SystemPermissionAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    /// The service is disabled or the system returned an unsupported authorization state.
    case unavailable
}

/// Provides a unified interface to system authorization for camera, microphone, and location.
/// It coalesces concurrent location authorization requests and forwards location updates.
@MainActor
public final class SystemPermissionClient: NSObject {

    public typealias LocationUpdate = Result<CLLocation, Error>

    public var locationUpdateHandler: ((LocationUpdate) -> Void)?

    private let locationManager: CLLocationManager
    private let locationServicesEnabled: () -> Bool
    private let avAuthorizationStatus: (AVMediaType) -> AVAuthorizationStatus
    private let avRequestAccess: (AVMediaType, @escaping @Sendable (Bool) -> Void) -> Void
    private let notificationCenter: NotificationCenter

    private var locationState: SystemPermissionAuthorizationState = .notDetermined
    private var locationAuthorizationContinuations = [CheckedContinuation<SystemPermissionAuthorizationState, Never>]()

    var pendingLocationAuthorizationRequestCount: Int {
        locationAuthorizationContinuations.count
    }

    public override convenience init() {
        self.init(locationManager: CLLocationManager(),
                  locationServicesEnabled: CLLocationManager.locationServicesEnabled,
                  avAuthorizationStatus: AVCaptureDevice.authorizationStatus,
                  avRequestAccess: AVCaptureDevice.requestAccess,
                  notificationCenter: .default)
    }

    init(locationManager: CLLocationManager,
         locationServicesEnabled: @escaping () -> Bool,
         avAuthorizationStatus: @escaping (AVMediaType) -> AVAuthorizationStatus,
         avRequestAccess: @escaping (AVMediaType, @escaping @Sendable (Bool) -> Void) -> Void,
         notificationCenter: NotificationCenter) {
        self.locationManager = locationManager
        self.locationServicesEnabled = locationServicesEnabled
        self.avAuthorizationStatus = avAuthorizationStatus
        self.avRequestAccess = avRequestAccess
        self.notificationCenter = notificationCenter
        super.init()

        locationManager.delegate = self
        refreshAuthorizationStates()
        notificationCenter.addObserver(self,
                                       selector: #selector(applicationDidBecomeActive),
                                       name: UIApplication.didBecomeActiveNotification,
                                       object: nil)
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    public func authorizationState(for permissionType: SitePermissionType) -> SystemPermissionAuthorizationState {
        switch permissionType {
        case .camera:
            Self.state(from: avAuthorizationStatus(.video))
        case .microphone:
            Self.state(from: avAuthorizationStatus(.audio))
        case .location:
            locationState
        }
    }

    public func requestAuthorization(for permissionType: SitePermissionType) async -> SystemPermissionAuthorizationState {
        switch permissionType {
        case .camera:
            return await requestAVAuthorization(for: .video)
        case .microphone:
            return await requestAVAuthorization(for: .audio)
        case .location:
            return await requestLocationAuthorization()
        }
    }

    public func refreshAuthorizationStates() {
        refreshLocationAuthorizationState()
    }

    public func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    public func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    private func refreshLocationAuthorizationState() {
        locationState = locationServicesEnabled() ? Self.state(from: locationManager.authorizationStatus) : .unavailable
        completePendingLocationAuthorizationRequestsIfNeeded()
    }

    private func completePendingLocationAuthorizationRequestsIfNeeded() {
        guard locationState != .notDetermined else { return }

        let continuations = locationAuthorizationContinuations
        locationAuthorizationContinuations.removeAll()
        continuations.forEach { $0.resume(returning: locationState) }
    }

    private func requestAVAuthorization(for mediaType: AVMediaType) async -> SystemPermissionAuthorizationState {
        let currentState = Self.state(from: avAuthorizationStatus(mediaType))
        guard currentState == .notDetermined else { return currentState }

        return await withCheckedContinuation { continuation in
            avRequestAccess(mediaType) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(returning: .unavailable)
                        return
                    }
                    continuation.resume(returning: Self.state(from: self.avAuthorizationStatus(mediaType)))
                }
            }
        }
    }

    private func requestLocationAuthorization() async -> SystemPermissionAuthorizationState {
        guard locationState == .notDetermined else { return locationState }

        return await withCheckedContinuation { continuation in
            let shouldRequest = locationAuthorizationContinuations.isEmpty
            locationAuthorizationContinuations.append(continuation)
            if shouldRequest {
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    @objc private func applicationDidBecomeActive() {
        refreshAuthorizationStates()
        // Core Location ignores authorization requests made while the app is inactive, so retry when it returns.
        if locationState == .notDetermined, !locationAuthorizationContinuations.isEmpty {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private static func state(from status: AVAuthorizationStatus) -> SystemPermissionAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }

    private static func state(from status: CLAuthorizationStatus) -> SystemPermissionAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }
}

extension SystemPermissionClient: @preconcurrency CLLocationManagerDelegate {

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshLocationAuthorizationState()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locations.forEach { locationUpdateHandler?(.success($0)) }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationUpdateHandler?(.failure(error))
    }
}
