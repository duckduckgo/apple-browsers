//
//  DefaultBrowserAndDockPromptEventMapper.swift
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

enum DefaultBrowserAndDockPromptEvent {
    case storage(Storage)
}

extension DefaultBrowserAndDockPromptEvent {

    enum Storage {
        case failedToRetrieveValue(Value)
        case failedToSaveValue(Value)
    }

}

extension DefaultBrowserAndDockPromptEvent.Storage {

    enum Value {
        case popoverShownDate(Error)
        case bannerShownDate(Error)
        case permanentlyDismissPrompt(Error)
    }

}

enum DefaultBrowserAndDockPromptEventMapper {

    static let eventHandler = EventMapping<DefaultBrowserAndDockPromptEvent> { event, _, _, _ in
        switch event {
        case let .storage(.failedToRetrieveValue(.popoverShownDate(error))):
            break
        case let .storage(.failedToRetrieveValue(.bannerShownDate(error))):
            break
        case let .storage(.failedToRetrieveValue(.permanentlyDismissPrompt(error))):
            break
        case let .storage(.failedToSaveValue(.popoverShownDate(error))):
            break
        case let .storage(.failedToSaveValue(.bannerShownDate(error))):
            break
        case let .storage(.failedToSaveValue(.permanentlyDismissPrompt(error))):
            break
        }
    }

}
