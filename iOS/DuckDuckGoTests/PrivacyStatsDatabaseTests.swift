//
//  PrivacyStatsDatabaseTests.swift
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

import CoreData
import Foundation
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo

final class PrivacyStatsDatabaseTests: XCTestCase {

    private var location: URL!
    private var pixelKit: PixelKitMock!

    override func setUpWithError() throws {
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        pixelKit = PixelKitMock()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: location)
    }

    func testWhenStoreLoadsThenDatabaseIsUsableAndNoPixelIsFired() throws {
        let database = try XCTUnwrap(PrivacyStatsDatabase(location: location, pixelFiring: pixelKit))

        try assertStoreIsUsable(database)
        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty)
    }

    func testWhenStoreIsCorruptedThenItIsRecreatedAndPixelIsFired() throws {
        try Data(repeating: 0xAB, count: 4096).write(to: location.appendingPathComponent("PrivacyStats.sqlite"))

        // Before the fix, creating PrivacyStats never returned here.
        let database = try XCTUnwrap(PrivacyStatsDatabase(location: location, pixelFiring: pixelKit))

        try assertStoreIsUsable(database)
        XCTAssertEqual(pixelKit.actualFireCalls.count, 1)
        let call = try XCTUnwrap(pixelKit.actualFireCalls.first)
        XCTAssertEqual(call.pixel.name, "privacy-stats_database_load_failed")
        XCTAssertEqual(call.pixel.parameters, ["stage": "initial"])
        XCTAssertEqual(call.pixel.error?.domain, NSCocoaErrorDomain)
        XCTAssertEqual(call.frequency, .dailyAndCount)
    }

    func testWhenStoreCannotBeRecreatedThenDatabaseIsNilAndBothAttemptsFirePixel() throws {
        // A regular file in the store's path means the store directory can never be created.
        let blockingFile = location.appendingPathComponent("blocker")
        try Data().write(to: blockingFile)

        let database = PrivacyStatsDatabase(location: blockingFile.appendingPathComponent("store"), pixelFiring: pixelKit)

        XCTAssertNil(database)
        XCTAssertEqual(pixelKit.actualFireCalls.map(\.pixel.parameters), [["stage": "initial"], ["stage": "retry"]])
        XCTAssertEqual(pixelKit.actualFireCalls.map(\.frequency), [.dailyAndCount, .dailyAndCount])
    }

    private func assertStoreIsUsable(_ database: PrivacyStatsDatabase) throws {
        let context = database.initializeDatabase().makeContext(concurrencyType: .privateQueueConcurrencyType)
        var saveError: Error?
        context.performAndWait {
            XCTAssertFalse(context.persistentStoreCoordinator?.persistentStores.isEmpty ?? true)
            do {
                try context.save()
            } catch {
                saveError = error
            }
        }
        if let saveError { throw saveError }
    }
}
