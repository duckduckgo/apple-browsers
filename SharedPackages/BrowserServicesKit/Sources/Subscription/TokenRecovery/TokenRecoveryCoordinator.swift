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
    /// - Throws: `TokenBackupError.sessionChanged` as soon as a strategy reports it, without trying the next ones;
    ///   `SubscriptionManagerError.tokenRecoveryNotAttempted` when no strategy applied;
    ///   otherwise the error of the last strategy that applied and failed.
    public func recover(_ context: TokenRecoveryContext) async throws {
        let strategies = context.trigger == .invalidToken ? invalidTokenStrategies : missingTokenStrategies
        let trigger = context.trigger.rawValue
        var lastFailure: Error?
        for strategy in strategies {
            let name = String(describing: type(of: strategy))
            do {
                try await strategy.recover(context)
                Logger.subscriptionTokensManagement.log("Token recovered by \(name, privacy: .public), trigger: \(trigger, privacy: .public)")
                return
            } catch TokenBackupError.sessionChanged {
                Logger.subscriptionTokensManagement.log("\(name, privacy: .public) stopped the recovery, the session changed, trigger: \(trigger, privacy: .public)")
                throw TokenBackupError.sessionChanged
            } catch TokenBackupError.unavailable {
                Logger.subscriptionTokensManagement.log("\(name, privacy: .public) doesn't apply, trigger: \(trigger, privacy: .public)")
                continue
            } catch SubscriptionManagerError.tokenRecoveryNotAttempted {
                Logger.subscriptionTokensManagement.log("\(name, privacy: .public) doesn't apply, trigger: \(trigger, privacy: .public)")
                continue
            } catch {
                Logger.subscriptionTokensManagement.error("\(name, privacy: .public) failed, trigger: \(trigger, privacy: .public): \(String(describing: error), privacy: .public)")
                lastFailure = error
            }
        }
        if lastFailure == nil {
            Logger.subscriptionTokensManagement.log("No token recovery applies, trigger: \(trigger, privacy: .public)")
        }
        throw lastFailure ?? SubscriptionManagerError.tokenRecoveryNotAttempted
    }
}
