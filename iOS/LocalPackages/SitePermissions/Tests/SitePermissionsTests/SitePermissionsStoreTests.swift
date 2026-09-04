//
//  SitePermissionsStoreTests.swift
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

import Foundation
@_spi(Testing) import Persistence
import XCTest
@testable import SitePermissions

@MainActor
final class SitePermissionsStoreTests: XCTestCase {

    func testWhenModelRawValuesAreReadThenTheyMatchTheWireContract() {
        XCTAssertEqual(SitePermissionType.camera.rawValue, "camera")
        XCTAssertEqual(SitePermissionType.microphone.rawValue, "microphone")
        XCTAssertEqual(SitePermissionType.location.rawValue, "geolocation")
        XCTAssertEqual(SitePermissionDecision.ask.rawValue, "ask")
        XCTAssertEqual(SitePermissionDecision.allow.rawValue, "allow")
        XCTAssertEqual(SitePermissionDecision.deny.rawValue, "deny")
    }

    func testWhenPermissionIsWrittenThenFreshStoreReadsPlistDictionaryRatherThanData() throws {
        let keyValueStore = MockKeyValueStore()
        let store = makeStore(keyValueStore: keyValueStore)
        let site = try makeSite("https://example.com")

        store.setPersistentDecision(.allow, for: .camera, at: site)

        let rawObject = keyValueStore.object(forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue)
        XCTAssertTrue(rawObject is [String: [String: String]])
        XCTAssertFalse(rawObject is Data)
        XCTAssertEqual(rawObject as? [String: [String: String]], ["example.com": ["camera": "allow"]])

        let freshStore = makeStore(keyValueStore: keyValueStore)
        XCTAssertEqual(freshStore.decision(for: .camera, at: site), .allow)
    }

    func testWhenSitePermissionsAreClearedThenGlobalDefaultsRemainUnchanged() throws {
        let keyValueStore = MockKeyValueStore()
        let store = makeStore(keyValueStore: keyValueStore)
        let site = try makeSite("https://example.com")
        store.setPersistentDecision(.allow, for: .camera, at: site)
        store.setGlobalDefault(.deny, for: .microphone)
        let rawGlobals = keyValueStore.object(forKey: SitePermissionsStorageKeyNames.globalDefaults.rawValue) as? [String: String]

        store.clearSitePermissions()

        XCTAssertNil(store.decision(for: .camera, at: site))
        XCTAssertEqual(store.globalDefault(for: .microphone), .deny)
        XCTAssertEqual(keyValueStore.object(forKey: SitePermissionsStorageKeyNames.globalDefaults.rawValue) as? [String: String], rawGlobals)
    }

    func testWhenGlobalDefaultsAreResetThenSitePermissionsRemainUnchanged() throws {
        let keyValueStore = MockKeyValueStore()
        let store = makeStore(keyValueStore: keyValueStore)
        let site = try makeSite("https://example.com")
        store.setPersistentDecision(.deny, for: .location, at: site)
        store.setGlobalDefault(.deny, for: .location)

        store.resetGlobalDefaults()

        XCTAssertEqual(store.globalDefault(for: .location), .ask)
        XCTAssertEqual(store.decision(for: .location, at: site), .deny)
    }

    func testWhenNoPersistentChoiceExistsThenReadingWritesNoPassiveRecord() throws {
        let keyValueStore = MockKeyValueStore()
        let store = makeStore(keyValueStore: keyValueStore)
        let site = try makeSite("https://example.com")

        XCTAssertNil(store.decision(for: .camera, at: site))
        XCTAssertTrue(store.permissions(for: site).isEmpty)
        XCTAssertNil(keyValueStore.object(forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue))
    }

    func testWhenAskIsPassedAsPersistentDecisionThenItIsNotWritten() throws {
        let keyValueStore = MockKeyValueStore()
        let store = makeStore(keyValueStore: keyValueStore)
        let site = try makeSite("https://example.com")

        store.setPersistentDecision(.ask, for: .camera, at: site)

        XCTAssertNil(store.decision(for: .camera, at: site))
        XCTAssertNil(keyValueStore.object(forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue))
    }

    func testWhenUserExplicitlyResetsPermissionThenAskIsPersistedAndSiteRemainsListed() throws {
        let keyValueStore = MockKeyValueStore()
        let store = makeStore(keyValueStore: keyValueStore)
        let site = try makeSite("https://example.com")

        store.resetDecision(for: .camera, at: site)

        XCTAssertEqual(store.decision(for: .camera, at: site), .ask)
        XCTAssertEqual(store.storedSites, [site])
    }

    func testWhenAllowOnceRawValueIsReadThenItHasNoPersistentRepresentation() {
        XCTAssertNil(SitePermissionDecision(rawValue: "allowOnce"))
        XCTAssertNil(SitePermissionDecision(rawValue: "allow_once"))
    }

    func testWhenGlobalDefaultIsMissingOrInvalidThenItIsAsk() {
        let keyValueStore = MockKeyValueStore()
        keyValueStore.set(["camera": "allow"], forKey: SitePermissionsStorageKeyNames.globalDefaults.rawValue)
        let store = makeStore(keyValueStore: keyValueStore)

        XCTAssertEqual(store.globalDefault(for: .camera), .ask)
        XCTAssertEqual(store.globalDefault(for: .microphone), .ask)
        XCTAssertNil(GlobalSitePermissionDecision(rawValue: "allow"))
    }

    func testWhenGlobalDefaultIsSetThenOnlyAskAndDenyCanBeStored() {
        let keyValueStore = MockKeyValueStore()
        let store = makeStore(keyValueStore: keyValueStore)

        store.setGlobalDefault(.deny, for: .location)
        XCTAssertEqual(store.globalDefault(for: .location), .deny)

        store.setGlobalDefault(.ask, for: .location)
        XCTAssertEqual(store.globalDefault(for: .location), .ask)
        XCTAssertEqual(keyValueStore.object(forKey: SitePermissionsStorageKeyNames.globalDefaults.rawValue) as? [String: String],
                       ["geolocation": "ask"])
    }

    func testWhenPermissionIsRemovedAndUndoneThenExactRecordIsRestored() throws {
        let keyValueStore = MockKeyValueStore()
        let original = ["example.com": ["camera": "allow", "future-permission": "future-decision"]]
        keyValueStore.set(original, forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue)
        let store = makeStore(keyValueStore: keyValueStore)
        let site = try makeSite("https://example.com")

        let snapshot = store.removePermissions(for: site)
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertNil(keyValueStore.object(forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue))

        store.restore(snapshot)

        XCTAssertEqual(
            keyValueStore.object(forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue) as? [String: [String: String]],
            original)
    }

    func testWhenNewerSiteRecordExistsThenUndoDoesNotOverwriteIt() throws {
        let keyValueStore = MockKeyValueStore()
        let store = makeStore(keyValueStore: keyValueStore)
        let site = try makeSite("https://example.com")
        store.setPersistentDecision(.allow, for: .camera, at: site)
        let snapshot = store.removePermissions(for: site)

        store.setPersistentDecision(.deny, for: .microphone, at: site)
        store.restore(snapshot)

        XCTAssertNil(store.decision(for: .camera, at: site))
        XCTAssertEqual(store.decision(for: .microphone, at: site), .deny)
    }

    func testWhenAllSitesAreClearedThenUndoRestoresOnlySitesWithoutNewerRecords() throws {
        let keyValueStore = MockKeyValueStore()
        let store = makeStore(keyValueStore: keyValueStore)
        let first = try makeSite("https://first.example")
        let second = try makeSite("https://second.example")
        store.setPersistentDecision(.allow, for: .camera, at: first)
        store.setPersistentDecision(.deny, for: .microphone, at: second)
        let snapshot = store.clearSitePermissions()

        store.setPersistentDecision(.deny, for: .location, at: first)
        store.restore(snapshot)

        XCTAssertNil(store.decision(for: .camera, at: first))
        XCTAssertEqual(store.decision(for: .location, at: first), .deny)
        XCTAssertEqual(store.decision(for: .microphone, at: second), .deny)
    }

    func testWhenClearExcludesHostThenItsExactRawRecordIsPreserved() {
        let keyValueStore = MockKeyValueStore()
        let original = [
            "fireproof.example": ["future-permission": "future-decision"],
            "removed.example": ["camera": "deny"]
        ]
        keyValueStore.set(original, forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue)
        let store = makeStore(keyValueStore: keyValueStore)

        let snapshot = store.clearSitePermissions { $0 == "fireproof.example" }

        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(keyValueStore.object(forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue) as? [String: [String: String]],
                       ["fireproof.example": ["future-permission": "future-decision"]])
    }

    func testWhenKnownDecisionChangesThenUnknownRawEntriesRemainUntouched() throws {
        let keyValueStore = MockKeyValueStore()
        keyValueStore.set(["example.com": ["future-permission": "future-decision"]],
                          forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue)
        let store = makeStore(keyValueStore: keyValueStore)
        let site = try makeSite("https://example.com")

        store.setPersistentDecision(.allow, for: .camera, at: site)

        XCTAssertEqual(keyValueStore.object(forKey: SitePermissionsStorageKeyNames.perSitePermissions.rawValue) as? [String: [String: String]],
                       ["example.com": ["future-permission": "future-decision", "camera": "allow"]])
    }

    private func makeStore(keyValueStore: KeyValueStoring) -> SitePermissionsStore {
        SitePermissionsStore(storage: keyValueStore.keyedStoring())
    }

    private func makeSite(_ urlString: String) throws -> SitePermissionKey {
        try XCTUnwrap(SitePermissionKey(committedURL: URL(string: urlString)!))
    }
}
