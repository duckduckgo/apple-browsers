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

    func testRowMembershipIsStoredUnionActiveSessionAndRequestedButExcludesLocation() throws {
        let harness = try Harness()
        harness.store.resetDecision(for: .camera, at: harness.site)
        let snapshot = harness.snapshot(
            ephemeral: [.microphone],
            siteAllowed: [.microphone],
            requested: [.location],
            captureStates: [.microphone: .active]
        )

        XCTAssertEqual(snapshot.relevantPermissionTypes, [.camera, .microphone])
        XCTAssertTrue(snapshot.showsMenuEntry)

        let sut = harness.makeViewModel(snapshot: snapshot)
        XCTAssertEqual(sut.rows.map(\.permissionType), [.camera, .microphone])
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

        let permissionsOnly = harness.makeViewModel(snapshot: harness.snapshot(stored: [.camera: .ask]))
        XCTAssertEqual(permissionsOnly.state, .permissionsOnly)
        XCTAssertNil(permissionsOnly.reminderText)

        let permissionsAndReminder = harness.makeViewModel(snapshot: harness.snapshot(
            stored: [.camera: .allow],
            systemStates: [.camera: .denied],
            systemBlocked: [.camera]
        ))
        XCTAssertEqual(permissionsAndReminder.state, .permissionsAndReminder)
        XCTAssertEqual(permissionsAndReminder.systemSettingsPermissionTypes, [.camera])

        let reminderOnly = harness.makeViewModel(snapshot: harness.snapshot(
            systemStates: [.microphone: .restricted],
            systemBlocked: [.microphone]
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
            stored: [.camera: .ask],
            ephemeral: [.microphone]
        ))

        let camera = try XCTUnwrap(sut.rows.first { $0.permissionType == .camera })
        XCTAssertEqual(camera.options, [.askEachTime, .alwaysAllow, .neverAllow])
        XCTAssertEqual(camera.selectedOption, .askEachTime)

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
    }

    func testDenyWritesStoreBeforeImmediateRevocationAndReportsTypedChange() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        var order = [String]()
        var changes = [SitePermissionDecisionChange]()
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(stored: [.camera: .allow], captureStates: [.camera: .active]),
            onDecisionChanged: {
                order.append("change")
                changes.append($0)
            },
            revokePermissions: { permissionTypes in
                XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .deny)
                XCTAssertEqual(permissionTypes, [.camera])
                order.append("revoke")
            }
        )

        sut.select(.neverAllow, for: .camera)

        XCTAssertEqual(order, ["revoke", "change"])
        XCTAssertEqual(changes, [SitePermissionDecisionChange(permissionType: .camera, from: .allow, to: .deny)])
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
        harness.store.resetDecision(for: .camera, at: harness.site)
        var revoked = [Set<SitePermissionType>]()
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(stored: [.camera: .ask], captureStates: [.camera: .active]),
            revokePermissions: { revoked.append($0) }
        )

        sut.select(.alwaysAllow, for: .camera)
        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .allow)
        XCTAssertTrue(revoked.isEmpty)

        sut.select(.askEachTime, for: .camera)
        XCTAssertEqual(harness.store.decision(for: .camera, at: harness.site), .ask)
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
        var order = [String]()
        var removal: SitePermissionsRemoval?
        var dismissal: SitePermissionsSheetDismissal?
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(
                stored: [.camera: .allow, .microphone: .deny],
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
                XCTAssertEqual($0, [.camera, .microphone])
                order.append("revoke")
            }
        )

        sut.removePermissions()

        XCTAssertEqual(order, ["revoke", "remove", "dismiss"])
        XCTAssertEqual(removal?.permissionTypes, [.camera, .microphone])
        XCTAssertEqual(removal?.revokedPermissionTypes, [.camera, .microphone])
        XCTAssertFalse(removal?.snapshot.isEmpty ?? true)
        XCTAssertEqual(dismissal, .clean)
    }

    func testRemoveRevokesBothManagedTypesSoOtherMatchingTabsStopCapture() throws {
        let harness = try Harness()
        harness.store.setPersistentDecision(.allow, for: .camera, at: harness.site)
        var revokedPermissionTypes = Set<SitePermissionType>()
        let sut = harness.makeViewModel(
            snapshot: harness.snapshot(stored: [.camera: .allow]),
            revokePermissions: { revokedPermissionTypes = $0 }
        )

        sut.removePermissions()

        XCTAssertEqual(revokedPermissionTypes, [.camera, .microphone])
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
                stored: [.camera: .allow, .microphone: .allow],
                systemStates: [.camera: .denied, .microphone: .authorized],
                systemBlocked: [.camera]
            ),
            onOpenSystemSettings: { openedTypes = $0 }
        )

        sut.openSystemSettings()

        XCTAssertEqual(openedTypes, [.camera])
        XCTAssertEqual(sut.removalToastMessage, "Permissions removed for example.com")
        XCTAssertEqual(sut.reminderText,
                       "DuckDuckGo needs to access your camera, if you want to use related features on this site.")
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
