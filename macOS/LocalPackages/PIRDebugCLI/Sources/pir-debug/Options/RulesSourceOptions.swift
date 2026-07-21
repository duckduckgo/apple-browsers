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

/// The DBP environment: base for remote rules fetch and for the email/captcha services endpoint.
enum RulesEnvironment: String, ExpressibleByArgument {
    case staging
    case production
}

/// Selects the broker rules source. At most one explicit source may be given; with none, rules are
/// fetched remotely from `--environment`. `--environment` also selects the services endpoint.
struct RulesSourceOptions: ParsableArguments {

    @Option(name: .long, help: "Directory of broker JSON files (e.g. a dbp-api checkout's dbp-json/data/json/).", completion: .directory)
    var rulesDir: String?

    @Option(name: .long, help: "A single broker JSON file.", completion: .file(extensions: ["json"]))
    var brokerFile: String?

    @Option(name: .long, help: "Fetch rules from a dbp-api staging branch deploy (branch name is sanitized: lowercase, [a-z0-9.-]).")
    var dbpApiBranch: String?

    @Option(name: .long, help: "Fetch rules from a verbatim dbp-api base URL.")
    var dbpApiURL: String?

    @Option(name: .long, help: "DBP environment for remote rules fetch and email/captcha services.")
    var environment: RulesEnvironment = .staging

    /// The email/captcha services endpoint, always derived from `--environment`.
    var resolvedServicesEndpoint: PIRServicesEndpoint {
        switch environment {
        case .staging: return .staging
        case .production: return .production
        }
    }

    /// Builds the `BrokerRulesProviding` for the selected source. Throws ``CLIUsageError`` when more
    /// than one explicit source is given.
    func makeProvider() throws -> BrokerRulesProviding {
        let explicit = [rulesDir, brokerFile, dbpApiBranch, dbpApiURL].compactMap { $0 }
        guard explicit.count <= 1 else {
            throw CLIUsageError("Specify only one rules source (--rules-dir, --broker-file, --dbp-api-branch, or --dbp-api-url).")
        }

        if let rulesDir {
            return try localProvider(path: rulesDir)
        }
        if let brokerFile {
            return try localProvider(path: brokerFile)
        }
        if let dbpApiBranch {
            Log.info("Fetching rules from dbp-api branch: \(PIRDebugBranchNameSanitizer.sanitize(dbpApiBranch))")
            return RemoteBrokerRulesProvider(endpoint: .stagingBranch(dbpApiBranch))
        }
        if let dbpApiURL {
            guard let url = URL(string: dbpApiURL), url.scheme != nil else {
                throw CLIUsageError("Invalid --dbp-api-url: \(dbpApiURL)")
            }
            Log.info("Fetching rules from custom dbp-api URL: \(url.absoluteString)")
            return RemoteBrokerRulesProvider(endpoint: .custom(url))
        }
        Log.info("Fetching rules from \(environment.rawValue) environment.")
        return RemoteBrokerRulesProvider(endpoint: environment == .staging ? .staging : .production)
    }

    /// The remote endpoint for `fetch-rules`. Throws ``CLIUsageError`` for local sources or when
    /// more than one remote source is given.
    func makeRemoteEndpoint() throws -> RemoteBrokerEndpoint {
        if rulesDir != nil || brokerFile != nil {
            throw CLIUsageError("fetch-rules needs a remote source; --rules-dir/--broker-file are local. Use --dbp-api-branch, --dbp-api-url, or --environment.")
        }
        guard [dbpApiBranch, dbpApiURL].compactMap({ $0 }).count <= 1 else {
            throw CLIUsageError("Specify only one remote source (--dbp-api-branch or --dbp-api-url).")
        }
        if let dbpApiBranch {
            return .stagingBranch(dbpApiBranch)
        }
        if let dbpApiURL {
            guard let url = URL(string: dbpApiURL), url.scheme != nil else {
                throw CLIUsageError("Invalid --dbp-api-url: \(dbpApiURL)")
            }
            return .custom(url)
        }
        return environment == .staging ? .staging : .production
    }

    private func localProvider(path: String) throws -> BrokerRulesProviding {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIUsageError("Rules source does not exist: \(url.path)")
        }
        return LocalFileBrokerRulesProvider(url: url)
    }
}
