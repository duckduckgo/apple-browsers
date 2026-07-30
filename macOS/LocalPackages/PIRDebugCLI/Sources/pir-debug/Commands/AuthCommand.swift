//
//  AuthCommand.swift
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
import Networking
import PIRDebugKit

/// Group for managing the CLI's own subscription token, so opt-out and the `email` commands can run
/// off a real subscription instead of a hand-pasted access token.
struct AuthCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage the stored subscription token (import, status, refresh, logout).",
        discussion: """
        The app keeps its token in the data-protection keychain behind an access group, which an \
        unsigned executable cannot read. So the token is handed over once and kept here instead, at \
        ~/.config/pir-debug/token.json (mode 0600):

          1. In the DuckDuckGo app: log in, then Debug › Privacy Pro › "Export token for pir-debug".
          2. pir-debug auth status

        From then on every command refreshes the access token itself using the stored refresh token, \
        so long runs ('optout --wait-for-email', 'email inbox --wait') do not die when the short-lived \
        access token expires.

        The token is issued by whichever environment the app was logged into: a staging token works \
        with '--environment staging', a production token with '--environment production'.

        NOTE: the file holds a refresh token — a real credential. 'auth logout' deletes it locally \
        (it does not sign the app out).
        """,
        subcommands: [
            AuthStatusCommand.self,
            AuthImportCommand.self,
            AuthRefreshCommand.self,
            AuthLogoutCommand.self,
        ],
        defaultSubcommand: AuthStatusCommand.self)
}

// MARK: - Report

/// What the stored container holds. Deliberately claims only — never the token strings.
struct AuthStatusReport: Encodable {
    let tokenFile: String
    let present: Bool
    /// From the access token's `iss` claim, and the environment implied by it.
    let issuer: String?
    let environment: String?
    let email: String?
    let externalID: String?
    let entitlements: [String]
    let hasPIREntitlement: Bool
    /// Expected to be `true` most of the time: access tokens are short-lived and refreshed on use.
    let accessTokenExpired: Bool
    let accessTokenExpiresAt: String?
    /// The one that matters — once this expires the token must be exported from the app again.
    let refreshTokenExpired: Bool
    let refreshTokenExpiresAt: String?

    /// No token stored yet.
    init(absentAt tokenFile: String) {
        self.tokenFile = tokenFile
        self.present = false
        self.issuer = nil
        self.environment = nil
        self.email = nil
        self.externalID = nil
        self.entitlements = []
        self.hasPIREntitlement = false
        self.accessTokenExpired = true
        self.accessTokenExpiresAt = nil
        self.refreshTokenExpired = true
        self.refreshTokenExpiresAt = nil
    }

    init(container: TokenContainer, tokenFile: String) {
        let issuer = Self.claim("iss", inJWT: container.accessToken)
        self.tokenFile = tokenFile
        self.present = true
        self.issuer = issuer
        self.environment = issuer.flatMap(Self.environmentName(forIssuer:))
        self.email = container.decodedAccessToken.email
        self.externalID = container.decodedAccessToken.externalID
        self.entitlements = container.decodedAccessToken.subscriptionEntitlements.map(\.rawValue).sorted()
        self.hasPIREntitlement = container.decodedAccessToken.hasEntitlement(.dataBrokerProtection)
        self.accessTokenExpired = container.decodedAccessToken.isExpired()
        self.accessTokenExpiresAt = ISO8601DateFormatter().string(from: container.decodedAccessToken.expirationDate)
        self.refreshTokenExpired = container.decodedRefreshToken.isExpired()
        self.refreshTokenExpiresAt = ISO8601DateFormatter().string(from: container.decodedRefreshToken.expirationDate)
    }

    /// A usable token: refreshable and entitled for PIR. Drives the exit code.
    var isUsable: Bool {
        present && !refreshTokenExpired && hasPIREntitlement
    }

    /// The problem to print, or `nil` when usable.
    var problem: String? {
        guard present else { return "No stored token. Run 'pir-debug auth import' (see 'pir-debug auth --help')." }
        if refreshTokenExpired {
            return "The refresh token has expired; export a fresh one from the app."
        }
        if !hasPIREntitlement {
            let list = entitlements.isEmpty ? "none" : entitlements.joined(separator: ", ")
            return "This token has no 'Data Broker Protection' entitlement (has: \(list)); the DBP services will return 401."
        }
        return nil
    }

    /// `JWTAccessToken` does not expose `iss`, so read it from the token's own payload segment.
    /// Payload only — no signature material, and never the token itself.
    private static func claim(_ name: String, inJWT jwt: String) -> String? {
        let segments = jwt.split(separator: ".")
        guard segments.count > 1 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object[name] as? String
    }

    private static func environmentName(forIssuer issuer: String) -> String? {
        guard let host = URL(string: issuer)?.host else { return nil }
        if host == URL(string: "https://quackdev.duckduckgo.com")?.host { return "staging" }
        if host == URL(string: "https://quack.duckduckgo.com")?.host { return "production" }
        return nil
    }
}

// MARK: - status

struct AuthStatusCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Report the stored token's environment, entitlements and expiry. Exits 1 if unusable.")

    @OptionGroup var auth: AuthOptions

    @Option(name: .long, help: "Write result JSON to this file instead of stdout.")
    var output: String?

    /// Offline — no refresh, so no watchdog needed.
    var watchdogTimeout: TimeInterval? { nil }

    func execute() async -> Int32 {
        do {
            let report = try AuthSupport.report(store: auth.tokenStore)
            try ResultWriter(outputPath: output).write(report)
            if let problem = report.problem {
                Log.error(problem)
                return CLIExit.operationFailed
            }
            if report.accessTokenExpired {
                Log.info("Access token is expired; it is refreshed automatically on the next request.")
            }
            return CLIExit.success
        } catch {
            Log.error(String(describing: error))
            return CLIExit.usageError
        }
    }
}

// MARK: - import

struct AuthImportCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Store a token container exported from the app (JSON), then report its status.")

    @OptionGroup var auth: AuthOptions

    @Option(name: .long, help: "Token container JSON to import. Use --stdin to read it from standard input.", completion: .file(extensions: ["json"]))
    var file: String?

    @Flag(name: .long, help: "Read the token container JSON from standard input.")
    var stdin = false

    var watchdogTimeout: TimeInterval? { nil }

    func validateOptions() throws {
        guard file != nil || stdin else {
            throw CLIUsageError("Pass --file <token.json> or --stdin.")
        }
        guard !(file != nil && stdin) else {
            throw CLIUsageError("Pass only one of --file or --stdin.")
        }
    }

    func execute() async -> Int32 {
        do {
            let data = try readInput()
            guard let container = try? JSONDecoder().decode(TokenContainer.self, from: data) else {
                throw CLIUsageError("That is not a token container. Expected the JSON written by the app's \"Export token for pir-debug\" debug item.")
            }
            let store = auth.tokenStore
            try store.saveTokenContainer(container)
            Log.info("Stored token at \(store.url.path) (mode 0600).")

            let report = try AuthSupport.report(store: store)
            try ResultWriter(outputPath: nil).write(report)
            if let problem = report.problem {
                Log.error(problem)
                return CLIExit.operationFailed
            }
            return CLIExit.success
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            Log.error(String(describing: error))
            return CLIExit.usageError
        }
    }

    private func readInput() throws -> Data {
        if let file {
            let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
            guard let data = try? Data(contentsOf: url) else {
                throw CLIUsageError("Could not read \(url.path).")
            }
            return data
        }
        guard let data = try FileHandle.standardInput.readToEnd(), !data.isEmpty else {
            throw CLIUsageError("No token container on standard input.")
        }
        return data
    }
}

// MARK: - refresh

struct AuthRefreshCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "refresh",
        abstract: "Force a token refresh now (proves the stored refresh token still works).")

    @OptionGroup var auth: AuthOptions

    @Option(name: .long, help: "Auth environment to refresh against. Must match the token's issuer (see 'auth status').")
    var environment: RulesEnvironment = .staging

    @Option(name: .long, help: "Watchdog timeout in seconds; the process exits 3 if exceeded.")
    var timeout: Double = 60

    var watchdogTimeout: TimeInterval? { timeout }

    func validateOptions() throws {
        guard timeout > 0, timeout <= 86_400 else {
            throw CLIUsageError("--timeout must be > 0 and <= 86400 seconds (got \(timeout)).")
        }
    }

    func execute() async -> Int32 {
        do {
            let store = auth.tokenStore
            guard store.hasToken else {
                throw CLIUsageError("No stored token to refresh. Run 'pir-debug auth import' first.")
            }
            let manager = PIRDebugSubscriptionAuthManager(
                store: store,
                environment: environment == .staging ? .staging : .production)
            Log.info("Refreshing against \(environment.rawValue) auth…")
            guard await manager.accessToken() != nil else {
                throw CLIOperationError("Refresh failed. The refresh token may be expired, reused or revoked, or --environment may not match the token's issuer (see 'auth status').")
            }
            Log.info("Refresh succeeded; stored token updated.")
            try ResultWriter(outputPath: nil).write(try AuthSupport.report(store: store))
            return CLIExit.success
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

// MARK: - logout

struct AuthLogoutCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "logout",
        abstract: "Delete the stored token file. Local only — the app stays signed in.")

    @OptionGroup var auth: AuthOptions

    var watchdogTimeout: TimeInterval? { nil }

    private struct LogoutResult: Encodable {
        let tokenFile: String
        let deleted: Bool
    }

    func execute() async -> Int32 {
        let store = auth.tokenStore
        let existed = store.hasToken
        do {
            // Deletes locally only: the refresh token is the app's too, so invalidating it
            // server-side would sign the app out as a side effect of a debug-tool cleanup.
            try store.saveTokenContainer(nil)
            try ResultWriter(outputPath: nil).write(LogoutResult(tokenFile: store.url.path, deleted: existed))
            return CLIExit.success
        } catch {
            Log.error(String(describing: error))
            return CLIExit.operationFailed
        }
    }
}

// MARK: - Shared

enum AuthSupport {

    static func report(store: PIRDebugTokenStore) throws -> AuthStatusReport {
        guard let container = try store.getTokenContainer() else {
            return AuthStatusReport(absentAt: store.url.path)
        }
        return AuthStatusReport(container: container, tokenFile: store.url.path)
    }
}
