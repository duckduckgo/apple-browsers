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
import Common
import SetDefaultBrowserCore

final class DefaultBrowserPromptManagerDebugPixelHandler: EventMapping<DefaultBrowserManagerDebugEvent>, DefaultBrowserPromptEventMapping {

    public init() {
        super.init { event, error, _, _ in
            switch event {
            case .successfulResult:
                Logger.defaultBrowserPrompt.debug("[Default Browser] - Default Browser API Successful Result")
            case .rateLimitReached:
                Logger.defaultBrowserPrompt.debug("[Default Browser] - Default Browser API Rate Limit Reached")
            case .rateLimitReachedNoExistingResultPersisted:
                Logger.defaultBrowserPrompt.debug("[Default Browser] - Default Browser API Rate Limit Reached. No Persisted Result.")
            case .unknownError:
                Logger.defaultBrowserPrompt.debug("[Default Browser] - Default Browser API Unknown Error \(error)")
            }
        }
    }

    @available(*, unavailable, message: "Use init() instead")
    override init(mapping: @escaping EventMapping<DefaultBrowserManagerDebugEvent>.Mapping) {
        fatalError("Use init()")
    }

}
