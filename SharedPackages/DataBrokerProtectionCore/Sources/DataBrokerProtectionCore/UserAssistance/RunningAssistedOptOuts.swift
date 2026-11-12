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

public final class RunningAssistedOptOuts: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<AssistedOptOutID> = []

    public init() {}

    public func contains(_ id: AssistedOptOutID) -> Bool {
        lock.withLock { ids.contains(id) }
    }

    public func insert(_ id: AssistedOptOutID) {
        lock.withLock { _ = ids.insert(id) }
    }

    public func remove(_ id: AssistedOptOutID) {
        lock.withLock { _ = ids.remove(id) }
    }
}
