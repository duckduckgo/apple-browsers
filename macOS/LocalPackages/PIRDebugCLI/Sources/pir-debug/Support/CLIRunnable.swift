//
//  CLIRunnable.swift
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

import AppKit
import ArgumentParser
import Foundation

/// A `pir-debug` subcommand that runs inside the `NSApplication` run loop. `execute()` performs the
/// work and returns the process exit code; the bootstrap calls `exit(code)` when it returns.
protocol CLIRunnable: ParsableCommand {
    /// Activation policy for the run. `.prohibited` headless; `.accessory` when a web view is shown.
    var activationPolicy: NSApplication.ActivationPolicy { get }
    /// Watchdog timeout in seconds; `nil` disables the watchdog (used by the long-running `serve`).
    var watchdogTimeout: TimeInterval? { get }
    /// Validates option bounds before the watchdog is armed and the engine runs. Default: no-op.
    func validateOptions() throws
    func execute() async -> Int32
}

extension CLIRunnable {
    var activationPolicy: NSApplication.ActivationPolicy { .prohibited }
    var watchdogTimeout: TimeInterval? { 600 }
    func validateOptions() throws {}
}

/// Runs a parsed command on a `@MainActor` task from `applicationDidFinishLaunching`, arms the
/// `--timeout` watchdog, and calls `exit(code)` when the command finishes.
final class CLIAppDelegate: NSObject, NSApplicationDelegate {

    private let command: CLIRunnable

    init(command: CLIRunnable) {
        self.command = command
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let timeout = command.watchdogTimeout {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                Log.error("Timed out after \(timeout)s")
                exit(CLIExit.timeout)
            }
        }
        Task { @MainActor in
            let code = await command.execute()
            exit(code)
        }
    }
}

/// Boots `NSApplication` per the proven spike recipe and runs `command` to completion.
func runInApplication(_ command: CLIRunnable) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(command.activationPolicy)
    let delegate = CLIAppDelegate(command: command)
    app.delegate = delegate
    app.run()
    exit(CLIExit.success) // unreachable: the delegate always calls exit()
}
