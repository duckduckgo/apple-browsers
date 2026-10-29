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

/// One way of getting a valid current token container back.
public protocol TokenRecoveryStrategy {
    /// Attempts the recovery. On success a valid current token container is stored.
    /// - Parameter context: The state the recovery starts from.
    /// - Returns: The outcome of the recovery.
    func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryResult
}
