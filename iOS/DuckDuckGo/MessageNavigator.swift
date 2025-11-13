//
//  MessageNavigator.swift
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

import RemoteMessaging
import UIKit
import DDGSync

protocol MessageNavigator {

    func navigateTo(_ target: NavigationTarget, presentationStyle: PresentationContext.Style)

}

protocol MessageNavigationDelegate: AnyObject {

    func segueToSettingsAIChat(openedFromSERPSettingsButton: Bool, presentationStyle: PresentationContext.Style)
    func segueToSettings(presentationStyle: PresentationContext.Style)
    func segueToSettingsAppearance(presentationStyle: PresentationContext.Style)
    func segueToFeedback(presentationStyle: PresentationContext.Style)
    func segueToSettingsSync(with source: String?, pairingInfo: PairingInfo?, presentationStyle: PresentationContext.Style)
    func segueToImportPasswords(presentationStyle: PresentationContext.Style)
}

class DefaultMessageNavigator: MessageNavigator {

    weak var delegate: MessageNavigationDelegate?

    init(delegate: MessageNavigationDelegate?) {
        self.delegate = delegate
    }

    func navigateTo(_ target: NavigationTarget, presentationStyle: PresentationContext.Style) {
        assert(delegate != nil)
        switch target {
        case .duckAISettings:
            delegate?.segueToSettingsAIChat(openedFromSERPSettingsButton: false,
                                            presentationStyle: presentationStyle)
        case .settings:
            delegate?.segueToSettings(presentationStyle: presentationStyle)
        case .feedback:
            delegate?.segueToFeedback(presentationStyle: presentationStyle)
        case .sync:
            delegate?.segueToSettingsSync(with: nil, pairingInfo: nil, presentationStyle: presentationStyle)
        case .importPasswords:
            delegate?.segueToImportPasswords(presentationStyle: presentationStyle)
        case .appearance:
            delegate?.segueToSettingsAppearance(presentationStyle: presentationStyle)

        }
    }

}
