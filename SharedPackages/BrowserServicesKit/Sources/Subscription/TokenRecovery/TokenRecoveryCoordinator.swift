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
    ///   - missingTokenStrategies: The strategies tried, in order, when no current token is stored, including before an account is created.
    public init(invalidTokenStrategies: [TokenRecoveryStrategy], missingTokenStrategies: [TokenRecoveryStrategy]) {
        self.invalidTokenStrategies = invalidTokenStrategies
        self.missingTokenStrategies = missingTokenStrategies
    }

    /// Tries each strategy for `context.trigger` in order and stops at the first success.
    /// - Parameter context: The state the recovery starts from.
    /// - Returns: The result of each strategy that ran, and the outcome: `.recovered` from the first strategy that recovers;
    ///   `.sessionChanged` as soon as a strategy reports it, without trying the next ones; `.failed` with the error of the last
    ///   strategy that failed; `.notApplicable` when no strategy applied.
    public func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryReport {
        let strategies = context.trigger == .invalidToken ? invalidTokenStrategies : missingTokenStrategies
        let trigger = context.trigger.rawValue
        var attempts: [TokenRecoveryReport.Attempt] = []
        var lastFailure: Error?
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
            case .failed(let error):
                Logger.subscriptionTokensManagement.error("\(name, privacy: .public) failed, trigger: \(trigger, privacy: .public): \(String(describing: error), privacy: .public)")
                lastFailure = error
            }
        }
        if let lastFailure {
            return TokenRecoveryReport(result: .failed(lastFailure), attempts: attempts)
        }
        Logger.subscriptionTokensManagement.log("No token recovery applies, trigger: \(trigger, privacy: .public)")
        return TokenRecoveryReport(result: .notApplicable, attempts: attempts)
    }
}
