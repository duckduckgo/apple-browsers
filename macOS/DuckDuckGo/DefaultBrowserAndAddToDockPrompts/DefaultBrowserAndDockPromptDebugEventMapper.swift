//
//  DefaultBrowserAndDockPromptDebugEventMapper.swift
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
import PixelKit

enum DefaultBrowserAndDockPromptDebugEvent {
    case storage(Storage)
}

extension DefaultBrowserAndDockPromptDebugEvent {

    enum Storage {
        case failedToRetrieveValue(Value)
        case failedToSaveValue(Value)
    }

}

extension DefaultBrowserAndDockPromptDebugEvent.Storage {

    enum Value {
        case popoverShownDate(Error)
        case bannerShownDate(Error)
        case bannerShownOccurrences(Error)
        case permanentlyDismissPrompt(Error)
    }

}

enum DefaultBrowserAndDockPromptDebugEventMapper {

    static let eventHandler = EventMapping<DefaultBrowserAndDockPromptDebugEvent> { event, _, _, _ in
        let debugEvent: DebugEvent
        switch event {
        case let .storage(.failedToRetrieveValue(.popoverShownDate(error))):
            debugEvent = DebugEvent(DefaultBrowserAndDockPromptDebugPixelEvent.failedToRetrievePopoverSeenDate, error: error)
        case let .storage(.failedToRetrieveValue(.bannerShownDate(error))):
            debugEvent = DebugEvent(DefaultBrowserAndDockPromptDebugPixelEvent.failedToRetrieveBannerSeenDate, error: error)
        case let .storage(.failedToRetrieveValue(.bannerShownOccurrences(error))):
            debugEvent = DebugEvent(DefaultBrowserAndDockPromptDebugPixelEvent.failedToRetrieveNumberOfBannerShown, error: error)
        case let .storage(.failedToSaveValue(.bannerShownOccurrences(error))):
            debugEvent = DebugEvent(DefaultBrowserAndDockPromptDebugPixelEvent.failedToSaveNumberOfBannerShown, error: error)
        case let .storage(.failedToRetrieveValue(.permanentlyDismissPrompt(error))):
            debugEvent = DebugEvent(DefaultBrowserAndDockPromptDebugPixelEvent.failedToRetrieveBannerPermanentlyDismissedValue, error: error)
        case let .storage(.failedToSaveValue(.popoverShownDate(error))):
            debugEvent = DebugEvent(DefaultBrowserAndDockPromptDebugPixelEvent.failedToSavePopoverSeenDate, error: error)
        case let .storage(.failedToSaveValue(.bannerShownDate(error))):
            debugEvent = DebugEvent(DefaultBrowserAndDockPromptDebugPixelEvent.failedToSaveBannerSeenDate, error: error)
        case let .storage(.failedToSaveValue(.permanentlyDismissPrompt(error))):
            debugEvent = DebugEvent(DefaultBrowserAndDockPromptDebugPixelEvent.failedToSaveBannerPermanentlyDismissedValue, error: error)
        }
        PixelKit.fire(debugEvent, frequency: .dailyAndCount)
    }

}
