//
//  MockAIChatBonusStore.swift
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
@testable import AIChat

/// An in-memory store. Setting an error makes that operation throw without touching the record.
final class MockAIChatBonusStore: AIChatBonusStoring {

    var storedRecord: AIChatBonusRecord?
    var readError: Error?
    var writeError: Error?
    var deleteError: Error?

    private(set) var readCallCount = 0
    private(set) var writeCallCount = 0
    private(set) var deleteCallCount = 0

    init(storedRecord: AIChatBonusRecord? = nil) {
        self.storedRecord = storedRecord
    }

    func read() throws -> AIChatBonusRecord? {
        readCallCount += 1
        if let readError { throw readError }
        return storedRecord
    }

    func write(_ record: AIChatBonusRecord) throws {
        writeCallCount += 1
        if let writeError { throw writeError }
        storedRecord = record
    }

    func delete() throws {
        deleteCallCount += 1
        if let deleteError { throw deleteError }
        storedRecord = nil
    }
}
