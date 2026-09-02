//
//  LegacyPixelStateMigrationTests.swift
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

import XCTest
import Persistence
@testable import Core

final class LegacyPixelStateMigrationTests: XCTestCase {

    /// In-memory `ThrowingKeyValueStoring`, so the tests touch neither UserDefaults nor the disk.
    final class Store: ThrowingKeyValueStoring {
        var values: [String: Any]
        var throwOnRead = false

        init(_ values: [String: Any] = [:]) { self.values = values }

        func object(forKey defaultName: String) throws -> Any? {
            if throwOnRead { throw NSError(domain: "Store", code: 1) }
            return values[defaultName]
        }
        func set(_ value: Any?, forKey defaultName: String) throws { values[defaultName] = value }
        func removeObject(forKey defaultName: String) throws { values.removeValue(forKey: defaultName) }
    }

    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func key(_ name: String) -> String {
        "com.duckduckgo.network-protection.pixel.\(name)"
    }

    private func migration(destination: Store,
                           daily: Store? = nil,
                           unique: Store? = nil,
                           debounce: Store? = nil,
                           flags: Store? = nil,
                           version: String = "1.0.0") -> LegacyPixelStateMigration {
        LegacyPixelStateMigration(destination: destination,
                                  dailyStore: daily,
                                  uniqueStore: unique,
                                  debounceStore: debounce,
                                  completionFlagStore: flags ?? Store(),
                                  migrationVersion: version)
    }

    func testCopiesADailyLastFireDateUnderTheDailyMapKey() throws {
        let destination = Store()
        migration(destination: destination, daily: Store(["m_example": date])).run()

        XCTAssertEqual(destination.values[key("m_example")] as? [String: Date], ["daily": date])
    }

    func testCopiesAUniqueLastFireDateUnderTheUniqueByNameMapKey() throws {
        let destination = Store()
        migration(destination: destination, unique: Store(["m_example_u": date])).run()

        XCTAssertEqual(destination.values[key("m_example_u")] as? [String: Date],
                       ["uniqueByName": date])
    }

    func testCopiesADebounceLastFireDateUnderTheDebounceMapKey() throws {
        let destination = Store()
        migration(destination: destination, debounce: Store(["m_example": date])).run()

        XCTAssertEqual(destination.values[key("m_example")] as? [String: Date], ["debounce": date])
    }

    func testMergesWhenTheSameNameAppearsInMoreThanOneLegacyStore() throws {
        let destination = Store()
        let otherDate = date.addingTimeInterval(-3600)
        migration(destination: destination,
                  daily: Store(["m_example": date]),
                  debounce: Store(["m_example": otherDate])).run()

        XCTAssertEqual(destination.values[key("m_example")] as? [String: Date],
                       ["daily": date, "debounce": otherDate])
    }

    func testPreservesAnExistingPixelKitEntry() throws {
        // A pixel already fired through PixelKit before the migration ran must not lose its state.
        let existing = date.addingTimeInterval(-7200)
        let destination = Store([key("m_example"): ["uniqueByName": existing]])
        migration(destination: destination, daily: Store(["m_example": date])).run()

        XCTAssertEqual(destination.values[key("m_example")] as? [String: Date],
                       ["uniqueByName": existing, "daily": date])
    }

    func testSkipsNonDateValues() throws {
        // The legacy daily store also holds compound `name:<error values>` keys and, defensively,
        // anything else a past version wrote. Only `Date` values mean anything here.
        let destination = Store()
        migration(destination: destination, daily: Store(["m_example": "not a date"])).run()

        XCTAssertTrue(destination.values.isEmpty)
    }

    func testDoesNothingOnASecondRun() throws {
        let destination = Store()
        let flags = Store()
        let daily = Store(["m_example": date])

        migration(destination: destination, daily: daily, flags: flags).run()
        destination.values.removeAll()
        migration(destination: destination, daily: daily, flags: flags).run()

        XCTAssertTrue(destination.values.isEmpty)
    }

    func testRecordsTheMigratingVersion() throws {
        let flags = Store()
        migration(destination: Store(), daily: Store(["m_example": date]), flags: flags, version: "7.1.0").run()

        XCTAssertEqual(flags.values[LegacyPixelStateMigration.completionFlagKey] as? String, "7.1.0")
    }

    func testRunsAgainOnANewAppVersion() throws {
        // PixelKit can ship a release or more before the call sites move onto it. Until they do, the
        // legacy store keeps taking the writes, so each upgrade has to pick up what it recorded.
        let flags = Store()
        let destination = Store()
        migration(destination: destination, daily: Store(["m_example": date]), flags: flags, version: "7.1.0").run()

        let laterDate = date.addingTimeInterval(86_400)
        migration(destination: destination, daily: Store(["m_example": laterDate]), flags: flags, version: "7.2.0").run()

        XCTAssertEqual(destination.values[key("m_example")] as? [String: Date], ["daily": laterDate])
        XCTAssertEqual(flags.values[LegacyPixelStateMigration.completionFlagKey] as? String, "7.2.0")
    }

    func testRunsOnceMoreWhenTheFlagIsThePreVersionedBool() throws {
        // Installs that ran the migration before the flag became version-keyed hold `true`.
        let flags = Store([LegacyPixelStateMigration.completionFlagKey: true])
        let destination = Store()
        migration(destination: destination, daily: Store(["m_example": date]), flags: flags, version: "7.2.0").run()

        XCTAssertEqual(destination.values[key("m_example")] as? [String: Date], ["daily": date])
        XCTAssertEqual(flags.values[LegacyPixelStateMigration.completionFlagKey] as? String, "7.2.0")
    }

    func testKeepsTheLaterOfTheTwoDates() throws {
        // A re-run must not walk a date backwards: PixelKit's own entry is the newer one once the
        // call sites have moved over.
        let newer = date.addingTimeInterval(3600)
        let destination = Store([key("m_example"): ["daily": newer]])
        migration(destination: destination, daily: Store(["m_example": date]), version: "7.2.0").run()

        XCTAssertEqual(destination.values[key("m_example")] as? [String: Date], ["daily": newer])
    }

    func testAnAbsentLegacyStoreIsNotAnError() throws {
        let destination = Store()
        migration(destination: destination).run()

        XCTAssertTrue(destination.values.isEmpty)
    }

    func testAFailingLegacyStoreDoesNotBlockTheOthers() throws {
        // Fail open: a store we cannot read costs us that store's throttle state, which is one extra
        // fire per pixel. Abandoning the whole migration would cost every store's.
        let destination = Store()
        let broken = Store(["m_broken": date])
        broken.throwOnRead = true
        migration(destination: destination, daily: broken, unique: Store(["m_example_u": date])).run()

        XCTAssertEqual(destination.values[key("m_example_u")] as? [String: Date],
                       ["uniqueByName": date])
    }

    func testDistinctCompletionFlagKeysDoNotShareARun() throws {
        // Two processes that both fall back to the same UserDefaults suite (e.g. Widgets and the
        // VPN tunnel's failure path) must not let whichever runs first for a version mark the flag
        // complete for the other.
        let flags = Store()
        let destinationA = Store()
        let destinationB = Store()

        LegacyPixelStateMigration(destination: destinationA, dailyStore: Store(["m_a": date]), uniqueStore: nil,
                                  debounceStore: nil, completionFlagStore: flags, completionFlagKey: "flag.a").run()
        LegacyPixelStateMigration(destination: destinationB, dailyStore: Store(["m_b": date]), uniqueStore: nil,
                                  debounceStore: nil, completionFlagStore: flags, completionFlagKey: "flag.b").run()

        XCTAssertEqual(destinationA.values[key("m_a")] as? [String: Date], ["daily": date],
                       "The second migration's distinct flag key must not make the first look already-run")
        XCTAssertEqual(destinationB.values[key("m_b")] as? [String: Date], ["daily": date])
        XCTAssertEqual(flags.values["flag.a"] as? String, "1.0.0")
        XCTAssertEqual(flags.values["flag.b"] as? String, "1.0.0")
    }
}

extension LegacyPixelStateMigrationTests.Store: LegacyPixelLastFireDateSource {
    func allLastFireDates() throws -> [String: Date] {
        if throwOnRead { throw NSError(domain: "Store", code: 1) }
        return values.compactMapValues { $0 as? Date }
    }
}

final class UserDefaultsLegacyPixelStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "\(Self.self)-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testReturnsOnlyThisSuitesOwnKeys() throws {
        defaults.set(Date(), forKey: "m_example")
        let store = UserDefaultsLegacyPixelStore(suiteName: suiteName)!

        let dates = try store.allLastFireDates()

        XCTAssertEqual(dates.count, 1)
        XCTAssertEqual(Array(dates.keys), ["m_example"])
    }

    func testDoesNotLeakGlobalDomainKeys() throws {
        // A freshly created, empty suite still returns many keys from the domains
        // `dictionaryRepresentation()` merges in. `allLastFireDates()` must not.
        XCTAssertGreaterThan(defaults.dictionaryRepresentation().count, 1)

        let store = UserDefaultsLegacyPixelStore(suiteName: suiteName)!
        XCTAssertTrue(try store.allLastFireDates().isEmpty)
    }
}
