//
//  AIChatBonusStateProviding.swift
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

/// Read-only state of the bonus offer, for targeting such as the RMF `isAIChatBoostActive` rule.
public protocol AIChatBonusStateProviding {
    /// Whether the install has a boost that hasn't expired.
    ///
    /// - Parameter date: The moment to check against.
    /// - Returns: `true` if the install has a boost that hasn't expired, `false` if it has none, including no record.
    /// - Throws: When the record can't be read.
    func isBoostActive(at date: Date) throws -> Bool
}

public extension AIChatBonusStateProviding {
    /// Whether the install has a boost that hasn't expired now.
    func isBoostActive() throws -> Bool {
        try isBoostActive(at: Date())
    }
}
