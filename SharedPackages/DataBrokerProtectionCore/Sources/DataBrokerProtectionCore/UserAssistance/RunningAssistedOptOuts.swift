//
//  RunningAssistedOptOuts.swift
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

/// The opt-out records running right now. Scheduled and assisted runs both claim a record here, so it never runs twice at once.
public final class RunningAssistedOptOuts: @unchecked Sendable {
    private let lock = NSLock()
    private enum Owner { case regular, assisted }
    private var owners: [AssistedOptOutID: Owner] = [:]

    public init() {}

    public func contains(_ id: AssistedOptOutID) -> Bool {
        lock.withLock { owners[id] != nil }
    }

    public func isRegularRunning(_ id: AssistedOptOutID) -> Bool {
        lock.withLock { owners[id] == .regular }
    }

    public func tryInsertRegular(_ id: AssistedOptOutID) -> Bool {
        tryInsert(id, as: .regular)
    }

    public func tryInsertAssisted(_ id: AssistedOptOutID) -> Bool {
        tryInsert(id, as: .assisted)
    }

    private func tryInsert(_ id: AssistedOptOutID, as owner: Owner) -> Bool {
        lock.withLock {
            guard owners[id] == nil else { return false }
            owners[id] = owner
            return true
        }
    }

    public func remove(_ id: AssistedOptOutID) {
        lock.withLock { owners[id] = nil }
    }
}
