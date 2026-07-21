//
//  OptOutCommand.swift
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

/// Runs opt-out for one or more extracted profiles from a prior `scan` result, optionally waiting
/// for the email-confirmation link and continuing the opt-out.
struct OptOutCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "optout",
        abstract: "Run opt-out for extracted profile(s) from a scan result JSON.")

    @OptionGroup var rules: RulesSourceOptions
    @OptionGroup var script: ScriptSourceOptions
    @OptionGroup var auth: AuthOptions
    @OptionGroup var runtime: RuntimeOptions
    @OptionGroup var out: OutputOptions

    @Option(name: .long, help: "Path to the profile JSON (the one used for the scan).", completion: .file(extensions: ["json"]))
    var profile: String

    @Option(name: .long, help: "Broker name or domain to opt out of.")
    var broker: String

    @Option(name: .long, help: "Scan result JSON containing extractedProfiles[].", completion: .file(extensions: ["json"]))
    var extracted: String

    @Option(name: .long, help: "Index into the extracted profiles to opt out (0-based).")
    var index: Int?

    @Flag(name: .long, help: "Opt out every extracted profile in the result.")
    var allMatches = false

    @Flag(name: .long, help: "After opt-out, poll for the email-confirmation link and continue the opt-out.")
    var waitForEmail = false

    @Option(name: .long, help: "Seconds between email-confirmation polls (with --wait-for-email).")
    var pollInterval: Double = 15

    var activationPolicy: NSApplication.ActivationPolicy { runtime.showWebview ? .accessory : .prohibited }
    var watchdogTimeout: TimeInterval? { runtime.timeout }

    func execute() async -> Int32 {
        Log.verbose = runtime.verbose
        do {
            let debugProfile = try ProfileLoader.load(path: profile)
            let records = try loadRecords(path: extracted)
            let provider = try rules.makeProvider()
            let scriptSource = try await script.resolve()

            let allBrokers = try await provider.fetchBrokers()
            let matched = try BrokerSelectionOptions.select(selector: broker, all: false, from: allBrokers)
            guard matched.count == 1, let dataBroker = matched.first else {
                throw CLIUsageError("--broker '\(broker)' matched \(matched.count) brokers; be more specific.")
            }
            let brokerId = DebugHelper.stableId(for: dataBroker.with(id: DebugHelper.stableId(for: dataBroker)))

            let selectedRecords = try select(records: records, brokerId: brokerId)
            Log.info("Opting out \(selectedRecords.count) extracted profile(s) from \(dataBroker.name).")

            let configuration = try PIRDebugSessionConfiguration(
                rulesSource: provider,
                authManager: auth.authenticationManager(),
                scriptSource: scriptSource,
                showWebView: runtime.showWebview,
                operationAwaitTime: runtime.awaitTime,
                servicesEndpoint: rules.resolvedServicesEndpoint,
                userAgentApplicationName: "pir-debug")
            let session = try PIRDebugSession(configuration: configuration)

            let eventsWriter = out.makeEventsWriter()
            let eventsTask = eventsWriter.map { writer in
                Task { for await event in session.events { writer.write(event) } }
            }
            defer {
                eventsTask?.cancel()
                eventsWriter?.close()
            }

            var results: [PIROptOutResult] = []
            for record in selectedRecords {
                let singleQueryProfile = try reconstructSingleQueryProfile(for: record, from: debugProfile)
                Log.info("Opt-out: \(record.profileQueryLabel)")
                var result = try await session.optOut(broker: dataBroker,
                                                      profile: singleQueryProfile.toDataBrokerProtectionProfile(),
                                                      extractedProfile: record.extractedProfile)

                if result.awaitingEmailConfirmation, waitForEmail {
                    result = try await waitForEmailAndContinue(session: session, initial: result)
                }
                results.append(result)
            }

            let anyFailed = results.contains { !$0.success && !$0.awaitingEmailConfirmation }
            if results.count == 1, let single = results.first {
                try out.resultWriter.write(single)
            } else {
                try out.resultWriter.write(results)
            }
            return anyFailed ? CLIExit.operationFailed : CLIExit.success
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            Log.error(error.localizedDescription)
            return CLIExit.operationFailed
        }
    }

    // MARK: - Email confirmation

    private func waitForEmailAndContinue(session: PIRDebugSession,
                                         initial: PIROptOutResult) async throws -> PIROptOutResult {
        Log.info("Awaiting email confirmation; polling every \(pollInterval)s (bounded by --timeout)…")
        while true {
            if let url = try await session.checkEmailConfirmation() {
                Log.info("Confirmation link received; continuing opt-out.")
                return try await session.continueOptOut(afterEmailURL: url)
            }
            Log.debug("No confirmation link yet; sleeping \(pollInterval)s.")
            try await Task.sleep(nanoseconds: UInt64(max(0, pollInterval) * 1_000_000_000))
        }
    }

    // MARK: - Record loading / selection

    private func loadRecords(path: String) throws -> [PIRExtractedProfileRecord] {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url) else {
            throw CLIUsageError("Could not read extracted results file: \(url.path)")
        }
        let decoder = JSONDecoder()
        if let single = try? decoder.decode(PIRScanResult.self, from: data) {
            return single.extractedProfiles
        }
        if let many = try? decoder.decode([PIRScanResult].self, from: data) {
            return many.flatMap { $0.extractedProfiles }
        }
        throw CLIUsageError("Could not decode a scan result from \(url.lastPathComponent).")
    }

    private func select(records: [PIRExtractedProfileRecord], brokerId: Int64) throws -> [PIRExtractedProfileRecord] {
        var pool = records.filter { $0.brokerId == brokerId }
        if pool.isEmpty { pool = records } // fall back if the result came from a different id scheme

        guard !pool.isEmpty else {
            throw CLIUsageError("The extracted results contain no profiles.")
        }
        if allMatches {
            return pool
        }
        if let index {
            guard pool.indices.contains(index) else {
                throw CLIUsageError("--index \(index) is out of range (0..<\(pool.count)).")
            }
            return [pool[index]]
        }
        if pool.count == 1 {
            return pool
        }
        throw CLIUsageError("\(pool.count) extracted profiles; select one with --index <n> or opt out all with --all-matches.")
    }

    /// Rebuilds a single-query `DebugProfile` whose profile query matches the extracted record's
    /// label, so a fresh session resolves the correct (single) profile query and the stable IDs line
    /// up for email-confirmation keying.
    private func reconstructSingleQueryProfile(for record: PIRExtractedProfileRecord,
                                               from profile: DebugProfile) throws -> DebugProfile {
        for name in profile.names {
            for address in profile.addresses {
                let label = "\(name.firstName) \(name.lastName) x \(address.city) \(address.state)"
                if label == record.profileQueryLabel {
                    return DebugProfile(names: [name],
                                        addresses: [address],
                                        phones: profile.phones,
                                        birthYear: profile.birthYear)
                }
            }
        }
        if profile.names.count == 1, profile.addresses.count == 1 {
            return profile
        }
        throw CLIUsageError("Profile has no name/address combination matching '\(record.profileQueryLabel)'. Pass the same --profile used for the scan.")
    }
}
