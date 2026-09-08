//
//  DefaultBrowserPromptManagerDebugPixelHandler.swift
//  DuckDuckGo
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
import PixelKit
import class Common.EventMapping
import class Core.Pixel
import SetDefaultBrowserCore

final class DefaultBrowserPromptManagerDebugPixelHandler: EventMapping<DefaultBrowserManagerDebugEvent>, DefaultBrowserPromptEventMapping {

    public init() {
        super.init { event, error, _, _ in
            switch event {
            case .successfulResult:
                PixelKit.fire(Pixel.Event.debugSetAsDefaultBrowserSuccessfulResult, frequency: .dailyAndCount)
            case .rateLimitReached:
                PixelKit.fire(Pixel.Event.debugSetAsDefaultBrowserMaxNumberOfAttemptsFailure, frequency: .dailyAndCount)
            case .rateLimitReachedNoExistingResultPersisted:
                PixelKit.fire(Pixel.Event.debugSetAsDefaultBrowserMaxNumberOfAttemptsNoExistingResultPersistedFailure, frequency: .dailyAndCount)
            case .unknownError:
                PixelKit.fire(Pixel.Event.debugSetAsDefaultBrowserUnknownFailure.withError(error), frequency: .dailyAndCount)
            }
        }
    }

    @available(*, unavailable, message: "Use init() instead")
    override init(mapping: @escaping EventMapping<DefaultBrowserManagerDebugEvent>.Mapping) {
        fatalError("Use init()")
    }

}
