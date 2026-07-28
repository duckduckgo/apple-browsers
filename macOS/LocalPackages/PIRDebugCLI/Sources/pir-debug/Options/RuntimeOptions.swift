//
//  RuntimeOptions.swift
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

/// Runtime knobs shared by the commands that drive the engine.
struct RuntimeOptions: ParsableArguments {

    @Flag(name: .long, help: "Show the web view window (activation policy .accessory).")
    var showWebview = false

    @Option(name: .long, help: "Seconds to await around every action (fractional ok, must be >= 0).")
    var awaitTime: Double = 1

    @Option(name: .long, help: "Watchdog timeout in seconds; the process exits 3 if exceeded.")
    var timeout: Double = 600

    @Flag(name: .long, help: "Verbose progress logging on stderr.")
    var verbose = false

    @Option(name: .long, help: """
        Web view applicationNameForUserAgent. Default \"safari\" matches the app's Safari-shaped value; \
        brokers behind bot management challenge tool-shaped names. \"tool\" sends \"pir-debug\"; anything \
        else is sent verbatim.
        """)
    var userAgent: String = "safari"

    /// Resolves `--user-agent` to the value handed to the engine. `@MainActor` because the Safari-like
    /// name reads the WebKit version from a `WKWebView`.
    @MainActor
    func resolvedUserAgentApplicationName() -> String {
        switch userAgent {
        case "safari": return PIRDebugUserAgent.safariLike()
        case "tool": return PIRDebugUserAgent.toolLike
        default: return userAgent
        }
    }

    /// Validates the numeric knobs so bad input becomes a clean usage error (exit 2) instead of
    /// trapping later (e.g. `UInt64(negative)` in the watchdog / await-time conversions).
    /// - Parameter checkTimeout: bound `--timeout` too; skipped by `serve`, which ignores it.
    func checkBounds(checkTimeout: Bool) throws {
        guard awaitTime >= 0 else {
            throw CLIUsageError("--await-time must be >= 0 (got \(awaitTime)).")
        }
        if checkTimeout {
            guard timeout > 0, timeout <= 86_400 else {
                throw CLIUsageError("--timeout must be > 0 and <= 86400 seconds (got \(timeout)).")
            }
        }
    }
}
