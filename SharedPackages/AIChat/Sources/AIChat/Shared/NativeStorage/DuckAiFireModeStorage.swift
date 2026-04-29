//
//  DuckAiFireModeStorage.swift
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

public enum DuckAiFireModeStorage {
    case notFireMode
    case unavailable
    case available(DuckAiNativeStorageHandling)

    /// Resolves to `.notFireMode` when not in fire mode, `.unavailable` when in fire mode but
    /// `handler` is nil, and `.available(handler)` otherwise. Encapsulates the guard chain
    /// callers would otherwise duplicate.
    public static func resolve(isFireMode: Bool, handler: DuckAiNativeStorageHandling?) -> DuckAiFireModeStorage {
        guard isFireMode else { return .notFireMode }
        guard let handler else { return .unavailable }
        return .available(handler)
    }
}
