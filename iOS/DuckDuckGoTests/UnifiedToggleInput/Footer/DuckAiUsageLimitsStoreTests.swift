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

final class DuckAiUsageLimitsStoreTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func test_currentLimits_isNilWhenTheFeatureFlagIsOff() {
        let sut = makeStore(storage: seededStorage(weeklyPercent: 80), isFeatureOn: false)

        XCTAssertNil(sut.currentLimits())
    }

    func test_currentLimits_isNilWhenThereIsNoStorageBridge() {
        let sut = makeStore(storage: nil)

        XCTAssertNil(sut.currentLimits())
    }

    func test_currentLimits_readsTheSnapshotWrittenByTheWebApp() {
        let sut = makeStore(storage: seededStorage(weeklyPercent: 80, resetsAt: now.addingTimeInterval(172_800)))

        let limits = sut.currentLimits()

        XCTAssertEqual(limits?.weekly?.percentUsed, 80)
        XCTAssertEqual(limits?.weekly?.resetsAt.timeIntervalSince1970 ?? 0,
                       now.addingTimeInterval(172_800).timeIntervalSince1970,
                       accuracy: 1)
    }

    func test_currentLimits_isNoDataWhenStorageHoldsNothing() {
        let sut = makeStore(storage: DuckAiNativeMemoryStorageHandler())

        XCTAssertEqual(sut.currentLimits(), .noData)
    }

    func test_currentLimits_dropsAWindowThatHasAlreadyReset() {
        let sut = makeStore(storage: seededStorage(weeklyPercent: 80, resetsAt: now.addingTimeInterval(-60)))

        XCTAssertEqual(sut.currentLimits(), .noData)
    }

    // MARK: - Helpers

    private func makeStore(storage: DuckAiNativeStorageHandling?, isFeatureOn: Bool = true) -> DuckAiUsageLimitsStore {
        DuckAiUsageLimitsStore(storageHandler: storage,
                               featureFlagger: MockFeatureFlagger(enabledFeatureFlags: isFeatureOn ? [.utiDuckAIWarnings] : []),
                               dateProvider: { [unowned self] in now })
    }

    private func seededStorage(weeklyPercent: Double, resetsAt: Date? = nil) -> DuckAiNativeStorageHandling {
        let storage = DuckAiNativeMemoryStorageHandler()
        try? storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue,
                              value: Self.snapshotJSON(weeklyPercent: weeklyPercent,
                                                       resetsAt: resetsAt ?? now.addingTimeInterval(172_800)))
        return storage
    }

    private static func snapshotJSON(weeklyPercent: Double, resetsAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return """
        {"weekly":{"percentUsed":\(weeklyPercent),"resetsAt":"\(formatter.string(from: resetsAt))"}}
        """
    }
}

final class UTIFooterWarningProviderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func test_currentWarning_resolvesTheSnapshotHeldInNativeStorage() {
        let sut = makeProvider(weeklyPercent: 80)

        let warning = sut.currentWarning()

        guard case .usageThreshold(let window, let threshold, _) = warning else {
            return XCTFail("Expected a usage threshold, got \(String(describing: warning))")
        }
        XCTAssertEqual(window, .weekly)
        XCTAssertEqual(threshold, .seventyFive)
    }

    func test_currentWarning_isNilWhenTheFeatureIsInactive() {
        let sut = makeProvider(weeklyPercent: 80, isFeatureOn: false)

        XCTAssertNil(sut.currentWarning())
    }

    func test_currentWarning_isNilWhenUsageIsBelowEveryThreshold() {
        let sut = makeProvider(weeklyPercent: 20)

        XCTAssertNil(sut.currentWarning())
    }

    private func makeProvider(weeklyPercent: Double, isFeatureOn: Bool = true) -> UTIFooterWarningProvider {
        let storage = DuckAiNativeMemoryStorageHandler()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let json = """
        {"weekly":{"percentUsed":\(weeklyPercent),"resetsAt":"\(formatter.string(from: now.addingTimeInterval(172_800)))"}}
        """
        try? storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue, value: json)

        let store = DuckAiUsageLimitsStore(storageHandler: storage,
                                           featureFlagger: MockFeatureFlagger(enabledFeatureFlags: isFeatureOn ? [.utiDuckAIWarnings] : []),
                                           dateProvider: { [unowned self] in now })
        return UTIFooterWarningProvider(limitsStore: store)
    }
}

final class UTIFireTabAwareFooterWarningProviderTests: XCTestCase {

    private let normalWarning = UTIFooterWarning.usageThreshold(window: .weekly,
                                                                threshold: .ninety,
                                                                resetsAt: Date(timeIntervalSince1970: 1_800_172_800))
    private let fireWarning = UTIFooterWarning.usageThreshold(window: .daily,
                                                              threshold: .fifty,
                                                              resetsAt: Date(timeIntervalSince1970: 1_800_086_400))

    func test_currentWarning_readsTheNormalTabSourceOutsideAFireTab() {
        let sut = makeProvider(isFireTab: { false })

        XCTAssertEqual(sut.currentWarning(), normalWarning)
    }

    func test_currentWarning_readsTheFireTabSourceOnAFireTab() {
        let sut = makeProvider(isFireTab: { true })

        XCTAssertEqual(sut.currentWarning(), fireWarning)
    }

    func test_currentWarning_isNilOnAFireTabWithNoFireTabSource() {
        let sut = UTIFireTabAwareFooterWarningProvider(normalTabProvider: StubUTIFooterWarningProvider(warning: normalWarning),
                                                       fireTabProvider: nil,
                                                       isFireTab: { true })

        XCTAssertNil(sut.currentWarning())
    }

    func test_currentWarning_followsTheFireTabStateAcrossReads() {
        var isFireTab = false
        let sut = makeProvider(isFireTab: { isFireTab })

        XCTAssertEqual(sut.currentWarning(), normalWarning)
        isFireTab = true
        XCTAssertEqual(sut.currentWarning(), fireWarning)
    }

    private func makeProvider(isFireTab: @escaping () -> Bool) -> UTIFireTabAwareFooterWarningProvider {
        UTIFireTabAwareFooterWarningProvider(normalTabProvider: StubUTIFooterWarningProvider(warning: normalWarning),
                                             fireTabProvider: StubUTIFooterWarningProvider(warning: fireWarning),
                                             isFireTab: isFireTab)
    }
}

private struct StubUTIFooterWarningProvider: UTIFooterWarningProviding {
    let warning: UTIFooterWarning?

    func currentWarning() -> UTIFooterWarning? { warning }
}
