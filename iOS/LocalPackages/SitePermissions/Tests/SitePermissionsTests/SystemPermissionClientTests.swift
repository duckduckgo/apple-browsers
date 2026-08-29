//
//  SystemPermissionClientTests.swift
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
import XCTest
@testable import SitePermissions

@MainActor
final class SystemPermissionClientTests: XCTestCase {

    func testWhenAuthorizationStatesAreReadThenAllFiveStatesRemainDistinct() {
        let manager = MockLocationManager()
        manager.authorizationStatusValue = .restricted
        let statuses: [AVMediaType: AVAuthorizationStatus] = [.video: .authorized, .audio: .denied]
        let client = makeClient(locationManager: manager, statuses: { statuses[$0] ?? .notDetermined })

        XCTAssertEqual(client.authorizationState(for: .camera), .authorized)
        XCTAssertEqual(client.authorizationState(for: .microphone), .denied)
        XCTAssertEqual(client.authorizationState(for: .location), .restricted)

        manager.authorizationStatusValue = .notDetermined
        client.refreshAuthorizationStates()
        XCTAssertEqual(client.authorizationState(for: .location), .notDetermined)

        let unavailableClient = makeClient(locationServicesEnabled: { false })
        XCTAssertEqual(unavailableClient.authorizationState(for: .location), .unavailable)
    }

    func testWhenCameraAndMicrophoneAreRequestedThenVideoAndAudioAreEvaluatedSeparately() async {
        var statuses: [AVMediaType: AVAuthorizationStatus] = [.video: .notDetermined, .audio: .notDetermined]
        var requestedMediaTypes = [AVMediaType]()
        var locationServicesQueryCount = 0
        let client = makeClient(locationServicesEnabled: {
            locationServicesQueryCount += 1
            return true
        }, statuses: { statuses[$0] ?? .notDetermined }) { mediaType, completion in
            requestedMediaTypes.append(mediaType)
            statuses[mediaType] = mediaType == .video ? .authorized : .denied
            completion(mediaType == .video)
        }

        let cameraState = await client.requestAuthorization(for: .camera)
        let microphoneState = await client.requestAuthorization(for: .microphone)

        XCTAssertEqual(requestedMediaTypes, [.video, .audio])
        XCTAssertEqual(cameraState, .authorized)
        XCTAssertEqual(microphoneState, .denied)
        XCTAssertEqual(locationServicesQueryCount, 1)
    }

    func testWhenLocationAuthorizationAndUpdatesAreRequestedThenOneManagerHandlesBoth() async {
        let manager = MockLocationManager()
        let authorizationRequested = expectation(description: "Location authorization requested")
        manager.requestAuthorizationHandler = { authorizationRequested.fulfill() }
        let expectedLocation = CLLocation(latitude: 37.3317, longitude: -122.0301)
        var receivedLocation: CLLocation?
        let client = makeClient(locationManager: manager)
        client.locationUpdateHandler = { result in
            receivedLocation = try? result.get()
        }

        let authorizationTask = Task { await client.requestAuthorization(for: .location) }
        await fulfillment(of: [authorizationRequested], timeout: 1.0)
        XCTAssertEqual(manager.requestAuthorizationCallCount, 1)

        manager.authorizationStatusValue = .authorizedWhenInUse
        manager.delegate?.locationManagerDidChangeAuthorization?(manager)
        let authorizationState = await authorizationTask.value
        XCTAssertEqual(authorizationState, .authorized)

        client.startUpdatingLocation()
        manager.delegate?.locationManager?(manager, didUpdateLocations: [expectedLocation])
        client.stopUpdatingLocation()

        XCTAssertEqual(manager.startUpdatingCallCount, 1)
        XCTAssertEqual(manager.stopUpdatingCallCount, 1)
        XCTAssertEqual(receivedLocation, expectedLocation)
    }

    func testWhenAppBecomesActiveWithPendingLocationRequestThenRequestCompletesWithRefreshedState() async {
        let manager = MockLocationManager()
        let notificationCenter = NotificationCenter()
        let authorizationRequested = expectation(description: "Location authorization requested")
        manager.requestAuthorizationHandler = { authorizationRequested.fulfill() }
        let client = makeClient(locationManager: manager, notificationCenter: notificationCenter)

        let authorizationTask = Task { await client.requestAuthorization(for: .location) }
        await fulfillment(of: [authorizationRequested], timeout: 1.0)

        manager.authorizationStatusValue = .denied
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let authorizationState = await authorizationTask.value
        XCTAssertEqual(authorizationState, .denied)
        XCTAssertEqual(client.pendingLocationAuthorizationRequestCount, 0)
    }

    func testWhenTwoLocationAuthorizationRequestsArePendingThenOneNativeRequestCompletesBoth() async {
        let manager = MockLocationManager()
        let authorizationRequested = expectation(description: "Location authorization requested")
        authorizationRequested.assertForOverFulfill = true
        manager.requestAuthorizationHandler = { authorizationRequested.fulfill() }
        let client = makeClient(locationManager: manager)

        let firstTask = Task { await client.requestAuthorization(for: .location) }
        await fulfillment(of: [authorizationRequested], timeout: 1.0)
        let secondTask = Task { await client.requestAuthorization(for: .location) }
        let didEnqueueBothRequests = await waitUntil {
            client.pendingLocationAuthorizationRequestCount == 2
        }
        XCTAssertTrue(didEnqueueBothRequests)
        XCTAssertEqual(manager.requestAuthorizationCallCount, 1)

        manager.authorizationStatusValue = .authorizedWhenInUse
        manager.delegate?.locationManagerDidChangeAuthorization?(manager)

        let firstState = await firstTask.value
        let secondState = await secondTask.value
        XCTAssertEqual(firstState, .authorized)
        XCTAssertEqual(secondState, .authorized)
        XCTAssertEqual(client.pendingLocationAuthorizationRequestCount, 0)
    }

    func testWhenAppBecomesActiveThenAuthorizationStatesAreRefreshed() {
        let notificationCenter = NotificationCenter()
        var cameraStatus = AVAuthorizationStatus.denied
        let client = makeClient(statuses: { _ in cameraStatus }, notificationCenter: notificationCenter)
        XCTAssertEqual(client.authorizationState(for: .camera), .denied)

        cameraStatus = .authorized
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(client.authorizationState(for: .camera), .authorized)
    }

    func testSettingsURLUsesApplicationSettingsDeepLink() {
        let client = makeClient()

        XCTAssertEqual(client.settingsURL, URL(string: UIApplication.openSettingsURLString))
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }

    private func makeClient(locationManager: MockLocationManager = MockLocationManager(),
                            locationServicesEnabled: @escaping () -> Bool = { true },
                            statuses: @escaping (AVMediaType) -> AVAuthorizationStatus = { _ in .notDetermined },
                            requestAccess: @escaping (AVMediaType, @escaping @Sendable (Bool) -> Void) -> Void = { _, _ in },
                            notificationCenter: NotificationCenter = NotificationCenter()) -> SystemPermissionClient {
        SystemPermissionClient(locationManager: locationManager,
                               locationServicesEnabled: locationServicesEnabled,
                               avAuthorizationStatus: statuses,
                               avRequestAccess: requestAccess,
                               notificationCenter: notificationCenter)
    }
}

private final class MockLocationManager: CLLocationManager {

    var authorizationStatusValue = CLAuthorizationStatus.notDetermined
    var requestAuthorizationHandler: (() -> Void)?
    private(set) var requestAuthorizationCallCount = 0
    private(set) var startUpdatingCallCount = 0
    private(set) var stopUpdatingCallCount = 0

    override var authorizationStatus: CLAuthorizationStatus {
        authorizationStatusValue
    }

    override func requestWhenInUseAuthorization() {
        requestAuthorizationCallCount += 1
        requestAuthorizationHandler?()
    }

    override func startUpdatingLocation() {
        startUpdatingCallCount += 1
    }

    override func stopUpdatingLocation() {
        stopUpdatingCallCount += 1
    }
}
