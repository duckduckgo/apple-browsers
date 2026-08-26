//
//  DuckAiUsageLimitsStoreTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAiUsageLimitsStoreTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
#if DEBUG || ALPHA
        DuckAiUsageLimitsStore.debugOverride = nil
#endif
        super.tearDown()
    }

    // MARK: - Feature gating

    func test_makeWarningViewModel_isNilWhenTheFeatureFlagIsOff() {
        let sut = makeStore(storage: seededStorage(weeklyPercent: 80), isFeatureOn: false)

        XCTAssertNil(sut.makeWarningViewModel(surfaceProvider: { .addressBar },
                                              modelSuggester: NullDuckAiModelSuggester(),
                                              isTrialEligible: { false },
                                              isFireMode: { false }))
    }

    func test_makeWarningViewModel_isNilWhenThereIsNoStorageBridge() {
        let sut = makeStore(storage: nil)

        XCTAssertNil(sut.makeWarningViewModel(surfaceProvider: { .addressBar },
                                              modelSuggester: NullDuckAiModelSuggester(),
                                              isTrialEligible: { false },
                                              isFireMode: { false }))
    }

    // MARK: - Reading the snapshot

    func test_warning_readsTheSnapshotWrittenByTheWebApp() {
        let viewModel = makeViewModel(storage: seededStorage(weeklyPercent: 80))

        viewModel?.refresh()

        XCTAssertEqual(viewModel?.warning?.window, .weekly)
        XCTAssertEqual(viewModel?.warning?.percent, 80)
    }

    func test_warning_isNilWhenStorageHoldsNothing() {
        let viewModel = makeViewModel(storage: DuckAiNativeMemoryStorageHandler())

        viewModel?.refresh()

        XCTAssertNil(viewModel?.warning)
    }

    func test_warning_isNilWhenTheNoticeHasAlreadyReset() {
        let viewModel = makeViewModel(storage: seededStorage(weeklyPercent: 80, resetsAt: now.addingTimeInterval(-60)))

        viewModel?.refresh()

        XCTAssertNil(viewModel?.warning)
    }

    func test_warning_isNilInFireMode() {
        let viewModel = makeViewModel(storage: seededStorage(weeklyPercent: 80), isFireMode: true)

        viewModel?.refresh()

        XCTAssertNil(viewModel?.warning)
    }

    // MARK: - Debug override

#if DEBUG || ALPHA
    func test_warning_prefersTheDebugOverrideSnapshot() {
        let viewModel = makeViewModel(storage: seededStorage(weeklyPercent: 80))
        DuckAiUsageLimitsStore.debugOverride = DuckAiUsageSnapshot.make(
            entryValue: Self.snapshotJSON(weeklyPercent: 95, resetsAt: now.addingTimeInterval(172_800)),
            now: now
        )

        viewModel?.refresh()

        XCTAssertEqual(viewModel?.warning?.percent, 95)
    }
#endif

    // MARK: - Writing the hand-off

    /// Web owns the key and the value; the store writes exactly what it sent.
    func test_write_putsTheEntriesWebNamed() throws {
        let storage = DuckAiNativeMemoryStorageHandler()

        XCTAssertTrue(makeStore(storage: storage).write([
            DuckAiNativeStorageEntry(key: "duckai.fixedCostWindowBypassResetAtById",
                                     value: "{\"day\":\"2026-08-22T00:00:00.000Z\"}")
        ]))
        XCTAssertEqual(try storage.getEntry(key: "duckai.fixedCostWindowBypassResetAtById") as? String,
                       "{\"day\":\"2026-08-22T00:00:00.000Z\"}")
    }

    func test_write_isRefusedWhenTheFeatureFlagIsOff() throws {
        let storage = DuckAiNativeMemoryStorageHandler()

        XCTAssertFalse(makeStore(storage: storage, isFeatureOn: false)
            .write([DuckAiNativeStorageEntry(key: "duckai.a", value: "{}")]))
        XCTAssertNil(try storage.getEntry(key: "duckai.a"))
    }

    func test_write_isRefusedWhenThereIsNoStorageBridge() {
        XCTAssertFalse(makeStore(storage: nil).write([DuckAiNativeStorageEntry(key: "duckai.a", value: "{}")]))
    }

    // MARK: - Helpers

    private func makeStore(storage: DuckAiNativeStorageHandling?, isFeatureOn: Bool = true) -> DuckAiUsageLimitsStore {
        DuckAiUsageLimitsStore(storageHandler: storage,
                              featureFlagger: MockFeatureFlagger(enabledFeatureFlags: isFeatureOn ? [.utiDuckAIWarnings] : []),
                              dismissalStore: InMemoryDuckAiUsageWarningDismissalStore(),
                              dateProvider: { [unowned self] in now })
    }

    private func makeViewModel(storage: DuckAiNativeStorageHandling?,
                               isFireMode: Bool = false) -> DuckAiUsageWarningViewModel? {
        makeStore(storage: storage).makeWarningViewModel(surfaceProvider: { .addressBar },
                                                        modelSuggester: NullDuckAiModelSuggester(),
                                                        isTrialEligible: { false },
                                                        isFireMode: { isFireMode })
    }

    private func seededStorage(weeklyPercent: Int, resetsAt: Date? = nil) -> DuckAiNativeStorageHandling {
        let storage = DuckAiNativeMemoryStorageHandler()
        try? storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue,
                              value: Self.snapshotJSON(weeklyPercent: weeklyPercent,
                                                       resetsAt: resetsAt ?? now.addingTimeInterval(172_800)))
        return storage
    }

    /// The shape web writes now: a notice, not the windows older clients read.
    private static func snapshotJSON(weeklyPercent: Int, resetsAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return """
        {"notice":{"id":"approaching","window":"weekly","percentUsed":\(weeklyPercent),\
        "resetsAt":"\(formatter.string(from: resetsAt))","reached":false,"dismissible":true}}
        """
    }
}
