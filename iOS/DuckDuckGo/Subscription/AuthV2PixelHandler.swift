//
//  AuthV2PixelHandler.swift
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
import Subscription
import Core

public struct AuthV2PixelHandler: SubscriptionPixelHandler {

    public enum Source {
        case mainApp
        case systemExtension
        
        var description: String {
            switch self {
            case .mainApp:
                return "MainApp"
            case .systemExtension:
                return "SysExt"
            }
        }
    }

    let source: Source

    public func handle(pixelType: Subscription.SubscriptionPixelType) {
        let sourceParam = ["source": source.description]
        switch pixelType {
        case .invalidRefreshToken:
            DailyPixel.fireDailyAndCount(pixel: .privacyProInvalidRefreshTokenDetected, withAdditionalParameters: sourceParam)
        case .subscriptionIsActive:
            DailyPixel.fire(pixel: .privacyProSubscriptionActive)
        case .migrationStarted:
            DailyPixel.fireDailyAndCount(pixel: .privacyProAuthV2MigrationStarted, withAdditionalParameters: sourceParam)
        case .migrationFailed(let error):
            DailyPixel.fireDailyAndCount(pixel: .privacyProAuthV2MigrationFailed, withAdditionalParameters: ["error": error.localizedDescription].merging(sourceParam){ $1 } )
        case .migrationSucceeded:
            DailyPixel.fireDailyAndCount(pixel: .privacyProAuthV2MigrationSucceeded, withAdditionalParameters: sourceParam)
        case .getTokensError(let policy, let error):
            DailyPixel.fireDailyAndCount(pixel: .privacyProAuthV2GetTokensError, withAdditionalParameters: ["error": error.localizedDescription,
                                                                                                            "policycache": policy.description].merging(sourceParam){ $1 } )
        }
    }

}
