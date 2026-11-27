//
//  AIChatUserDefaultModelTests.swift
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

import Combine
import Foundation
import Testing
@testable import AIChat
import AIChatTestingUtilities

@Suite("User default model: native storage entry")
struct DuckAiUserDefaultModelStoreTests {

    private static let entryKey = DuckAiNativeStorageReservedEntryKeys.defaultDuckaiModel.rawValue

    @available(iOS 16, macOS 13, *)
    @Test("The JSON-encoded model id web writes is read", .timeLimit(.minutes(1)))
    func jsonEncodedId() {
        #expect(DuckAiUserDefaultModelStore.modelId(fromEntryValue: #""gpt-6-luna""#) == "gpt-6-luna")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Anything else reads as not set", .timeLimit(.minutes(1)),
          arguments: [nil, "", #""""#, "gpt-6-luna", "42", "null", "{}", #"["gpt-6-luna"]"#, "{oops"] as [String?])
    func malformedIsNotSet(value: String?) {
        #expect(DuckAiUserDefaultModelStore.modelId(fromEntryValue: value) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A non-string value reads as not set", .timeLimit(.minutes(1)))
    func nonStringIsNotSet() {
        #expect(DuckAiUserDefaultModelStore.modelId(fromEntryValue: 42) == nil)
        #expect(DuckAiUserDefaultModelStore.modelId(fromEntryValue: ["modelId": "gpt-6-luna"]) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each read sees the latest stored value, even once cached", .timeLimit(.minutes(1)))
    func readsLiveValue() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        let store = DuckAiUserDefaultModelStore(storage: storage)
        #expect(store.modelId == nil)

        try storage.putUserDefaultModel("claude-haiku-5-5")
        #expect(store.modelId == "claude-haiku-5-5")

        try storage.deleteEntry(key: Self.entryKey)
        #expect(store.modelId == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Announces writes to the setting only", .timeLimit(.minutes(1)))
    func announcesSettingChanges() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        var changeCount = 0
        let store = DuckAiUserDefaultModelStore(storage: storage)
        let cancellable = store.changes.sink { changeCount += 1 }

        try storage.putUserDefaultModel("claude-haiku-5-5")
        try storage.putEntry(key: "unrelated", value: "1")
        try storage.deleteEntry(key: Self.entryKey)

        #expect(changeCount == 2)
        cancellable.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fire mode reads the user default through from normal storage", .timeLimit(.minutes(1)))
    func fireModeReadsThrough() throws {
        let normal = try DuckAiNativeStorageHandler(.memory())
        try normal.putUserDefaultModel("gpt-6-luna")
        let fire = try DuckAiNativeStorageHandler(.memory(seedSource: normal))

        #expect(DuckAiUserDefaultModelStore(storage: fire).modelId == "gpt-6-luna")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fire mode sees a setting changed in normal storage", .timeLimit(.minutes(1)))
    func fireModeIsNeverStale() throws {
        let normal = try DuckAiNativeStorageHandler(.memory())
        try normal.putUserDefaultModel("gpt-6-luna")
        let store = DuckAiUserDefaultModelStore(storage: try DuckAiNativeStorageHandler(.memory(seedSource: normal)))
        #expect(store.modelId == "gpt-6-luna")

        try normal.putUserDefaultModel("claude-haiku-5-5")

        #expect(store.modelId == "claude-haiku-5-5")
    }
}

@Suite("User default model: fire storage")
struct DuckAiUserDefaultModelFireStorageTests {

    private static let entryKey = DuckAiNativeStorageReservedEntryKeys.defaultDuckaiModel.rawValue

    private func makeStorages(userDefault: String = "gpt-6-luna") throws -> (normal: DuckAiNativeStorageHandler, fire: DuckAiNativeStorageHandler) {
        let normal = try DuckAiNativeStorageHandler(.memory())
        try normal.putUserDefaultModel(userDefault)
        return (normal, try DuckAiNativeStorageHandler(.memory(seedSource: normal)))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Clearing the setting in fire storage hides the normal one", .timeLimit(.minutes(1)))
    func clearedInFireStorage() throws {
        let (normal, fire) = try makeStorages()
        let store = DuckAiUserDefaultModelStore(storage: fire)

        try fire.deleteEntry(key: Self.entryKey)

        #expect(store.modelId == nil)
        #expect(try fire.getAllEntries()[Self.entryKey] == nil)
        #expect(DuckAiUserDefaultModelStore(storage: normal).modelId == "gpt-6-luna")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Deleting a consent entry in fire storage still reads it through", .timeLimit(.minutes(1)))
    func consentStillReadsThrough() throws {
        let (normal, fire) = try makeStorages()
        try normal.putEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey, value: "true")

        try fire.deleteEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey)

        #expect(try fire.getEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey) as? String == "true")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Wiping fire storage shows the normal setting again", .timeLimit(.minutes(1)))
    func wipeShowsNormalSettingAgain() throws {
        let (_, fire) = try makeStorages()
        try fire.deleteEntry(key: Self.entryKey)

        try fire.deleteAllEntries()

        #expect(DuckAiUserDefaultModelStore(storage: fire).modelId == "gpt-6-luna")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fire storage announces a setting changed in normal storage", .timeLimit(.minutes(1)))
    func announcesNormalChanges() throws {
        let (normal, fire) = try makeStorages()
        var updates: [DuckAiNativeStorageReservedEntryKeys] = []
        let cancellable = fire.reservedEntryUpdatesPublisher.sink { updates.append($0) }

        try normal.putUserDefaultModel("claude-haiku-5-5")
        try normal.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue, value: "{}")

        #expect(updates == [.defaultDuckaiModel])
        cancellable.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("A fire store announces and serves a setting changed in normal storage", .timeLimit(.minutes(1)))
    func storeFollowsNormalChanges() throws {
        let (normal, fire) = try makeStorages()
        let store = DuckAiUserDefaultModelStore(storage: fire)
        #expect(store.modelId == "gpt-6-luna")
        var changeCount = 0
        let cancellable = store.changes.sink { changeCount += 1 }

        try normal.putUserDefaultModel("claude-haiku-5-5")

        #expect(changeCount == 1)
        #expect(store.modelId == "claude-haiku-5-5")
        cancellable.cancel()
    }
}
