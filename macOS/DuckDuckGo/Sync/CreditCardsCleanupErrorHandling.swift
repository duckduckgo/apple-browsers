//
//  CreditCardsCleanupErrorHandling.swift
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

import BrowserServicesKit
import Common
import Foundation
import Persistence
import PixelKit

public class CreditCardsCleanupErrorHandling: EventMapping<CreditCardsCleanupError> {

    public init() {
        super.init { event, _, _, _ in
            if event.cleanupError is CreditCardsCleanupCancelledError {
                PixelKit.fire(DebugEvent(GeneralPixel.creditCardsCleanupAttemptedWhileSyncWasEnabled))
            } else {
                let processedErrors = CoreDataErrorsParser.parse(error: event.cleanupError as NSError)
                let params = processedErrors.errorPixelParameters

                PixelKit.fire(DebugEvent(GeneralPixel.creditCardsCleanupError, error: event.cleanupError), withAdditionalParameters: params)
            }
        }
    }

    override init(mapping: @escaping EventMapping<CreditCardsCleanupError>.Mapping) {
        fatalError("Use init()")
    }
}
