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
        let client = makeClient(statuses: { statuses[$0] ?? .notDetermined }) { mediaType, completion in
            requestedMediaTypes.append(mediaType)
            statuses[mediaType] = mediaType == .video ? .authorized : .denied
            completion(mediaType == .video)
        }

        let cameraState = await client.requestAuthorization(for: .camera)
        let microphoneState = await client.requestAuthorization(for: .microphone)

        XCTAssertEqual(requestedMediaTypes, [.video, .audio])
        XCTAssertEqual(cameraState, .authorized)
        XCTAssertEqual(microphoneState, .denied)
    }

    func testWhenLocationAuthorizationAndUpdatesAreRequestedThenOneManagerHandlesBoth() async {
        let manager = MockLocationManager()
        let authorizationRequested = expectation(description: "Location authorization requested")
        manager.requestAuthorizationHandler = { authorizationRequested.fulfill() }
        let expectedLocation = CLLocation(latitude: 37.3317, longitude: -122.0301)
        var receivedLocation: CLLocation?
        let client = makeClient(locationManager: manager)
        let updateHandler = client.addLocationUpdateHandler { result in
            receivedLocation = try? result.get()
        }

        let authorizationTask = Task { await client.requestAuthorization(for: .location) }
        await fulfillment(of: [authorizationRequested], timeout: 1.0)
        XCTAssertEqual(manager.requestAuthorizationCallCount, 1)

        manager.authorizationStatusValue = .authorizedWhenInUse
        manager.delegate?.locationManagerDidChangeAuthorization?(manager)
        let authorizationState = await authorizationTask.value
        XCTAssertEqual(authorizationState, .authorized)

        manager.delegate?.locationManager?(manager, didUpdateLocations: [expectedLocation])
        client.removeLocationUpdateHandler(updateHandler)

        XCTAssertEqual(manager.startUpdatingCallCount, 1)
        XCTAssertEqual(manager.stopUpdatingCallCount, 1)
        XCTAssertEqual(receivedLocation, expectedLocation)
    }

    func testLocationUpdateHandlersShareOneManagerUntilLastHandlerIsRemoved() {
        let manager = MockLocationManager()
        let client = makeClient(locationManager: manager)
        var firstLocations = [CLLocation]()
        var secondLocations = [CLLocation]()

        let first = client.addLocationUpdateHandler { result in
            if let location = try? result.get() {
                firstLocations.append(location)
            }
        }
        let second = client.addLocationUpdateHandler { result in
            if let location = try? result.get() {
                secondLocations.append(location)
            }
        }
        let firstLocation = CLLocation(latitude: 37.3317, longitude: -122.0301)
        manager.delegate?.locationManager?(manager, didUpdateLocations: [firstLocation])

        client.removeLocationUpdateHandler(first)
        let secondLocation = CLLocation(latitude: 51.5072, longitude: -0.1276)
        manager.delegate?.locationManager?(manager, didUpdateLocations: [secondLocation])
        client.removeLocationUpdateHandler(second)

        XCTAssertEqual(manager.startUpdatingCallCount, 1)
        XCTAssertEqual(manager.stopUpdatingCallCount, 1)
        XCTAssertEqual(firstLocations, [firstLocation])
        XCTAssertEqual(secondLocations, [firstLocation, secondLocation])
    }

    func testLocationUpdateHandlersAggregateAccuracyAcrossConsumers() {
        let manager = MockLocationManager()
        let client = makeClient(locationManager: manager)

        let standardAccuracy = client.addLocationUpdateHandler(highAccuracy: false) { _ in }
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyHundredMeters)
        XCTAssertEqual(manager.startUpdatingCallCount, 1)

        let highAccuracy = client.addLocationUpdateHandler(highAccuracy: true) { _ in }
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyBest)
        XCTAssertEqual(manager.startUpdatingCallCount, 1)

        client.updateLocationUpdateHandler(standardAccuracy, highAccuracy: true)
        client.removeLocationUpdateHandler(highAccuracy)
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyBest)
        XCTAssertEqual(manager.stopUpdatingCallCount, 0)

        client.updateLocationUpdateHandler(standardAccuracy, highAccuracy: false)
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyHundredMeters)

        client.removeLocationUpdateHandler(standardAccuracy)
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyHundredMeters)
        XCTAssertEqual(manager.stopUpdatingCallCount, 1)
    }

    func testLocationUpdateHandlersReceiveOnlyNewestBatchedLocation() {
        let manager = MockLocationManager()
        let client = makeClient(locationManager: manager)
        var receivedLocations = [CLLocation]()
        let handler = client.addLocationUpdateHandler { result in
            if let location = try? result.get() {
                receivedLocations.append(location)
            }
        }
        let olderLocation = CLLocation(latitude: 37.3317, longitude: -122.0301)
        let newestLocation = CLLocation(latitude: 51.5072, longitude: -0.1276)

        manager.delegate?.locationManager?(manager, didUpdateLocations: [olderLocation, newestLocation])
        client.removeLocationUpdateHandler(handler)

        XCTAssertEqual(receivedLocations, [newestLocation])
    }

    func testLocationUpdateHandlersReceiveNewestValidFixAndIgnoreAllInvalidBatch() {
        let manager = MockLocationManager()
        let client = makeClient(locationManager: manager)
        var receivedLocations = [CLLocation]()
        let handler = client.addLocationUpdateHandler { result in
            if let location = try? result.get() {
                receivedLocations.append(location)
            }
        }
        let olderValid = CLLocation(latitude: 37.3317, longitude: -122.0301)
        let invalidAccuracy = CLLocation(coordinate: .init(latitude: 48.8566, longitude: 2.3522),
                                         altitude: 0,
                                         horizontalAccuracy: -1,
                                         verticalAccuracy: -1,
                                         timestamp: Date())
        let newestValid = CLLocation(latitude: 51.5072, longitude: -0.1276)
        let invalidCoordinate = CLLocation(latitude: 100, longitude: 0)

        manager.delegate?.locationManager?(
            manager,
            didUpdateLocations: [olderValid, invalidAccuracy, newestValid, invalidCoordinate]
        )
        manager.delegate?.locationManager?(manager, didUpdateLocations: [invalidAccuracy, invalidCoordinate])
        client.removeLocationUpdateHandler(handler)

        XCTAssertEqual(receivedLocations, [newestValid])
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

    func testWhenLocationRequestDoesNotChangeStateThenAppActivationRetriesIt() async {
        let manager = MockLocationManager()
        let notificationCenter = NotificationCenter()
        let client = makeClient(locationManager: manager, notificationCenter: notificationCenter)

        let authorizationTask = Task { await client.requestAuthorization(for: .location) }
        let didEnqueueRequest = await waitUntil {
            client.pendingLocationAuthorizationRequestCount == 1
        }
        XCTAssertTrue(didEnqueueRequest)
        XCTAssertEqual(manager.requestAuthorizationCallCount, 1)

        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(manager.requestAuthorizationCallCount, 2)

        manager.authorizationStatusValue = .authorizedWhenInUse
        manager.delegate?.locationManagerDidChangeAuthorization?(manager)

        let authorizationState = await authorizationTask.value
        XCTAssertEqual(authorizationState, .authorized)
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
