//
//  ScriptSourceOptions.swift
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

import ArgumentParser
import Foundation
import PIRDebugKit

/// Selects the injected `contentScopeIsolated.js`. Default is the bundled C-S-S resource.
struct ScriptSourceOptions: ParsableArguments {

    @Option(name: .long, help: "Path to a contentScopeIsolated.js file to inject (bypasses the JS cache).", completion: .file())
    var cssScript: String?

    /// Resolves the injected-script source. Throws ``CLIUsageError`` on an invalid combination.
    func resolve() async throws -> InjectedScriptSource {
        if let cssScript {
            let url = URL(fileURLWithPath: (cssScript as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CLIUsageError("Script file does not exist: \(url.path)")
            }
            Log.info("Using injected script: \(url.path)")
            return .file(url)
        }
        return .bundled
    }
}
