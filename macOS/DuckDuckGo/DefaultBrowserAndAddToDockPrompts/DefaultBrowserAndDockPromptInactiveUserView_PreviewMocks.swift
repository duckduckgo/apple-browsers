//
//  DefaultBrowserAndDockPromptInactiveUserView_PreviewMocks.swift
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

#if DEBUG
extension DefaultBrowserAndDockPromptInactiveUserViewModel {

    static var setAsDefault: DefaultBrowserAndDockPromptInactiveUserViewModel {
        DefaultBrowserAndDockPromptInactiveUserViewModel(
            message: UserText.setAsDefaultInactiveUserPromptMessage,
            image: .daxSearch,
            primaryButtonLabel: UserText.setAsDefaultInactiveUserPrimaryAction,
            dismissButtonLabel: UserText.setAsDefaultAndAddToDockInactiveUserDismissAction,
            primaryButtonAction: {},
            dismissButtonAction: {}
        )
    }

    static var addToDock: DefaultBrowserAndDockPromptInactiveUserViewModel {
        DefaultBrowserAndDockPromptInactiveUserViewModel(
            message: UserText.addToDockInactiveUserPromptMessage,
            image: .daxSearch,
            primaryButtonLabel: UserText.addToDockInactiveUserPrimaryAction,
            dismissButtonLabel: UserText.setAsDefaultAndAddToDockInactiveUserDismissAction,
            primaryButtonAction: {},
            dismissButtonAction: {}
        )
    }

    static var addToDockAndSetAsDefault: DefaultBrowserAndDockPromptInactiveUserViewModel {
        DefaultBrowserAndDockPromptInactiveUserViewModel(
            message: UserText.bothSetAsDefaultAndAddToDockInactiveUserPromptMessage,
            image: .daxSearch,
            primaryButtonLabel: UserText.bothSetAsDefaultAndAddToDockInactiveUserPrimaryAction,
            dismissButtonLabel: UserText.setAsDefaultAndAddToDockInactiveUserDismissAction,
            primaryButtonAction: {},
            dismissButtonAction: {}
        )
    }
}
#endif
