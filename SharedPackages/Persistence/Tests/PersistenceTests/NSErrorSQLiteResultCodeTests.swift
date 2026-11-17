//
//  NSErrorSQLiteResultCodeTests.swift
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
@testable import Persistence
import Testing

@Suite("NSError SQLite result code unpacking")
struct NSErrorSQLiteResultCodeTests {

    @available(iOS 16, macOS 13, *)
    @Test("The SQLite result code becomes the underlying error", .timeLimit(.minutes(1)))
    func resultCodeBecomesUnderlyingError() throws {
        let error = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [
            NSSQLiteErrorDomain: NSNumber(value: 4618),
            NSFilePathErrorKey: "/path/to/store.sqlite"
        ])

        let unpacked = error.unpackingSQLiteResultCode()

        #expect(unpacked.domain == NSCocoaErrorDomain)
        #expect(unpacked.code == 256)
        #expect(unpacked.userInfo[NSFilePathErrorKey] as? String == "/path/to/store.sqlite")
        #expect(unpacked.userInfo[NSSQLiteErrorDomain] as? NSNumber == 4618)
        let underlying = try #require(unpacked.userInfo[NSUnderlyingErrorKey] as? NSError)
        #expect(underlying.domain == NSSQLiteErrorDomain)
        #expect(underlying.code == 4618)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An error without a SQLite result code is returned unchanged", .timeLimit(.minutes(1)))
    func errorWithoutResultCodeIsUnchanged() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 256)

        #expect(error.unpackingSQLiteResultCode() === error)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An existing underlying error is kept", .timeLimit(.minutes(1)))
    func existingUnderlyingErrorIsKept() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 28)
        let error = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [
            NSSQLiteErrorDomain: NSNumber(value: 13),
            NSUnderlyingErrorKey: underlying
        ])

        #expect(error.unpackingSQLiteResultCode() === error)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A store that fails to load reports its SQLite result code as the underlying error", .timeLimit(.minutes(1)))
    func failedStoreLoadReportsResultCode() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: location) }
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 4096).write(to: location.appendingPathComponent("Junk.sqlite"))
        let database = CoreDataDatabase(name: "Junk", containerLocation: location, model: NSManagedObjectModel())

        let error: Error? = await withCheckedContinuation { continuation in
            database.loadStore { _, error in continuation.resume(returning: error) }
        }

        let nsError = try #require(error as NSError?)
        let underlying = try #require(nsError.userInfo[NSUnderlyingErrorKey] as? NSError)
        #expect(underlying.domain == NSSQLiteErrorDomain)
        #expect(underlying.code == (nsError.userInfo[NSSQLiteErrorDomain] as? NSNumber)?.intValue)
    }
}
