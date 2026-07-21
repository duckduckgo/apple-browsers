//
//  RulesSourceOptions.swift
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

/// Selects the broker rules source. Exactly one source must be resolvable. `--environment` also
/// selects the email/captcha services endpoint.
struct RulesSourceOptions: ParsableArguments {

    @Option(name: .long, help: "Directory of broker JSON files (e.g. a dbp-api checkout's dbp-json/data/json/).", completion: .directory)
    var rulesDir: String?

    @Option(name: .long, help: "A single broker JSON file.", completion: .file(extensions: ["json"]))
    var brokerFile: String?

    var resolvedServicesEndpoint: PIRServicesEndpoint {
        .staging
    }

    /// Builds the `BrokerRulesProviding` for the selected source. Throws ``CLIUsageError`` when the
    /// combination is invalid.
    func makeProvider() throws -> BrokerRulesProviding {
        let localSources = [rulesDir, brokerFile].compactMap { $0 }
        guard localSources.count <= 1 else {
            throw CLIUsageError("Specify only one rules source (--rules-dir or --broker-file).")
        }

        if let rulesDir {
            return try localProvider(path: rulesDir)
        }
        if let brokerFile {
            return try localProvider(path: brokerFile)
        }
        throw CLIUsageError("A rules source is required: --rules-dir or --broker-file.")
    }

    private func localProvider(path: String) throws -> BrokerRulesProviding {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIUsageError("Rules source does not exist: \(url.path)")
        }
        return LocalFileBrokerRulesProvider(url: url)
    }
}
