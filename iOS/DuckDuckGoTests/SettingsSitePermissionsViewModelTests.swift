//
//  SettingsSitePermissionsViewModelTests.swift
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
import Foundation
import SitePermissions
import XCTest
@testable import DuckDuckGo

@MainActor
final class SettingsSitePermissionsViewModelTests: XCTestCase {

    func testSettingsViewModelCallbacksMapExactEventsAndRevocationWithoutSiteMetadata() throws {
        var events = [SitePermissionsEvent]()
        var revocations = [(SitePermissionKey, Set<SitePermissionType>)]()
        let callbacks = SettingsViewModel.makeSitePermissionsCallbacks(
            eventHandler: { events.append($0) },
            revocationHandler: { revocations.append(($0, $1)) }
        )
        let site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://private.example")!))

        callbacks.didOpen()
        callbacks.didChangeGlobalDefault(.camera, .deny)
        callbacks.didChangeSiteDecision(.microphone, .deny, .allow)
        callbacks.didOpenSystemSettings()
        callbacks.didRequestRevocation(site, [.camera, .microphone, .location])
        callbacks.didRemoveSite()
        callbacks.didRemoveAll()
        callbacks.didUndoRemoval()

        XCTAssertEqual(events, [
            .settingsSitePermissionsOpen,
            .settingsSitePermissionsGlobalChanged(type: .camera, to: .deny),
            .permissionCenterChanged(type: .microphone, from: .deny, to: .allow),
            .permissionSystemSettingsOpened(type: .cameraAndMicrophone),
            .permissionRemoveSite,
            .permissionRemoveAll,
            .permissionRemoveUndo
        ])
        XCTAssertFalse(events.map { String(describing: $0) }.joined().contains(site.host))
        XCTAssertEqual(revocations.first?.0, site)
        XCTAssertEqual(revocations.first?.1, [.camera, .microphone, .location])
        XCTAssertEqual(revocations.count, 1)
    }

    func testSupportedPermissionTypesIncludeLocation() {
        XCTAssertEqual(SettingsSitePermissionsViewModel.supportedPermissionTypes, [.location, .camera, .microphone])
    }

    func testGlobalPickerHasOnlyAskAndDenyOptions() {
        XCTAssertEqual(GlobalSitePermissionDecision.allCases, [.ask, .deny])
    }

    func testMainSettingsEntryVisibilityFollowsPublishedSettingsState() {
        var state = SettingsState.defaults
        let builder = SettingsMainSettingsView.SettingsViewBuilder()

        state.sitePermissionsEnabled = false
        XCTAssertFalse(builder.shouldShowSitePermissions(state: state))

        state.sitePermissionsEnabled = true
        XCTAssertTrue(builder.shouldShowSitePermissions(state: state))
    }

    func testGlobalDefaultBindingPersistsSelectionAndReportsChange() {
        let store = makeStore()
        var changes = [(SitePermissionType, GlobalSitePermissionDecision)]()
        var callbacks = SettingsSitePermissionsViewModel.Callbacks()
        callbacks.didChangeGlobalDefault = { changes.append(($0, $1)) }
        let sut = makeSUT(store: store, callbacks: callbacks)

        sut.globalDefaultBinding(for: .location).wrappedValue = .deny

        XCTAssertEqual(store.globalDefault(for: .location), .deny)
        XCTAssertEqual(sut.globalDefault(for: .location), .deny)
        XCTAssertEqual(changes.first?.0, .location)
        XCTAssertEqual(changes.first?.1, .deny)
        XCTAssertEqual(changes.count, 1)
    }

    func testResettingSiteDecisionToAskKeepsSiteInManageSites() throws {
        let store = makeStore()
        let site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com")!))
        store.setPersistentDecision(.allow, for: .location, at: site)
        var changes = [(SitePermissionType, SitePermissionDecision, SitePermissionDecision)]()
        var callbacks = SettingsSitePermissionsViewModel.Callbacks()
        callbacks.didChangeSiteDecision = { changes.append(($0, $1, $2)) }
        let sut = makeSUT(store: store, callbacks: callbacks)

        sut.siteDecisionBinding(for: .location, at: site).wrappedValue = .ask

        XCTAssertEqual(store.decision(for: .location, at: site), .ask)
        XCTAssertEqual(sut.storedSites, [site])
        XCTAssertEqual(changes.first?.0, .location)
        XCTAssertEqual(changes.first?.1, .allow)
        XCTAssertEqual(changes.first?.2, .ask)
        XCTAssertEqual(changes.count, 1)
    }

    func testDenyRequestsStoreFirstRevocationForOnlyTheChangedType() throws {
        let store = makeStore()
        let site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com")!))
        store.setPersistentDecision(.allow, for: .location, at: site)
        var revocations = [(SitePermissionKey, Set<SitePermissionType>)]()
        var decisionAtRevocation: SitePermissionDecision?
        var callbacks = SettingsSitePermissionsViewModel.Callbacks()
        callbacks.didRequestRevocation = {
            decisionAtRevocation = store.decision(for: .location, at: $0)
            revocations.append(($0, $1))
        }
        let sut = makeSUT(store: store, callbacks: callbacks)

        sut.siteDecisionBinding(for: .location, at: site).wrappedValue = .deny

        XCTAssertEqual(decisionAtRevocation, .deny)
        XCTAssertEqual(revocations.first?.0, site)
        XCTAssertEqual(revocations.first?.1, [.location])
        XCTAssertEqual(revocations.count, 1)
    }

    func testAskAndAllowDoNotRequestRevocation() throws {
        for decision in [SitePermissionDecision.ask, .allow] {
            let store = makeStore()
            let site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com")!))
            store.setPersistentDecision(.deny, for: .location, at: site)
            var revocations = [(SitePermissionKey, Set<SitePermissionType>)]()
            var callbacks = SettingsSitePermissionsViewModel.Callbacks()
            callbacks.didRequestRevocation = { revocations.append(($0, $1)) }
            let sut = makeSUT(store: store, callbacks: callbacks)

            sut.siteDecisionBinding(for: .location, at: site).wrappedValue = decision

            XCTAssertEqual(store.decision(for: .location, at: site), decision)
            XCTAssertTrue(revocations.isEmpty)
        }
    }

    func testStoredSitesAreLocaleSorted() throws {
        let store = makeStore()
        let second = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://zulu.example")!))
        let first = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://alpha.example")!))
        store.setPersistentDecision(.allow, for: .camera, at: second)
        store.setPersistentDecision(.deny, for: .location, at: first)

        let sut = makeSUT(store: store)

        XCTAssertEqual(sut.storedSites, [first, second])
    }

    func testRemoveSiteOffersUndoAndRestoresSnapshot() throws {
        let store = makeStore()
        let site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com")!))
        store.setPersistentDecision(.allow, for: .camera, at: site)
        var presentedMessage: String?
        var undo: (() -> Void)?
        var removedCount = 0
        var undoCount = 0
        var revocations = [(SitePermissionKey, Set<SitePermissionType>)]()
        var callbacks = SettingsSitePermissionsViewModel.Callbacks()
        callbacks.didRemoveSite = { removedCount += 1 }
        callbacks.didUndoRemoval = { undoCount += 1 }
        callbacks.didRequestRevocation = { revocations.append(($0, $1)) }
        let sut = makeSUT(store: store, presentUndoToast: {
            presentedMessage = $0
            undo = $1
        }, callbacks: callbacks)

        sut.removePermissions(for: site)

        XCTAssertNil(store.decision(for: .camera, at: site))
        XCTAssertEqual(presentedMessage, "Permissions removed for example.com")
        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(revocations.first?.0, site)
        XCTAssertEqual(revocations.first?.1, [.camera, .microphone, .location])

        try XCTUnwrap(undo)()

        XCTAssertEqual(store.decision(for: .camera, at: site), .allow)
        XCTAssertEqual(sut.storedSites, [site])
        XCTAssertEqual(undoCount, 1)
    }

    func testUndoDoesNotOverwriteNewerSiteDecision() throws {
        let store = makeStore()
        let site = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com")!))
        store.setPersistentDecision(.allow, for: .camera, at: site)
        var undo: (() -> Void)?
        let sut = makeSUT(store: store, presentUndoToast: { _, action in undo = action })

        sut.removePermissions(for: site)
        store.setPersistentDecision(.deny, for: .camera, at: site)
        try XCTUnwrap(undo)()

        XCTAssertEqual(store.decision(for: .camera, at: site), .deny)
        XCTAssertEqual(sut.siteDecision(for: .camera, at: site), .deny)
    }

    func testRemoveAllPreservesGlobalDefaultsAndUndoRestoresSites() throws {
        let store = makeStore()
        let first = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://one.example")!))
        let second = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://two.example")!))
        store.setGlobalDefault(.deny, for: .camera)
        store.setPersistentDecision(.allow, for: .camera, at: first)
        store.setPersistentDecision(.deny, for: .microphone, at: second)
        var presentedMessage: String?
        var undo: (() -> Void)?
        var removedAllCount = 0
        var revokedSites = Set<SitePermissionKey>()
        var callbacks = SettingsSitePermissionsViewModel.Callbacks()
        callbacks.didRemoveAll = { removedAllCount += 1 }
        callbacks.didRequestRevocation = {
            revokedSites.insert($0)
            XCTAssertEqual($1, [.camera, .microphone, .location])
        }
        let sut = makeSUT(store: store, presentUndoToast: {
            presentedMessage = $0
            undo = $1
        }, callbacks: callbacks)

        sut.removeAllSitePermissions()

        XCTAssertTrue(sut.storedSites.isEmpty)
        XCTAssertEqual(store.globalDefault(for: .camera), .deny)
        XCTAssertEqual(presentedMessage, "Permissions removed for all sites")
        XCTAssertEqual(removedAllCount, 1)
        XCTAssertEqual(revokedSites, [first, second])

        try XCTUnwrap(undo)()

        XCTAssertEqual(Set(sut.storedSites), [first, second])
        XCTAssertEqual(store.globalDefault(for: .camera), .deny)
    }

    func testOpenAndSystemSettingsActionsUseInjectedCallbacks() {
        var openCount = 0
        var settingsCount = 0
        var callbacks = SettingsSitePermissionsViewModel.Callbacks()
        callbacks.didOpen = { openCount += 1 }
        callbacks.didOpenSystemSettings = { settingsCount += 1 }
        var systemSettingsOpenCount = 0
        let sut = makeSUT(openSystemSettings: { systemSettingsOpenCount += 1 }, callbacks: callbacks)

        sut.didOpen()
        sut.openSystemSettings()

        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(settingsCount, 1)
        XCTAssertEqual(systemSettingsOpenCount, 1)
    }

    private func makeStore() -> SitePermissionsStore {
        SitePermissionsStore(storage: InMemoryKeyValueStore().keyedStoring())
    }

    private func makeSUT(store: SitePermissionsStore? = nil,
                         openSystemSettings: @escaping () -> Void = {},
                         presentUndoToast: @escaping SettingsSitePermissionsViewModel.UndoToastPresenter = { _, _ in },
                         callbacks: SettingsSitePermissionsViewModel.Callbacks = .init()) -> SettingsSitePermissionsViewModel {
        SettingsSitePermissionsViewModel(store: store ?? makeStore(),
                                         openSystemSettings: openSystemSettings,
                                         presentUndoToast: presentUndoToast,
                                         callbacks: callbacks)
    }
}
