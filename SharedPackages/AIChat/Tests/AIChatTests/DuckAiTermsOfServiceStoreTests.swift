//
//  DuckAiTermsOfServiceStoreTests.swift
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

#if os(macOS)
import Combine
import Foundation
@_spi(Testing) import Persistence
import Testing
@testable import AIChat

@Suite("DuckAiTermsOfServiceStore")
final class DuckAiTermsOfServiceStoreTests {

    private let suiteName = "com.duckduckgo.aichat.tests.\(UUID().uuidString)"
    private let userDefaults: UserDefaults
    private let store: DuckAiTermsOfServiceStore

    init() {
        userDefaults = UserDefaults(suiteName: suiteName)!
        store = DuckAiTermsOfServiceStore(preferencesStorage: DefaultAIChatPreferencesStorage(userDefaults: userDefaults),
                                          keyValueStore: InMemoryThrowingKeyValueStore())
    }

    deinit {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    @Test("A fresh install hasn't accepted")
    func freshInstallHasNotAccepted() {
        #expect(!store.hasAccepted)
    }

    @Test("Accepting in the native input records acceptance")
    func acceptingInNativeInputRecordsAcceptance() {
        store.recordAcceptedInNativeInput()

        #expect(store.hasAccepted)
    }

    @Test("The web's first report is a first acceptance")
    func firstWebReportIsFirstAcceptance() {
        #expect(store.recordWebReport() == .firstAcceptance)
        #expect(store.hasAccepted)
    }

    @Test("A second web report is a repeat")
    func secondWebReportIsRepeat() {
        store.recordWebReport()

        #expect(store.recordWebReport() == .alreadyAccepted)
    }

    @Test("The web's report of a native acceptance isn't a repeat")
    func webReportOfNativeAcceptanceIsNotRepeat() {
        store.recordAcceptedInNativeInput()

        #expect(store.recordWebReport() == .firstAcceptance)
    }

    @Test("Only the first web report after a native acceptance is excused")
    func onlyFirstWebReportAfterNativeAcceptanceIsExcused() {
        store.recordAcceptedInNativeInput()
        store.recordWebReport()

        #expect(store.recordWebReport() == .alreadyAccepted)
    }

    @Test("Accepting natively after the web did doesn't excuse the next web report")
    func nativeAcceptanceAfterWebAcceptanceDoesNotExcuseNextReport() {
        store.recordWebReport()
        store.recordAcceptedInNativeInput()

        #expect(store.recordWebReport() == .alreadyAccepted)
    }

    @Test("The publisher emits when the user accepts")
    func publisherEmitsOnAcceptance() {
        var values: [Bool] = []
        let cancellable = store.hasAcceptedPublisher.sink { values.append($0) }

        store.recordAcceptedInNativeInput()
        cancellable.cancel()

        #expect(values.last == true)
    }

    // MARK: - Duck.ai's record in native storage

    private func makeStore(nativeStorage: DuckAiNativeStorageHandling) -> DuckAiTermsOfServiceStore {
        DuckAiTermsOfServiceStore(preferencesStorage: DefaultAIChatPreferencesStorage(userDefaults: userDefaults),
                                  keyValueStore: InMemoryThrowingKeyValueStore(),
                                  nativeStorage: nativeStorage)
    }

    @Test("Duck.ai's record in native storage counts as acceptance")
    func nativeStorageRecordCountsAsAcceptance() throws {
        let nativeStorage = try DuckAiNativeStorageHandler(.memory())
        try nativeStorage.putEntry(key: "duckaiHasAgreedToTerms", value: "true")

        #expect(makeStore(nativeStorage: nativeStorage).hasAccepted)
    }

    @Test("A boolean record in native storage counts as acceptance")
    func nativeStorageBooleanRecordCountsAsAcceptance() throws {
        let nativeStorage = try DuckAiNativeStorageHandler(.memory())
        try nativeStorage.putEntry(key: "duckaiHasAgreedToTerms", value: true)

        #expect(makeStore(nativeStorage: nativeStorage).hasAccepted)
    }

    @Test("A false record in native storage isn't acceptance")
    func nativeStorageFalseRecordIsNotAcceptance() throws {
        let nativeStorage = try DuckAiNativeStorageHandler(.memory())
        try nativeStorage.putEntry(key: "duckaiHasAgreedToTerms", value: "false")

        #expect(!makeStore(nativeStorage: nativeStorage).hasAccepted)
    }

    @Test("With native storage, the preferences flag alone isn't acceptance")
    func preferencesFlagAloneIsNotAcceptanceWithNativeStorage() throws {
        var preferencesStorage = DefaultAIChatPreferencesStorage(userDefaults: userDefaults)
        preferencesStorage.hasAcceptedTermsAndConditions = true

        #expect(!makeStore(nativeStorage: try DuckAiNativeStorageHandler(.memory())).hasAccepted)
    }

    @Test("Accepting in the native input writes Duck.ai's record")
    func acceptingInNativeInputWritesDuckAiRecord() throws {
        let nativeStorage = try DuckAiNativeStorageHandler(.memory())

        makeStore(nativeStorage: nativeStorage).recordAcceptedInNativeInput()

        #expect(try nativeStorage.getEntry(key: "duckaiHasAgreedToTerms") as? String == "true")
    }

    @Test("Duck.ai's first report is a first acceptance even when native storage already has its record")
    func firstWebReportIgnoresNativeStorageRecord() throws {
        let nativeStorage = try DuckAiNativeStorageHandler(.memory())
        try nativeStorage.putEntry(key: "duckaiHasAgreedToTerms", value: "true")

        #expect(makeStore(nativeStorage: nativeStorage).recordWebReport() == .firstAcceptance)
    }

    @Test("The publisher emits when Duck.ai records acceptance in native storage")
    func publisherEmitsOnNativeStorageRecord() throws {
        let nativeStorage = try DuckAiNativeStorageHandler(.memory())
        let store = makeStore(nativeStorage: nativeStorage)
        var values: [Bool] = []
        let cancellable = store.hasAcceptedPublisher.sink { values.append($0) }

        try nativeStorage.putEntry(key: "duckaiHasAgreedToTerms", value: "true")
        cancellable.cancel()

        #expect(values.last == true)
    }
}
#endif
