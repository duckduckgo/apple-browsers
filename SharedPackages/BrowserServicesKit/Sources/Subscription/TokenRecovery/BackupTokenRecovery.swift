//
//  BackupTokenRecovery.swift
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

/// Recovers the current token container from the backup token container.
public struct BackupTokenRecovery: TokenRecoveryStrategy {

    private let oAuthClient: any OAuthClient
    private let onRestored: (TokenRecoveryTrigger) -> Void

    /// - Parameters:
    ///   - oAuthClient: The client that holds the backup and stores the restored token container.
    ///   - onRestored: Called with the recovery trigger after each successful restore.
    public init(oAuthClient: any OAuthClient, onRestored: @escaping (TokenRecoveryTrigger) -> Void) {
        self.oAuthClient = oAuthClient
        self.onRestored = onRestored
    }

    /// Restores from the backup. The backup must belong to the dead current token's account, when there is one,
    /// and its refresh token must have been issued after the cut-off recorded at the last explicit sign-out.
    public func recover(_ context: TokenRecoveryContext) async throws {
        _ = try await oAuthClient.restoreFromBackup(expectedExternalID: context.deadPrimary?.decodedAccessToken.externalID,
                                                    issuedAfter: context.signOutCutoff)
        Logger.subscriptionTokensManagement.log("Token restored from backup, trigger: \(context.trigger.rawValue, privacy: .public)")
        onRestored(context.trigger)
    }
}
