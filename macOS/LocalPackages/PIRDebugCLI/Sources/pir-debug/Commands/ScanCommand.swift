//
//  ScanCommand.swift
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
import DataBrokerProtectionCore
import Foundation
import PIRDebugKit

struct ScanCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Run a scan for the selected broker(s) against a profile.")

    @OptionGroup var rules: RulesSourceOptions
    @OptionGroup var script: ScriptSourceOptions
    @OptionGroup var auth: AuthOptions
    @OptionGroup var runtime: RuntimeOptions
    @OptionGroup var out: OutputOptions
    @OptionGroup var selection: BrokerSelectionOptions

    @Option(name: .long, help: "Path to the profile JSON.", completion: .file(extensions: ["json"]))
    var profile: String

    var activationPolicy: NSApplication.ActivationPolicy { runtime.showWebview ? .accessory : .prohibited }
    var watchdogTimeout: TimeInterval? { runtime.timeout }

    func validateOptions() throws {
        try runtime.checkBounds(checkTimeout: true)
    }

    func execute() async -> Int32 {
        Log.verbose = runtime.verbose
        do {
            let debugProfile = try ProfileLoader.load(path: profile)
            let provider = try rules.makeProvider()
            let scriptSource = try await script.resolve()

            Log.info("Fetching brokers…")
            let allBrokers = try await provider.fetchBrokers()
            let selected = try selection.select(from: allBrokers)
            Log.info("Selected \(selected.count) broker(s).")

            let configuration = try PIRDebugSessionConfiguration(
                rulesSource: provider,
                authManager: auth.authenticationManager(),
                scriptSource: scriptSource,
                showWebView: runtime.showWebview,
                operationAwaitTime: runtime.awaitTime,
                servicesEndpoint: rules.resolvedServicesEndpoint,
                userAgentApplicationName: "pir-debug")
            let session = try PIRDebugSession(configuration: configuration)

            let eventsWriter = try out.makeEventsWriter()
            let eventsTask = eventsWriter.map { writer in
                Task { for await event in session.events { writer.write(event) } }
            }
            defer {
                eventsTask?.cancel()
                eventsWriter?.close()
            }

            let dbpProfile = debugProfile.toDataBrokerProtectionProfile()
            var results: [PIRScanResult] = []
            for broker in selected {
                Log.info("Scanning \(broker.name)…")
                do {
                    let result = try await session.scan(broker: broker, profile: dbpProfile)
                    results.append(result)
                } catch {
                    throw CLIOperationError(String(describing: error))
                }
            }

            let anyError = results.contains { $0.queryStatuses.contains { $0.outcome == .error } }
            if selected.count == 1, let single = results.first {
                try out.resultWriter.write(single)
            } else {
                try out.resultWriter.write(results)
            }
            return anyError ? CLIExit.operationFailed : CLIExit.success
        } catch let error as CLIOperationError {
            Log.error(error.message)
            return CLIExit.operationFailed
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            // Setup / rules-fetch failures (the spec's canonical exit-2 case) reach here.
            Log.error(String(describing: error))
            return CLIExit.usageError
        }
    }
}
