//
//  TokenRecoveryCoordinator.swift
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
import os.log
import Networking

/// Runs the recovery strategies that apply to a recovery trigger, in order, until one succeeds.
public final class TokenRecoveryCoordinator {

    private let invalidTokenStrategies: [TokenRecoveryStrategy]
    private let missingTokenStrategies: [TokenRecoveryStrategy]

    /// - Parameters:
    ///   - invalidTokenStrategies: The strategies tried, in order, when refreshing the current token was rejected.
    ///   - missingTokenStrategies: The strategies tried, in order, when no current token is stored.
    public init(invalidTokenStrategies: [TokenRecoveryStrategy], missingTokenStrategies: [TokenRecoveryStrategy]) {
        self.invalidTokenStrategies = invalidTokenStrategies
        self.missingTokenStrategies = missingTokenStrategies
    }

    /// Tries each strategy for `context.trigger` in order and stops at the first success.
    /// - Parameter context: The state the recovery starts from.
    /// - Returns: The result of each strategy that ran, and the outcome: `.recovered` from the first strategy that recovers;
    ///   `.sessionChanged` as soon as a strategy reports it, without trying the next ones; `.failed` with the error of the last
    ///   strategy that failed; `.deferred` when no strategy failed and one deferred; `.notApplicable` when no strategy applied.
    public func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryReport {
        let strategies = context.trigger == .invalidToken ? invalidTokenStrategies : missingTokenStrategies
        let trigger = context.trigger.rawValue
        var attempts: [TokenRecoveryReport.Attempt] = []
        var lastFailure: Error?
        var deferred = false
        for strategy in strategies {
            let name = String(describing: type(of: strategy))
            let result = await strategy.recover(context)
            attempts.append(TokenRecoveryReport.Attempt(method: strategy.method, result: result))
            switch result {
            case .recovered:
                Logger.subscriptionTokensManagement.log("Token recovered by \(name, privacy: .public), trigger: \(trigger, privacy: .public)")
                return TokenRecoveryReport(result: .recovered, attempts: attempts)
            case .sessionChanged:
                Logger.subscriptionTokensManagement.log("\(name, privacy: .public) stopped the recovery, the session changed, trigger: \(trigger, privacy: .public)")
                return TokenRecoveryReport(result: .sessionChanged, attempts: attempts)
            case .notApplicable:
                Logger.subscriptionTokensManagement.log("\(name, privacy: .public) doesn't apply, trigger: \(trigger, privacy: .public)")
            case .deferred:
                Logger.subscriptionTokensManagement.log("\(name, privacy: .public) deferred, trigger: \(trigger, privacy: .public)")
                deferred = true
            case .failed(let error):
                Logger.subscriptionTokensManagement.error("\(name, privacy: .public) failed, trigger: \(trigger, privacy: .public): \(String(describing: error), privacy: .public)")
                lastFailure = error
            }
        }
        if let lastFailure {
            return TokenRecoveryReport(result: .failed(lastFailure), attempts: attempts)
        }
        if deferred {
            return TokenRecoveryReport(result: .deferred, attempts: attempts)
        }
        Logger.subscriptionTokensManagement.log("No token recovery applies, trigger: \(trigger, privacy: .public)")
        return TokenRecoveryReport(result: .notApplicable, attempts: attempts)
    }
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

    /// Whether nothing can recover the token container: no strategy applied, or every strategy that failed was rejected for good
    /// and none deferred. False when the token was recovered, the session changed, or a failure may not repeat.
    public var isUnrecoverable: Bool {
        switch result {
        case .notApplicable:
            return true
        case .failed:
            return attempts.allSatisfy { attempt in
                switch attempt.result {
                case .notApplicable: true
                case .failed(let error): TokenRecoveryFailure(error) == .permanent
                case .recovered, .deferred, .sessionChanged: false
                }
            }
        case .recovered, .deferred, .sessionChanged:
            return false
        }
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
