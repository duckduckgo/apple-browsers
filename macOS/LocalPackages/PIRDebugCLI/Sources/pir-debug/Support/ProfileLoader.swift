//
//  ProfileLoader.swift
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
import PIRDebugKit

enum ProfileLoader {

    /// Loads a ``DebugProfile`` from a JSON file. Throws ``CLIUsageError`` if it cannot be read or
    /// decoded — a configuration problem, exit code 2.
    static func load(path: String) throws -> DebugProfile {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url) else {
            throw CLIUsageError("Could not read profile file: \(url.path)")
        }
        do {
            return try JSONDecoder().decode(DebugProfile.self, from: data)
        } catch {
            throw CLIUsageError("Could not decode profile \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
