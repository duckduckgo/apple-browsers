//
//  GeolocationProviderTests.swift
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
import XCTest
@testable import SitePermissions

@MainActor
final class GeolocationProviderTests: XCTestCase {

    func testOneShotUsesNewestBatchedUpdateOnceAndStopsSharedManager() async throws {
        let harness = try Harness()
        let task = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil { harness.locationManager.startUpdatingCallCount == 1 }

        let first = CLLocation(latitude: 37.3317, longitude: -122.0301)
        let second = CLLocation(latitude: 51.5072, longitude: -0.1276)
        harness.send([first, second])

        let result = await task.value
        XCTAssertEqual(result, .success(.init(location: second)))
        XCTAssertEqual(harness.locationManager.startUpdatingCallCount, 1)
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 1)
    }

    func testOneShotKeepsWaitingAfterInvalidBatchAndUsesNextValidFix() async throws {
        let harness = try Harness()
        let task = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil { harness.locationManager.startUpdatingCallCount == 1 }
        let invalidAccuracy = CLLocation(coordinate: .init(latitude: 48.8566, longitude: 2.3522),
                                         altitude: 0,
                                         horizontalAccuracy: -1,
                                         verticalAccuracy: -1,
                                         timestamp: Date())
        let invalidCoordinate = CLLocation(latitude: 100, longitude: 0)

        harness.send([invalidAccuracy, invalidCoordinate])
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 0)

        let validLocation = CLLocation(latitude: 37.3317, longitude: -122.0301)
        harness.send([validLocation])

        let result = await task.value
        XCTAssertEqual(result, .success(.init(location: validLocation)))
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 1)
    }

    func testMaximumAgeReusesRecentLocationWithoutRestartingManager() async throws {
        let harness = try Harness()
        let initialTask = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil { harness.locationManager.startUpdatingCallCount == 1 }
        let location = CLLocation(coordinate: .init(latitude: 37.3317, longitude: -122.0301),
                                  altitude: 0,
                                  horizontalAccuracy: 5,
                                  verticalAccuracy: -1,
                                  timestamp: Date())
        harness.send([location])
        _ = await initialTask.value

        let cachedResult = await harness.provider.requestCurrentPosition(
            context: harness.context,
            options: .init(maximumAge: 1)
        )

        XCTAssertEqual(cachedResult, .success(.init(location: location)))
        XCTAssertEqual(harness.locationManager.startUpdatingCallCount, 1)
    }

    func testMaximumAgeZeroRejectsStaleNativeFix() async throws {
        let harness = try Harness()
        let task = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil { harness.locationManager.startUpdatingCallCount == 1 }
        let staleLocation = CLLocation(coordinate: .init(latitude: 37.3317, longitude: -122.0301),
                                       altitude: 0,
                                       horizontalAccuracy: 5,
                                       verticalAccuracy: -1,
                                       timestamp: Date().addingTimeInterval(-60))
        let freshLocation = CLLocation(coordinate: .init(latitude: 51.5072, longitude: -0.1276),
                                       altitude: 0,
                                       horizontalAccuracy: 5,
                                       verticalAccuracy: -1,
                                       timestamp: Date())

        harness.send([staleLocation])
        harness.send([freshLocation])

        let result = await task.value
        XCTAssertEqual(result, .success(.init(location: freshLocation)))
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 1)
    }

    func testWatchesReceiveRepeatedUpdatesAndCancellationPreventsLateCallbacks() throws {
        let harness = try Harness()
        var firstResults = [GeolocationPositionResult]()
        var secondResults = [GeolocationPositionResult]()
        harness.provider.startWatch(withID: "first", context: harness.context) {
            firstResults.append($0)
            return true
        }
        harness.provider.startWatch(withID: "second", context: harness.context) {
            secondResults.append($0)
            return true
        }

        let firstLocation = CLLocation(latitude: 37.3317, longitude: -122.0301)
        harness.send([firstLocation])
        harness.provider.cancelWatch(withID: "first")
        let secondLocation = CLLocation(latitude: 51.5072, longitude: -0.1276)
        harness.send([secondLocation])
        harness.provider.cancelWatch(withID: "second")
        harness.send([CLLocation(latitude: 48.8566, longitude: 2.3522)])

        XCTAssertEqual(firstResults, [.success(.init(location: firstLocation))])
        XCTAssertEqual(secondResults, [.success(.init(location: firstLocation)), .success(.init(location: secondLocation))])
        XCTAssertEqual(harness.locationManager.startUpdatingCallCount, 1)
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 1)
    }

    func testLocationActivityReportsOnlyWatchBoundaryTransitions() throws {
        let harness = try Harness()
        var activity = [Bool]()
        harness.provider.locationActivityHandler = { activity.append($0) }

        harness.provider.startWatch(withID: "first", context: harness.context) { _ in true }
        harness.provider.startWatch(withID: "second", context: harness.context) { _ in true }
        harness.provider.cancelWatch(withID: "first")
        harness.provider.cancelWatch(withID: "second")

        XCTAssertEqual(activity, [true, false])
        XCTAssertFalse(harness.provider.isLocationActive)
    }

    func testLocationActivityReportsOneShotStartAndCompletionOnce() async throws {
        let harness = try Harness()
        var activity = [Bool]()
        harness.provider.locationActivityHandler = { activity.append($0) }

        let request = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil { harness.provider.isLocationActive }
        harness.send([CLLocation(latitude: 37.3317, longitude: -122.0301)])
        _ = await request.value

        XCTAssertEqual(activity, [true, false])
        XCTAssertFalse(harness.provider.isLocationActive)
    }

    func testCachedOneShotStillReportsACompleteActivityBoundaryWithoutRestartingLocationUpdates() async throws {
        let harness = try Harness()
        let cachedLocation = CLLocation(latitude: 37.3317, longitude: -122.0301)
        harness.provider.startWatch(withID: "seed", context: harness.context) { _ in true }
        harness.send([cachedLocation])
        harness.provider.cancelWatch(withID: "seed")
        let initialStartCount = harness.locationManager.startUpdatingCallCount
        var activity = [Bool]()
        harness.provider.locationActivityHandler = { activity.append($0) }

        let result = await harness.provider.requestCurrentPosition(
            context: harness.context,
            options: .init(maximumAge: 60)
        )

        XCTAssertEqual(result, .success(.init(location: cachedLocation)))
        XCTAssertEqual(activity, [true, false])
        XCTAssertEqual(harness.locationManager.startUpdatingCallCount, initialStartCount)
    }

    func testOneShotCompletionRefreshesPermissionStatusAfterActivityHandlerExpiresAllowOnce() async throws {
        var queryState = GeolocationPermissionState.granted
        let harness = try Harness(queryPermission: { _ in queryState })
        var becameActive = false
        harness.provider.locationActivityHandler = { isActive in
            if isActive {
                becameActive = true
            } else if becameActive {
                queryState = .prompt
            }
        }
        var statusStates = [GeolocationPermissionState]()
        let initialState = harness.provider.permissionState(withID: "status", context: harness.context) {
            statusStates.append($0)
            return true
        }

        let request = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil { harness.provider.isLocationActive }
        harness.send([CLLocation(latitude: 37.3317, longitude: -122.0301)])
        _ = await request.value

        XCTAssertEqual(initialState, .granted)
        XCTAssertEqual(statusStates, [.prompt])
    }

    func testPermissionStatusRefreshesUntilDeliveryFailsOrPageIsCancelled() throws {
        var queryState = GeolocationPermissionState.prompt
        let harness = try Harness(queryPermission: { _ in queryState })
        var deliveredStates = [GeolocationPermissionState]()

        let initialState = harness.provider.permissionState(withID: "status",
                                                            context: harness.context) { state in
            deliveredStates.append(state)
            return deliveredStates.count < 2
        }
        XCTAssertEqual(initialState, .prompt)

        harness.provider.refreshPermissionStatuses()
        queryState = .granted
        harness.provider.refreshPermissionStatuses()
        queryState = .denied
        harness.provider.refreshPermissionStatuses()
        harness.provider.refreshPermissionStatuses()

        XCTAssertEqual(deliveredStates, [.granted, .denied])
        XCTAssertNil(harness.provider.currentContext(tabID: harness.context.tabID,
                                                     requestingFrameID: harness.context.requestingFrameID))

        _ = harness.provider.permissionState(withID: "replacement",
                                             context: harness.context) { _ in true }
        harness.provider.cancelPageActivity()
        XCTAssertNil(harness.provider.currentContext(tabID: harness.context.tabID,
                                                     requestingFrameID: harness.context.requestingFrameID))
    }

    func testDeniedOneShotResolutionRefreshesPermissionStatus() async throws {
        var queryState = GeolocationPermissionState.prompt
        let harness = try Harness(
            requestPermission: { _, completion in
                queryState = .denied
                completion(.deny(systemBlocks: []))
            },
            queryPermission: { _ in queryState }
        )
        var statusStates = [GeolocationPermissionState]()
        _ = harness.provider.permissionState(withID: "status", context: harness.context) {
            statusStates.append($0)
            return true
        }

        let result = await harness.provider.requestCurrentPosition(context: harness.context)

        XCTAssertEqual(result, .failure(.init(code: .permissionDenied, message: "Location permission was denied")))
        XCTAssertEqual(statusStates, [.denied])
    }

    func testGrantedWatchResolutionRefreshesPermissionStatus() throws {
        var queryState = GeolocationPermissionState.prompt
        let harness = try Harness(
            requestPermission: { _, completion in
                queryState = .granted
                completion(.grant)
            },
            queryPermission: { _ in queryState }
        )
        var statusStates = [GeolocationPermissionState]()
        _ = harness.provider.permissionState(withID: "status", context: harness.context) {
            statusStates.append($0)
            return true
        }

        harness.provider.startWatch(withID: "watch", context: harness.context) { _ in true }

        XCTAssertEqual(statusStates, [.granted])
        harness.provider.cancelWatch(withID: "watch")
    }

    func testRevocationDeniesActiveWorkStopsActivityAndRefreshesPermissionStatus() async throws {
        var queryState = GeolocationPermissionState.granted
        var permissionRequestCount = 0
        let harness = try Harness(
            requestPermission: { _, completion in
                permissionRequestCount += 1
                completion(.grant)
            },
            queryPermission: { _ in queryState }
        )
        var activity = [Bool]()
        var watchResults = [GeolocationPositionResult]()
        var statusStates = [GeolocationPermissionState]()
        harness.provider.locationActivityHandler = { activity.append($0) }
        harness.provider.startWatch(withID: "watch", context: harness.context) {
            watchResults.append($0)
            return true
        }
        let oneShot = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil { permissionRequestCount == 2 }
        _ = harness.provider.permissionState(withID: "status", context: harness.context) {
            statusStates.append($0)
            return true
        }

        queryState = .denied
        harness.provider.revokeActivePermission()

        let denied = GeolocationPositionResult.failure(
            .init(code: .permissionDenied, message: "Location permission was denied")
        )
        let oneShotResult = await oneShot.value
        XCTAssertEqual(oneShotResult, denied)
        XCTAssertEqual(watchResults, [denied])
        XCTAssertEqual(statusStates, [.denied])
        XCTAssertEqual(activity, [true, false])
        XCTAssertFalse(harness.provider.isLocationActive)
    }

    func testAccuracyDemandTracksAuthorizedOneShotsAndWatches() async throws {
        let harness = try Harness()
        harness.provider.startWatch(withID: "standard", context: harness.context) { _ in true }
        XCTAssertEqual(harness.locationManager.desiredAccuracy, kCLLocationAccuracyHundredMeters)

        let highAccuracy = Task {
            await harness.provider.requestCurrentPosition(
                context: harness.context,
                options: .init(enableHighAccuracy: true)
            )
        }
        await waitUntil { harness.locationManager.desiredAccuracy == kCLLocationAccuracyBest }

        let location = CLLocation(latitude: 37.3317, longitude: -122.0301)
        harness.send([location])

        let highAccuracyResult = await highAccuracy.value
        XCTAssertEqual(highAccuracyResult, .success(.init(location: location)))
        XCTAssertEqual(harness.locationManager.desiredAccuracy, kCLLocationAccuracyHundredMeters)
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 0)

        harness.provider.cancelWatch(withID: "standard")
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 1)
    }

    func testCancelPageActivityDrainsPendingRequestAndRejectsLatePermissionCompletion() async throws {
        var permissionCompletion: ((SitePermissionResolution) -> Void)?
        let harness = try Harness(requestPermission: { _, completion in
            permissionCompletion = completion
        })
        let task = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil {
            harness.provider.currentContext(tabID: harness.context.tabID,
                                            requestingFrameID: harness.context.requestingFrameID) == harness.context
        }

        harness.provider.cancelPageActivity()
        permissionCompletion?(.grant)

        let result = await task.value
        XCTAssertEqual(result, .failure(.init(code: .positionUnavailable, message: "Location is unavailable")))
        XCTAssertNil(harness.provider.currentContext(tabID: harness.context.tabID,
                                                     requestingFrameID: harness.context.requestingFrameID))
        XCTAssertEqual(harness.locationManager.startUpdatingCallCount, 0)
    }

    func testZeroTimeoutCompletesAndUnregistersLocationUpdates() async throws {
        let harness = try Harness()
        let result = await harness.provider.requestCurrentPosition(context: harness.context, options: .init(timeout: 0))

        XCTAssertEqual(result, .failure(.init(code: .timeout, message: "Geolocation request timed out")))
        XCTAssertEqual(harness.locationManager.startUpdatingCallCount, 1)
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 1)
    }

    func testLargestFiniteTimeoutDoesNotOverflowNanosecondConversion() async throws {
        let harness = try Harness()
        let task = Task {
            await harness.provider.requestCurrentPosition(
                context: harness.context,
                options: .init(timeout: .greatestFiniteMagnitude)
            )
        }
        await waitUntil { harness.locationManager.startUpdatingCallCount == 1 }

        harness.provider.cancelPageActivity()

        let result = await task.value
        XCTAssertEqual(result, .failure(.init(code: .positionUnavailable, message: "Location is unavailable")))
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 1)
    }

    func testDeniedWatchDeliversTerminalErrorAndLeavesNoActiveContext() throws {
        let harness = try Harness(requestPermission: { _, completion in completion(.deny(systemBlocks: [])) })
        var results = [GeolocationPositionResult]()

        harness.provider.startWatch(withID: "denied", context: harness.context) {
            results.append($0)
            return true
        }

        XCTAssertEqual(results, [.failure(.init(code: .permissionDenied, message: "Location permission was denied"))])
        XCTAssertNil(harness.provider.currentContext(tabID: harness.context.tabID,
                                                     requestingFrameID: harness.context.requestingFrameID))
        XCTAssertEqual(harness.locationManager.startUpdatingCallCount, 0)
    }

    func testCoreLocationDenialTerminatesAuthorizedRequestsAndStopsSharedManager() async throws {
        var permissionRequestCount = 0
        let harness = try Harness(requestPermission: { _, completion in
            permissionRequestCount += 1
            completion(.grant)
        })
        var watchResults = [GeolocationPositionResult]()
        harness.provider.startWatch(withID: "watch", context: harness.context) {
            watchResults.append($0)
            return true
        }
        let oneShot = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil { permissionRequestCount == 2 }

        harness.send(error: NSError(domain: kCLErrorDomain, code: CLError.Code.denied.rawValue))

        let expected = GeolocationPositionResult.failure(
            .init(code: .permissionDenied, message: "Location permission was denied")
        )
        let oneShotResult = await oneShot.value
        XCTAssertEqual(oneShotResult, expected)
        XCTAssertEqual(watchResults, [expected])
        XCTAssertNil(harness.provider.currentContext(tabID: harness.context.tabID,
                                                     requestingFrameID: harness.context.requestingFrameID))
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 1)
    }

    func testLocationUnknownKeepsAuthorizedRequestsAliveForFutureFixes() async throws {
        var permissionRequestCount = 0
        let harness = try Harness(requestPermission: { _, completion in
            permissionRequestCount += 1
            completion(.grant)
        })
        var watchResults = [GeolocationPositionResult]()
        harness.provider.startWatch(withID: "watch", context: harness.context) {
            watchResults.append($0)
            return true
        }
        let oneShot = Task { await harness.provider.requestCurrentPosition(context: harness.context) }
        await waitUntil { permissionRequestCount == 2 }

        harness.send(error: NSError(domain: kCLErrorDomain, code: CLError.Code.locationUnknown.rawValue))

        XCTAssertTrue(watchResults.isEmpty)
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 0)
        XCTAssertEqual(harness.provider.currentContext(tabID: harness.context.tabID,
                                                       requestingFrameID: harness.context.requestingFrameID),
                       harness.context)

        let location = CLLocation(latitude: 37.3317, longitude: -122.0301)
        harness.send([location])

        let oneShotResult = await oneShot.value
        XCTAssertEqual(oneShotResult, .success(.init(location: location)))
        XCTAssertEqual(watchResults, [.success(.init(location: location))])
        harness.provider.cancelWatch(withID: "watch")
        XCTAssertEqual(harness.locationManager.stopUpdatingCallCount, 1)
    }

    func testSuccessfulWatchDoesNotTimeOutWhileWaitingForSignificantChange() async throws {
        let harness = try Harness()
        var results = [GeolocationPositionResult]()
        harness.provider.startWatch(withID: "watch",
                                    context: harness.context,
                                    options: .init(timeout: 0.01)) {
            results.append($0)
            return true
        }
        let location = CLLocation(latitude: 37.3317, longitude: -122.0301)

        harness.send([location])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(results, [.success(.init(location: location))])
        harness.provider.cancelWatch(withID: "watch")
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class Harness {

    let locationManager = ProviderMockLocationManager()
    let context: SitePermissionRequestContext
    let provider: GeolocationProvider

    init(requestPermission: GeolocationProvider.PermissionRequestHandler? = nil,
         queryPermission: @escaping GeolocationProvider.PermissionQueryHandler = { _ in .granted }) throws {
        let site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com")!))
        context = SitePermissionRequestContext(tabID: "tab",
                                               topLevelSite: site,
                                               requestingFrameID: 42,
                                               webContentProcessGeneration: 1,
                                               navigationGeneration: 1)
        let systemPermissionClient = SystemPermissionClient(
            locationManager: locationManager,
            locationServicesEnabled: { true },
            avAuthorizationStatus: { _ in .authorized },
            avRequestAccess: { _, completion in completion(true) },
            notificationCenter: NotificationCenter()
        )
        provider = GeolocationProvider(
            systemPermissionClient: systemPermissionClient,
            contextProvider: { _ in nil },
            requestPermission: requestPermission ?? { _, completion in completion(.grant) },
            queryPermission: queryPermission
        )
    }

    func send(_ locations: [CLLocation]) {
        locationManager.delegate?.locationManager?(locationManager, didUpdateLocations: locations)
    }

    func send(error: Error) {
        locationManager.delegate?.locationManager?(locationManager, didFailWithError: error)
    }
}

private final class ProviderMockLocationManager: CLLocationManager {

    private(set) var startUpdatingCallCount = 0
    private(set) var stopUpdatingCallCount = 0

    override var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }

    override func startUpdatingLocation() {
        startUpdatingCallCount += 1
    }

    override func stopUpdatingLocation() {
        stopUpdatingCallCount += 1
    }
}
