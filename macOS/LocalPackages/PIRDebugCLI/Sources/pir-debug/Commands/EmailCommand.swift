//
//  EmailCommand.swift
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

/// Group for the disposable-email commands. These drive the DBP email services directly, without a
/// scan or opt-out run — the equivalent of watching a broker's `generateEmail` / `getEmailData`
/// actions by hand.
struct EmailCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "email",
        abstract: "Drive the DBP disposable-email service directly (generate an address, read its inbox, clear it).",
        discussion: """
        A mailbox is keyed by (email, attempt id), so keep the attemptId that 'generate' reports and \
        pass it to 'inbox'/'delete'. Every subcommand needs a token (--auth-token or the env var).

        Typical loop:
          pir-debug email generate --broker fakebroker.com --wait
          pir-debug email inbox --email <address> --attempt-id <uuid>
          pir-debug email delete --email <address> --attempt-id <uuid>
        """,
        subcommands: [
            EmailGenerateCommand.self,
            EmailInboxCommand.self,
            EmailDeleteCommand.self,
        ])
}

// MARK: - generate

/// `email generate` — asks the v0 service for a fresh disposable address, optionally then waiting
/// for whatever the broker mails to it.
struct EmailGenerateCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate a fresh disposable email address for a broker.")

    @OptionGroup var auth: AuthOptions
    @OptionGroup var email: EmailOptions

    @Option(name: .long, help: "Broker domain sent as the service's dataBroker parameter — the broker JSON's 'url' (e.g. fakebroker.com).")
    var broker: String

    @Option(name: .long, help: "Attempt id to generate under. Default: a fresh UUID.")
    var attemptId: String?

    @Flag(name: .long, help: "After generating, poll the mailbox until it leaves 'pending' (bounded by --timeout).")
    var wait = false

    @Option(name: .long, help: "Seconds between mailbox polls (with --wait).")
    var pollInterval: Double = 15

    var watchdogTimeout: TimeInterval? { email.timeout }

    /// `generate --wait` reports the generated address plus the mailbox read that followed it.
    private struct GeneratedWithInbox: Encodable {
        let dataBroker: String
        let email: String
        let pattern: String?
        let attemptId: String
        let inbox: PIRDebugEmailInboxItem?
    }

    func validateOptions() throws {
        try email.checkBounds()
        _ = try email.resolvedServicesEndpoint()
        guard !broker.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CLIUsageError("--broker must not be empty.")
        }
        if let attemptId {
            _ = try EmailOptions.attemptId(attemptId)
        }
        if wait {
            guard pollInterval > 0 else {
                throw CLIUsageError("--poll-interval must be > 0 (got \(pollInterval)).")
            }
        }
    }

    func execute() async -> Int32 {
        Log.verbose = email.verbose
        do {
            let client = try email.makeClient(auth: auth)
            let requestedAttemptId = try attemptId.map(EmailOptions.attemptId) ?? UUID()

            Log.info("Generating an email address for \(broker) (\(email.endpointDescription))…")
            let generated = try await client.generateEmail(dataBrokerURL: broker, attemptId: requestedAttemptId)
            Log.info("Address: \(generated.email)")
            Log.info("Read it with: pir-debug email inbox --email \(generated.email) --attempt-id \(generated.attemptId)")

            guard wait else {
                try email.resultWriter.write(generated)
                return CLIExit.success
            }

            let mailbox = PIRDebugEmailMailbox(email: generated.email, attemptId: requestedAttemptId)
            let item = try await EmailInboxSupport.waitForInbox(client: client,
                                                               mailbox: mailbox,
                                                               pollInterval: pollInterval)
            try email.resultWriter.write(GeneratedWithInbox(dataBroker: generated.dataBroker,
                                                            email: generated.email,
                                                            pattern: generated.pattern,
                                                            attemptId: generated.attemptId,
                                                            inbox: item))
            return EmailInboxSupport.exitCode(for: item)
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            Log.error(String(describing: error))
            return CLIExit.operationFailed
        }
    }
}

// MARK: - inbox

/// `email inbox` — reads what the v1 email-data service has extracted for a mailbox.
struct EmailInboxCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "Read what the email service extracted for a generated address (status, confirmation link, data).")

    @OptionGroup var auth: AuthOptions
    @OptionGroup var email: EmailOptions

    @Option(name: .customLong("email"), help: "The generated address to read.")
    var address: String

    @Option(name: .long, help: "The attempt id the address was generated under (from 'email generate').")
    var attemptId: String

    @Flag(name: .long, help: "Poll until the mailbox leaves 'pending' (bounded by --timeout).")
    var wait = false

    @Option(name: .long, help: "Seconds between mailbox polls (with --wait).")
    var pollInterval: Double = 15

    var watchdogTimeout: TimeInterval? { email.timeout }

    func validateOptions() throws {
        try email.checkBounds()
        _ = try email.resolvedServicesEndpoint()
        _ = try EmailOptions.attemptId(attemptId)
        if wait {
            guard pollInterval > 0 else {
                throw CLIUsageError("--poll-interval must be > 0 (got \(pollInterval)).")
            }
        }
    }

    func execute() async -> Int32 {
        Log.verbose = email.verbose
        do {
            let client = try email.makeClient(auth: auth)
            let mailbox = PIRDebugEmailMailbox(email: address, attemptId: try EmailOptions.attemptId(attemptId))

            let item: PIRDebugEmailInboxItem?
            if wait {
                item = try await EmailInboxSupport.waitForInbox(client: client,
                                                                mailbox: mailbox,
                                                                pollInterval: pollInterval)
            } else {
                Log.info("Reading the mailbox for \(address) (\(email.endpointDescription))…")
                item = try await EmailInboxSupport.fetchInbox(client: client, mailbox: mailbox)
            }

            guard let item else {
                // A mailbox the service does not know about: no item comes back for the pair at all.
                throw CLIOperationError("The email service returned no data for \(address) / \(attemptId); confirm the address and attempt id came from the same 'email generate'.")
            }
            try email.resultWriter.write(item)
            return EmailInboxSupport.exitCode(for: item)
        } catch let error as CLIOperationError {
            Log.error(error.message)
            return CLIExit.operationFailed
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            Log.error(String(describing: error))
            return CLIExit.operationFailed
        }
    }
}

// MARK: - delete

/// `email delete` — clears the backend's stored data for a mailbox, as the app does once it has
/// consumed a confirmation link.
struct EmailDeleteCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Clear the email service's stored data for a generated address.")

    @OptionGroup var auth: AuthOptions
    @OptionGroup var email: EmailOptions

    @Option(name: .customLong("email"), help: "The generated address whose stored data is cleared.")
    var address: String

    @Option(name: .long, help: "The attempt id the address was generated under (from 'email generate').")
    var attemptId: String

    var watchdogTimeout: TimeInterval? { email.timeout }

    private struct DeleteResult: Encodable {
        let email: String
        let attemptId: String
        let deleted: Bool
    }

    func validateOptions() throws {
        try email.checkBounds()
        _ = try email.resolvedServicesEndpoint()
        _ = try EmailOptions.attemptId(attemptId)
    }

    func execute() async -> Int32 {
        Log.verbose = email.verbose
        do {
            let client = try email.makeClient(auth: auth)
            let mailbox = PIRDebugEmailMailbox(email: address, attemptId: try EmailOptions.attemptId(attemptId))
            Log.info("Deleting stored email data for \(address) (\(email.endpointDescription))…")
            try await client.deleteInbox([mailbox])
            try email.resultWriter.write(DeleteResult(email: address, attemptId: attemptId, deleted: true))
            return CLIExit.success
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            Log.error(String(describing: error))
            return CLIExit.operationFailed
        }
    }
}

// MARK: - Shared inbox handling

enum EmailInboxSupport {

    /// The item for `mailbox`, or `nil` when the service returned nothing for the pair. One mailbox
    /// is requested, so the sole item in the response is this mailbox's state.
    static func fetchInbox(client: PIRDebugEmailClient,
                           mailbox: PIRDebugEmailMailbox) async throws -> PIRDebugEmailInboxItem? {
        try await client.fetchInbox([mailbox]).first
    }

    /// Polls until the mailbox reports something other than `pending`. Unbounded by design: the
    /// `--timeout` watchdog (exit 3) is the bound, matching `optout --wait-for-email`.
    static func waitForInbox(client: PIRDebugEmailClient,
                             mailbox: PIRDebugEmailMailbox,
                             pollInterval: Double) async throws -> PIRDebugEmailInboxItem? {
        Log.info("Polling the mailbox for \(mailbox.email) every \(pollInterval)s (bounded by --timeout)…")
        while true {
            let item = try await fetchInbox(client: client, mailbox: mailbox)
            guard let item, item.status == .pending else {
                if let item {
                    Log.info("Mailbox status: \(item.status.rawValue).")
                }
                return item
            }
            Log.debug("Still pending; sleeping \(pollInterval)s.")
            try await Task.sleep(nanoseconds: UInt64(max(0, pollInterval) * 1_000_000_000))
        }
    }

    /// `ready`/`pending` are both expected states, so they exit 0; the service reporting `error` or
    /// `unknown` for the mailbox is a failure.
    static func exitCode(for item: PIRDebugEmailInboxItem?) -> Int32 {
        guard let item else {
            Log.error("The email service returned no data for this mailbox.")
            return CLIExit.operationFailed
        }
        switch item.status {
        case .ready, .pending:
            return CLIExit.success
        case .error, .unknown:
            let errorCode = item.errorCode.map { " (\($0))" } ?? ""
            Log.error("Email service reported status '\(item.status.rawValue)'\(errorCode).")
            return CLIExit.operationFailed
        }
    }
}
