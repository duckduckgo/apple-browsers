//
//  SitePermissionsManagementCoordinatorTests.swift
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

@_spi(Testing) import Persistence
@testable import SitePermissions
import XCTest

@MainActor
final class SitePermissionsManagementCoordinatorTests: XCTestCase {

    func testAcceptedRequestIsTrackedForSheetMembershipButNotMenuEligibility() throws {
        let harness = try CoordinatorHarness()

        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in }, completion: { _ in })

        let snapshot = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertEqual(snapshot.requestedPermissionTypesThisVisit, [.camera])
        XCTAssertEqual(snapshot.relevantPermissionTypes, [.camera])
        XCTAssertFalse(snapshot.showsMenuEntry)
    }

    func testRequestBlockedByGlobalNeverDoesNotCreateManagementRow() throws {
        let harness = try CoordinatorHarness()
        harness.store.setGlobalDefault(.deny, for: .camera)
        var resolutions = [SitePermissionResolution]()

        harness.coordinator.request(
            harness.request([.camera]),
            promptHandler: { _, _ in XCTFail("Global Never must not prompt") },
            completion: { resolutions.append($0) }
        )

        XCTAssertEqual(resolutions, [.deny(systemBlocks: [])])
        let snapshot = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertTrue(snapshot.relevantPermissionTypes.isEmpty)
        XCTAssertFalse(snapshot.showsMenuEntry)
    }

    func testFreshSystemDenialKeepsSiteAllowIntentAndReminderReachableWithoutActivatingEphemeralGrant() async throws {
        let harness = try CoordinatorHarness()
        harness.systemStates[.camera] = .notDetermined
        harness.authorizationRequester = {
            harness.systemStates[$0] = .denied
            return .denied
        }
        let requestCompleted = expectation(description: "Request completed")

        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { _ in
            requestCompleted.fulfill()
        })

        await fulfillment(of: [requestCompleted], timeout: 1)
        let snapshot = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertEqual(snapshot.ephemeralPermissionTypes, [])
        XCTAssertEqual(snapshot.siteAllowedPermissionTypesThisVisit, [.camera])
        XCTAssertEqual(snapshot.systemBlockedPermissionTypes, [.camera])
        XCTAssertTrue(snapshot.showsMenuEntry)
    }

    func testSuccessfulAllowOnceExposesAllowThisTimeUntilCaptureEnds() async throws {
        let harness = try CoordinatorHarness()
        harness.systemStates[.microphone] = .authorized
        let requestCompleted = expectation(description: "Request completed")

        harness.coordinator.request(harness.request([.microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { _ in
            requestCompleted.fulfill()
        })

        await fulfillment(of: [requestCompleted], timeout: 1)
        XCTAssertEqual(harness.coordinator.managementSnapshot(for: harness.site).ephemeralPermissionTypes, [.microphone])

        harness.coordinator.captureDidEnd([.microphone])

        let ended = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertTrue(ended.ephemeralPermissionTypes.isEmpty)
        XCTAssertTrue(ended.siteAllowedPermissionTypesThisVisit.isEmpty)
        XCTAssertFalse(ended.showsMenuEntry)
    }

    func testNavigationClearsRequestedAndSessionStateButPreservesStoredRecord() async throws {
        let harness = try CoordinatorHarness()
        harness.store.resetDecision(for: .camera, at: harness.site)
        harness.systemStates[.microphone] = .authorized
        let requestCompleted = expectation(description: "Request completed")
        harness.coordinator.request(harness.request([.microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { _ in requestCompleted.fulfill() })
        await fulfillment(of: [requestCompleted], timeout: 1)

        harness.coordinator.pageDidChange(.navigation)

        let snapshot = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertEqual(snapshot.storedPermissions, [.camera: .ask])
        XCTAssertTrue(snapshot.requestedPermissionTypesThisVisit.isEmpty)
        XCTAssertTrue(snapshot.ephemeralPermissionTypes.isEmpty)
        XCTAssertTrue(snapshot.siteAllowedPermissionTypesThisVisit.isEmpty)
        XCTAssertTrue(snapshot.showsMenuEntry)
    }

    func testRemoveManagementSessionStateClearsNonStoredMenuEligibility() async throws {
        let harness = try CoordinatorHarness()
        harness.systemStates[.camera] = .authorized
        let requestCompleted = expectation(description: "Request completed")
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { _ in requestCompleted.fulfill() })
        await fulfillment(of: [requestCompleted], timeout: 1)

        harness.coordinator.removeManagementSessionState(for: [.camera], at: harness.site)

        let snapshot = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertTrue(snapshot.relevantPermissionTypes.isEmpty)
        XCTAssertFalse(snapshot.showsMenuEntry)
    }

    func testFireModeManagementDecisionUpdatesSessionWithoutWritingStore() throws {
        let harness = try CoordinatorHarness(isFireMode: true)
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in }, completion: { _ in })

        harness.coordinator.applyFireModeManagementDecision(.allow, for: .camera)

        let snapshot = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertTrue(snapshot.isFireMode)
        XCTAssertEqual(snapshot.ephemeralPermissionTypes, [.camera])
        XCTAssertEqual(snapshot.siteAllowedPermissionTypesThisVisit, [.camera])
        XCTAssertNil(harness.store.decision(for: .camera, at: harness.site))
    }

    func testFireModeRemoveHidesStoredRecordForSessionWithoutDeletingIt() throws {
        let harness = try CoordinatorHarness(isFireMode: true)
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        harness.coordinator.request(harness.request([.camera]), promptHandler: { _, _ in }, completion: { _ in })

        harness.coordinator.removeManagementSessionState(for: [.camera], at: harness.site)

        let snapshot = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertTrue(snapshot.storedPermissions.isEmpty)
        XCTAssertFalse(snapshot.showsMenuEntry)
        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .allow)
    }

    func testFireModeUndoRestoresStoredRecordButNotEphemeralGrant() async throws {
        let harness = try CoordinatorHarness(isFireMode: true)
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        let requestCompleted = expectation(description: "Request completed")
        harness.coordinator.request(harness.request([.microphone]), promptHandler: { _, respond in
            respond(.allowOnce)
        }, completion: { _ in requestCompleted.fulfill() })
        await fulfillment(of: [requestCompleted], timeout: 1)
        harness.coordinator.removeManagementSessionState(for: [.camera, .microphone], at: harness.site)

        harness.coordinator.restoreFireModeManagementState(for: [.camera, .microphone], at: harness.site)

        let snapshot = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertEqual(snapshot.storedPermissions, [.camera: .allow])
        XCTAssertTrue(snapshot.ephemeralPermissionTypes.isEmpty)
        XCTAssertEqual(snapshot.relevantPermissionTypes, [.camera])
    }

    func testExternalRevocationClearsFireOverrideAndRevealsPersistentDecision() throws {
        let harness = try CoordinatorHarness(isFireMode: true)
        harness.store.setPersistentDecision(.deny, for: .camera, at: harness.site)
        harness.coordinator.applyFireModeManagementDecision(.allow, for: .camera)

        harness.coordinator.revokeManagementSessionState(for: [.camera], at: harness.site)

        let snapshot = harness.coordinator.managementSnapshot(for: harness.site)
        XCTAssertEqual(snapshot.storedPermissions, [.camera: .deny])
        XCTAssertTrue(snapshot.ephemeralPermissionTypes.isEmpty)
    }
}

@MainActor
private final class CoordinatorHarness {
    let site: SitePermissionKey
    let store: SitePermissionsStore
    let context: SitePermissionRequestContext
    let isFireMode: Bool

    lazy var coordinator = SitePermissionsCoordinator(
        store: store,
        isFireMode: isFireMode,
        currentContext: { [context] _, _ in context },
        authorizationState: { [weak self] in self?.systemStates[$0] ?? .unavailable },
        requestAuthorization: { [weak self] in await self?.authorizationRequester($0) ?? .unavailable },
        recoveryHandler: { _, completion in completion() }
    )

    var systemStates: [SitePermissionType: SystemPermissionAuthorizationState] = [
        .camera: .authorized,
        .microphone: .authorized
    ]
    var authorizationRequester: (SitePermissionType) async -> SystemPermissionAuthorizationState = { _ in .authorized }

    init(isFireMode: Bool = false) throws {
        self.isFireMode = isFireMode
        site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com")!))
        store = SitePermissionsStore(storage: InMemoryKeyValueStore().keyedStoring())
        context = SitePermissionRequestContext(tabID: "tab",
                                               topLevelSite: site,
                                               requestingFrameID: 1,
                                               webContentProcessGeneration: 0,
                                               navigationGeneration: 0)
    }

    func request(_ permissionTypes: Set<SitePermissionType>) -> SitePermissionRequest {
        SitePermissionRequest(context: context, permissionTypes: permissionTypes)
    }
}
