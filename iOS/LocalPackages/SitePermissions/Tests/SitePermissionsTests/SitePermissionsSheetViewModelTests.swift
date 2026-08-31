//
//  SitePermissionsSheetViewModelTests.swift
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
import SwiftUI
import XCTest

@MainActor
final class SitePermissionsSheetViewModelTests: XCTestCase {

    func testRowMembershipIsStoredUnionActiveSessionAndRequestedForAllManagedTypes() throws {
        let harness = try Harness()
        harness.store.resetDecision(for: .camera, at: harness.site)
        let snapshot = harness.snapshot(
            ephemeral: [.microphone],
            siteAllowed: [.microphone],
            requested: [.location],
            captureStates: [.microphone: .active]
        )

        XCTAssertEqual(snapshot.relevantPermissionTypes, [.camera, .microphone, .location])
        XCTAssertTrue(snapshot.showsMenuEntry)

        let sut = harness.makeViewModel(snapshot: snapshot)
        XCTAssertEqual(sut.rows.map(\.permissionType), [.location, .camera, .microphone])
    }

    func testRequestedOnlyAddsSheetRowButDoesNotMakeMenuEntryVisible() throws {
        let harness = try Harness()
        let snapshot = harness.snapshot(requested: [.camera])

        XCTAssertEqual(snapshot.relevantPermissionTypes, [.camera])
        XCTAssertFalse(snapshot.showsMenuEntry)
        XCTAssertEqual(harness.makeViewModel(snapshot: snapshot).rows.map(\.permissionType), [.camera])

        let globallyDeniedWithoutRequest = harness.snapshot()
        XCTAssertTrue(harness.makeViewModel(snapshot: globallyDeniedWithoutRequest).rows.isEmpty)
    }

    func testAllThreeSheetStatesAreRepresentable() throws {
        let harness = try Harness()

        let permissionsOnly = harness.makeViewModel(snapshot: harness.snapshot(stored: [.location: .ask]))
        XCTAssertEqual(permissionsOnly.state, .permissionsOnly)
        XCTAssertNil(permissionsOnly.reminderText)
        XCTAssertEqual(permissionsOnly.rows.map(\.permissionType), [.location])
        XCTAssertEqual(permissionsOnly.rows.first?.title, "Location")

        let permissionsAndReminder = harness.makeViewModel(snapshot: harness.snapshot(
            stored: [.location: .allow],
            systemStates: [.location: .denied],
            systemBlocked: [.location]
        ))
        XCTAssertEqual(permissionsAndReminder.state, .permissionsAndReminder)
        XCTAssertEqual(permissionsAndReminder.rows.map(\.permissionType), [.location])
        XCTAssertEqual(permissionsAndReminder.systemSettingsPermissionTypes, [.location])

        let reminderOnly = harness.makeViewModel(snapshot: harness.snapshot(
            systemStates: [.location: .restricted],
            systemBlocked: [.location]
        ))
        XCTAssertEqual(reminderOnly.state, .reminderOnly)
        XCTAssertTrue(reminderOnly.rows.isEmpty)

        _ = SitePermissionsSheetView(viewModel: permissionsOnly).body
        _ = SitePermissionsSheetView(viewModel: permissionsAndReminder).body
        _ = SitePermissionsSheetView(viewModel: reminderOnly).body
    }

    func testPickerUsesThreeNormalOptionsAndReplacesAskWithCheckedAllowThisTimeForEphemeralGrant() throws {
        let harness = try Harness()
        let sut = harness.makeViewModel(snapshot: harness.snapshot(
            stored: [.location: .ask],
            ephemeral: [.microphone]
        ))

        let location = try XCTUnwrap(sut.rows.first { $0.permissionType == .location })
        XCTAssertEqual(location.options, [.askEachTime, .alwaysAllow, .neverAllow])
        XCTAssertEqual(location.selectedOption, .askEachTime)

        let microphone = try XCTUnwrap(sut.rows.first { $0.permissionType == .microphone })
        XCTAssertEqual(microphone.options, [.allowThisTime, .alwaysAllow, .neverAllow])
        XCTAssertEqual(microphone.selectedOption, .allowThisTime)
        XCTAssertFalse(microphone.options.contains(.askEachTime))
    }

    func testIconAndAccessibilityStatesCoverInactiveInUseAndPaused() throws {
        let harness = try Harness()
        let sut = harness.makeViewModel(snapshot: harness.snapshot(
            stored: [.camera: .allow, .microphone: .deny],
            requested: [.camera, .microphone],
            captureStates: [.camera: .active, .microphone: .paused]
        ))

        let camera = try XCTUnwrap(sut.rows.first { $0.permissionType == .camera })
        XCTAssertEqual(camera.iconState, .inUse)
        XCTAssertEqual(camera.accessibilityValue, "Always Allow, in use")

        let microphone = try XCTUnwrap(sut.rows.first { $0.permissionType == .microphone })
        XCTAssertEqual(microphone.iconState, .solid)
        XCTAssertEqual(microphone.accessibilityValue, "Never Allow, paused")

        let denied = harness.makeViewModel(snapshot: harness.snapshot(stored: [.microphone: .deny]))
        XCTAssertEqual(denied.rows.first?.iconState, .blocked)
        XCTAssertEqual(denied.rows.first?.accessibilityValue, "Never Allow")

        let location = harness.makeViewModel(snapshot: harness.snapshot(stored: [.location: .allow]))
        XCTAssertEqual(location.rows.first?.iconState, .solid)
        XCTAssertEqual(location.rows.first?.title, "Location")
    }

    func testDenyWritesStoreBeforeImmediateRevocationAndReportsTypedChange() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .location, at: harness.site)
        var order = [String]()
        var changes = [SitePermissionDecisionChange]()
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(stored: [.location: .allow], captureStates: [.location: .active]),
            onDecisionChanged: {
                order.append("change")
                changes.append($0)
            },
            revokePermissions: { permissionTypes in
                XCTAssertEqual(harness.store.decision(for: .location, at: harness.site), .deny)
                XCTAssertEqual(permissionTypes, [.location])
                order.append("revoke")
            }
        )

        sut.select(.neverAllow, for: .location)

        XCTAssertEqual(order, ["change", "revoke"])
        XCTAssertEqual(changes, [SitePermissionDecisionChange(permissionType: .location, from: .allow, to: .deny)])
        XCTAssertEqual(sut.rows.first?.selectedOption, .neverAllow)
    }

    func testChangingEphemeralGrantReportsAskAsThePreviousCommittedDecision() throws {
        let harness = try Harness()
        var change: SitePermissionDecisionChange?
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(ephemeral: [.camera]),
            onDecisionChanged: { change = $0 }
        )

        sut.select(.alwaysAllow, for: .camera)

        XCTAssertEqual(change, SitePermissionDecisionChange(permissionType: .camera, from: .ask, to: .allow))
    }

    func testGrantAndAskWriteWithoutRevoking() throws {
        let harness = try Harness()
        harness.store.resetDecision(for: .location, at: harness.site)
        var revoked = [Set<SitePermissionType>]()
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(stored: [.location: .ask], captureStates: [.location: .active]),
            revokePermissions: { revoked.append($0) }
        )

        sut.select(.alwaysAllow, for: .location)
        XCTAssertEqual(harness.store.decision(for: .location, at: harness.site), .allow)
        XCTAssertTrue(revoked.isEmpty)

        sut.select(.askEachTime, for: .location)
        XCTAssertEqual(harness.store.decision(for: .location, at: harness.site), .ask)
        XCTAssertTrue(revoked.isEmpty)
    }

    func testFireModeSelectionDoesNotWriteStore() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        var change: SitePermissionDecisionChange?
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(isFireMode: true, stored: [.camera: .allow]),
            onDecisionChanged: { change = $0 }
        )

        sut.select(.neverAllow, for: .camera)

        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .allow)
        XCTAssertEqual(sut.rows.first?.selectedOption, .neverAllow)
        XCTAssertEqual(change, SitePermissionDecisionChange(permissionType: .camera, from: .allow, to: .deny))
    }

    func testRemoveWritesStoreBeforeRevokingManagedTypesThenReportsSnapshotAndDismissesCleanly() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        harness.store.setPersistentDecision(.deny, for: .microphone, at: harness.site)
        harness.store.resetDecision(for: .location, at: harness.site)
        var order = [String]()
        var removal: SitePermissionsRemoval?
        var dismissal: SitePermissionsSheetDismissal?
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(
                stored: [.camera: .allow, .microphone: .deny, .location: .ask],
                captureStates: [.camera: .active, .microphone: .paused]
            ),
            onRemovePermissions: {
                order.append("remove")
                removal = $0
            },
            onDismiss: {
                order.append("dismiss")
                dismissal = $0
            },
            revokePermissions: {
                XCTAssertTrue(harness.store.permissions(for: harness.site).isEmpty)
                XCTAssertEqual($0, [.camera, .microphone, .location])
                order.append("revoke")
            }
        )

        sut.removePermissions()

        XCTAssertEqual(order, ["remove", "revoke", "dismiss"])
        XCTAssertEqual(removal?.permissionTypes, [.camera, .microphone, .location])
        XCTAssertEqual(removal?.revokedPermissionTypes, [.camera, .microphone, .location])
        XCTAssertFalse(removal?.snapshot.isEmpty ?? true)
        XCTAssertEqual(dismissal, .clean)
    }

    func testRemoveRevokesAllManagedTypesSoOtherMatchingTabsStopCapture() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        var revokedPermissionTypes = Set<SitePermissionType>()
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(stored: [.camera: .allow]),
            revokePermissions: { revokedPermissionTypes = $0 }
        )

        sut.removePermissions()

        XCTAssertEqual(revokedPermissionTypes, [.camera, .microphone, .location])
    }

    func testDismissalReportsDirtyOnlyWhenPickerWasOpenedWithoutACommittedSelection() throws {
        let harness = try Harness()
        var dirtyDismissal: SitePermissionsSheetDismissal?
        let dirty = harness.makeViewModel(
            snapshot: harness.snapshot(stored: [.camera: .ask]),
            onDismiss: { dirtyDismissal = $0 }
        )
        dirty.beginEditing()
        dirty.dismiss()
        XCTAssertEqual(dirtyDismissal, .dirty)

        var cleanDismissal: SitePermissionsSheetDismissal?
        let clean = harness.makeViewModel(
            snapshot: harness.snapshot(stored: [.camera: .ask]),
            onDismiss: { cleanDismissal = $0 }
        )
        clean.beginEditing()
        clean.select(.alwaysAllow, for: .camera)
        clean.dismiss()
        XCTAssertEqual(cleanDismissal, .clean)
    }

    func testSystemSettingsActionCarriesOnlyBlockedTypes() throws {
        let harness = try Harness()
        var openedTypes = Set<SitePermissionType>()
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(
                stored: [.location: .allow],
                systemStates: [.location: .denied],
                systemBlocked: [.location]
            ),
            onOpenSystemSettings: { openedTypes = $0 }
        )

        sut.openSystemSettings()

        XCTAssertEqual(openedTypes, [.location])
        XCTAssertEqual(sut.removalToastMessage, "Permissions removed for example.com")
        XCTAssertEqual(sut.reminderText,
                       "DuckDuckGo needs to access your location, if you want to use related features on this site.")
    }
}

@MainActor
private final class Harness {
    let site: SitePermissionKey
    let store: SitePermissionsStore

    init() throws {
        site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com")!))
        store = SitePermissionsStore(storage: InMemoryKeyValueStore().keyedStoring())
    }

    func snapshot(isFireMode: Bool = false,
                  stored: SitePermissionsStore.SitePermissionRecord? = nil,
                  ephemeral: Set<SitePermissionType> = [],
                  siteAllowed: Set<SitePermissionType> = [],
                  requested: Set<SitePermissionType> = [],
                  captureStates: [SitePermissionType: SitePermissionCaptureState] = [:],
                  systemStates: [SitePermissionType: SystemPermissionAuthorizationState] = [:],
                  systemBlocked: Set<SitePermissionType> = []) -> SitePermissionsManagementSnapshot {
        SitePermissionsManagementSnapshot(
            site: site,
            isFireMode: isFireMode,
            storedPermissions: stored ?? store.permissions(for: site),
            ephemeralPermissionTypes: ephemeral,
            siteAllowedPermissionTypesThisVisit: siteAllowed,
            requestedPermissionTypesThisVisit: requested,
            captureStates: captureStates,
            systemAuthorizationStates: systemStates,
            systemBlockedPermissionTypes: systemBlocked
        )
    }

    func makeViewModel(snapshot: SitePermissionsManagementSnapshot,
                       onDecisionChanged: @escaping SitePermissionsSheetViewModel.DecisionChangedHandler = { _ in },
                       onRemovePermissions: @escaping SitePermissionsSheetViewModel.RemovePermissionsHandler = { _ in },
                       onOpenSystemSettings: @escaping SitePermissionsSheetViewModel.OpenSystemSettingsHandler = { _ in },
                       onDismiss: @escaping SitePermissionsSheetViewModel.DismissHandler = { _ in },
                       revokePermissions: @escaping SitePermissionsSheetViewModel.RevokePermissionsHandler = { _ in })
    -> SitePermissionsSheetViewModel {
        SitePermissionsSheetViewModel(
            snapshot: snapshot,
            store: store,
            onDecisionChanged: onDecisionChanged,
            onRemovePermissions: onRemovePermissions,
            onOpenSystemSettings: onOpenSystemSettings,
            onDismiss: onDismiss,
            revokePermissions: revokePermissions
        )
    }
}
