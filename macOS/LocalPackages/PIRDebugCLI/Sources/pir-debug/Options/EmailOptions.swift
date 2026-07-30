//
//  EmailOptions.swift
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

/// Knobs shared by the `email` subcommands. They talk to the email service directly, so they need
/// no rules source, no script source and no web view — only an endpoint, a token and an output
/// destination.
struct EmailOptions: ParsableArguments {

    @Option(name: .long, help: "DBP environment whose email service is used.")
    var environment: RulesEnvironment = .staging

    @Option(name: .long, help: "Verbatim services base URL, overriding --environment (e.g. a localhost fake service).")
    var servicesURL: String?

    @Option(name: .long, help: "Write result JSON to this file instead of stdout.")
    var output: String?

    @Option(name: .long, help: "Watchdog timeout in seconds; the process exits 3 if exceeded. Bounds --wait polling.")
    var timeout: Double = 600

    @Flag(name: .long, help: "Verbose progress logging on stderr.")
    var verbose = false

    func resolvedServicesEndpoint() throws -> PIRServicesEndpoint {
        if let servicesURL {
            guard let url = URL(string: servicesURL), url.scheme != nil else {
                throw CLIUsageError("Invalid --services-url: \(servicesURL)")
            }
            return .custom(url)
        }
        switch environment {
        case .staging: return .staging
        case .production: return .production
        }
    }

    /// The endpoint as logged to stderr, so a run always says which service it talked to.
    var endpointDescription: String {
        servicesURL ?? environment.rawValue
    }

    var resultWriter: ResultWriter {
        ResultWriter(outputPath: output)
    }

    func checkBounds() throws {
        guard timeout > 0, timeout <= 86_400 else {
            throw CLIUsageError("--timeout must be > 0 and <= 86400 seconds (got \(timeout)).")
        }
    }

    /// The email service rejects every request without a token, so fail as a usage error up front
    /// rather than as an opaque `noAuthToken` from the service.
    func makeClient(auth: AuthOptions) throws -> PIRDebugEmailClient {
        guard auth.resolvedToken != nil else {
            throw CLIUsageError("The email service needs a token: pass --auth-token or set $\(AuthOptions.envVariableName).")
        }
        return try PIRDebugEmailClient(authManager: auth.authenticationManager(),
                                       servicesEndpoint: try resolvedServicesEndpoint())
    }

    /// Parses an `--attempt-id` value. The services key mailboxes on (email, attemptId), so a typo
    /// here silently reads the wrong mailbox — reject anything that is not a UUID.
    static func attemptId(_ value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw CLIUsageError("--attempt-id must be a UUID as reported by 'email generate' (got '\(value)').")
        }
        return uuid
    }
}
