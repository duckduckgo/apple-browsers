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

public enum SystemPermissionAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

@MainActor
public final class SystemPermissionClient: NSObject {

    public typealias LocationUpdate = Result<CLLocation, Error>

    public var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    public var locationUpdateHandler: ((LocationUpdate) -> Void)?

    private let locationManager: CLLocationManager
    private let locationServicesEnabled: () -> Bool
    private let avAuthorizationStatus: (AVMediaType) -> AVAuthorizationStatus
    private let avRequestAccess: (AVMediaType, @escaping @Sendable (Bool) -> Void) -> Void
    private let notificationCenter: NotificationCenter

    private var cameraState: SystemPermissionAuthorizationState = .notDetermined
    private var microphoneState: SystemPermissionAuthorizationState = .notDetermined
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
            cameraState
        case .microphone:
            microphoneState
        case .location:
            locationState
        }
    }

    public func requestAuthorization(for permissionType: SitePermissionType) async -> SystemPermissionAuthorizationState {
        switch permissionType {
        case .camera:
            return await requestAVAuthorization(for: .video, permissionType: .camera)
        case .microphone:
            return await requestAVAuthorization(for: .audio, permissionType: .microphone)
        case .location:
            return await requestLocationAuthorization()
        }
    }

    public func refreshAuthorizationStates() {
        refreshAVAuthorizationState(for: .camera, mediaType: .video)
        refreshAVAuthorizationState(for: .microphone, mediaType: .audio)
        refreshLocationAuthorizationState()
    }

    public func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    public func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    private func refreshAVAuthorizationState(for permissionType: SitePermissionType, mediaType: AVMediaType) {
        let state = Self.state(from: avAuthorizationStatus(mediaType))
        switch permissionType {
        case .camera:
            cameraState = state
        case .microphone:
            microphoneState = state
        case .location:
            assertionFailure("Location does not use AV authorization")
        }
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

    private func requestAVAuthorization(for mediaType: AVMediaType,
                                        permissionType: SitePermissionType) async -> SystemPermissionAuthorizationState {
        let currentState = authorizationState(for: permissionType)
        guard currentState == .notDetermined else { return currentState }

        return await withCheckedContinuation { continuation in
            avRequestAccess(mediaType) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(returning: .unavailable)
                        return
                    }
                    self.refreshAVAuthorizationState(for: permissionType, mediaType: mediaType)
                    continuation.resume(returning: self.authorizationState(for: permissionType))
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
