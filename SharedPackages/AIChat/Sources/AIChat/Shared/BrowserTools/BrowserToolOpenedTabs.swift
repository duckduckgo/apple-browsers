//
//  BrowserToolOpenedTabs.swift
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

/// Tabs Duck.ai opened, per owner tab, oldest first. Only these may be closed by Duck.ai or read
/// without a prompt, and only by the chat that opened them. In memory only: a relaunch forgets them.
@MainActor
public final class BrowserToolOpenedTabs {

    private var tabIDsByOwner: [String: [String]] = [:]

    public init() {}

    public func add(_ tabID: String, ownerTabID: String) {
        remove(tabID)
        tabIDsByOwner[ownerTabID, default: []].append(tabID)
    }

    public func contains(_ tabID: String, ownerTabID: String) -> Bool {
        tabIDsByOwner[ownerTabID]?.contains(tabID) ?? false
    }

    /// Whether any chat opened it.
    public func contains(_ tabID: String) -> Bool {
        tabIDsByOwner.values.contains { $0.contains(tabID) }
    }

    /// Oldest first.
    public func tabIDs(ownerTabID: String) -> [String] {
        tabIDsByOwner[ownerTabID] ?? []
    }

    public var ownerTabIDs: [String] {
        Array(tabIDsByOwner.keys)
    }

    @discardableResult
    public func remove(_ tabID: String) -> Bool {
        for (ownerTabID, tabIDs) in tabIDsByOwner where tabIDs.contains(tabID) {
            let remaining = tabIDs.filter { $0 != tabID }
            tabIDsByOwner[ownerTabID] = remaining.isEmpty ? nil : remaining
            return true
        }
        return false
    }

    /// Forgets the chat's tabs and returns them, oldest first, so the caller can close them.
    public func removeAll(ownerTabID: String) -> [String] {
        tabIDsByOwner.removeValue(forKey: ownerTabID) ?? []
    }
}
