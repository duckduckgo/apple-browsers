//
//  AuthMigrator.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import PixelKit
import os.log

public class AuthMigrator {
    let oAuthClient: OAuthClient
    let isAuthV2Enabled: Bool

    /// Fired here
    /// - migrationSucceeded
    /// - migrationFailed(Error)
    let pixelHandler: SubscriptionPixelHandling

    public var isReadyToUseAuthV2: Bool {
        switch (isAuthV2Enabled, oAuthClient.isUserAuthenticated) {
        case (true, true):
            return true // AuthV2 FF enabled and the user is already logged in, the migration was completed or the subscription was purchased directly on V2
        case (true, false):
            // AuthV2 enabled but the user is not logged in, this could be:
            if oAuthClient.isV1TokenPresent {
                return false // Migration not performed yet
            } else {
               return true // User without a subscription
            }
        case (false, _):
            return false // AuthV2 FF disabled
        }
    }

    public init(oAuthClient: any OAuthClient,
                pixelHandler: SubscriptionPixelHandling,
                isAuthV2Enabled: Bool) {
        self.oAuthClient = oAuthClient
        self.pixelHandler = pixelHandler
        self.isAuthV2Enabled = isAuthV2Enabled
    }

    public func migrateAuthV1toAuthV2IfNeeded() async {
        guard isAuthV2Enabled else { return }
        do {
            try await oAuthClient.migrateV1Token()
            pixelHandler.handle(pixel: .migrationSucceeded)
            Logger.subscription.log("V1 token migration completed")
        } catch OAuthClientError.authMigrationNotPerformed {
            Logger.subscription.log("V1 token migration not needed")
        } catch OAuthServiceError.authAPIError(let code) where code == OAuthRequest.BodyErrorCode.invalidToken {
            Logger.subscription.error("V1 token invalid during migration, logging out user")
            try? await oAuthClient.logout()
        } catch {
            Logger.subscription.error("Failed to migrate V1 token: \(error, privacy: .public)")
            pixelHandler.handle(pixel: .migrationFailed(error))
        }
    }

}
