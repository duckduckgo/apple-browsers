//
//  TokenRecoveryStrategy.swift
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

import Foundation
import Networking

/// What made a token recovery necessary.
public enum TokenRecoveryTrigger: String {
    /// Refreshing the current token failed with `OAuthClientError.invalidTokenRequest`.
    case invalidToken = "invalid_token"
    /// No current token is stored.
    case missingToken = "missing_token"
    /// No current token is stored and an account is about to be created.
    case accountCreation = "account_creation"
}

/// The state a token recovery starts from.
public struct TokenRecoveryContext {
    /// What made the recovery necessary.
    public let trigger: TokenRecoveryTrigger
    /// The current token container that failed to refresh. Nil when no current token is stored, or when it couldn't be read.
    public let deadPrimary: TokenContainer?

    /// - Parameters:
    ///   - trigger: What made the recovery necessary.
    ///   - deadPrimary: The current token container that failed to refresh, or nil when none is stored.
    public init(trigger: TokenRecoveryTrigger, deadPrimary: TokenContainer?) {
        self.trigger = trigger
        self.deadPrimary = deadPrimary
    }
}

/// The outcome of a token recovery.
public enum TokenRecoveryResult {
    /// A valid current token container is stored.
    case recovered
    /// The recovery doesn't apply, so nothing was tried.
    case notApplicable
    /// The user signed out, signed in or switched account while the recovery ran. Nothing was stored.
    case sessionChanged
    /// The recovery was tried and failed with the associated error.
    case failed(Error)
}

/// How a token recovery strategy gets the current token container back.
public enum TokenRecoveryMethod: String, Codable, CaseIterable {
    /// Restoring from the backup token container.
    case backup
    /// Restoring the subscription from the last App Store purchase.
    case appStore = "app_store"
}

/// One way of getting a valid current token container back.
public protocol TokenRecoveryStrategy {
    /// How this strategy recovers the token container.
    var method: TokenRecoveryMethod { get }

    /// Attempts the recovery. On success a valid current token container is stored.
    /// - Parameter context: The state the recovery starts from.
    /// - Returns: The outcome of the recovery.
    func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryResult
}

/// What a token recovery did: its outcome and the result of each strategy that ran.
public struct TokenRecoveryReport {

    /// A strategy that ran and its result.
    public struct Attempt {
        /// How the strategy recovers the token container.
        public let method: TokenRecoveryMethod
        /// The strategy's result.
        public let result: TokenRecoveryResult

        public init(method: TokenRecoveryMethod, result: TokenRecoveryResult) {
            self.method = method
            self.result = result
        }
    }

    /// The outcome of the recovery.
    public let result: TokenRecoveryResult
    /// The strategies that ran, in order.
    public let attempts: [Attempt]

    /// - Parameters:
    ///   - result: The outcome of the recovery.
    ///   - attempts: The strategies that ran, in order.
    public init(result: TokenRecoveryResult, attempts: [Attempt]) {
        self.result = result
        self.attempts = attempts
    }

    /// The method of the strategy that recovered the token container, or nil when none did.
    public var recoveredBy: TokenRecoveryMethod? {
        guard case .recovered = result else { return nil }
        return attempts.last?.method
    }

    /// The result of the strategy using `method`.
    /// - Parameter method: The recovery method.
    /// - Returns: The result, or nil when no strategy using `method` ran.
    public func result(of method: TokenRecoveryMethod) -> TokenRecoveryResult? {
        attempts.last { $0.method == method }?.result
    }
}

/// The outcome of the backup restore within a token recovery, as reported on pixels and wide events.
public enum BackupRecoveryOutcome: String, Codable, CaseIterable {
    /// The backup restored the token container.
    case succeeded
    /// No backup restore ran: no backup is stored, backups are off, or no recovery is configured.
    case notAttempted = "not_attempted"
    /// The backup can never restore the session: it belongs to another account, predates the last sign-out or has expired,
    /// or the server rejected it.
    case rejected
    /// The backup restore failed for a temporary or unknown reason.
    case failed
    /// The user signed out, signed in or switched account while the backup restore ran.
    case sessionChanged = "session_changed"
    /// The path reporting it doesn't run a token recovery.
    case notApplicable = "not_applicable"

    /// - Parameter result: The result of the backup strategy, or nil when it didn't run.
    public init(_ result: TokenRecoveryResult?) {
        switch result {
        case .recovered:
            self = .succeeded
        case .notApplicable, nil:
            self = .notAttempted
        case .sessionChanged:
            self = .sessionChanged
        case .failed(let error):
            self = BackupRestoreFailure(error) == .permanent ? .rejected : .failed
        }
    }
}
