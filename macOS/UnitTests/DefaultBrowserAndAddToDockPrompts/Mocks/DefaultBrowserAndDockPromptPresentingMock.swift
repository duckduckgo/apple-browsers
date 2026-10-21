//
//  DefaultBrowserAndDockPromptPresentingMock.swift
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

import AppKit
import Combine
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptPresentingMock: DefaultBrowserAndDockPromptPresenting {
    private let bannerSubject = PassthroughSubject<Void, Never>()
    private let promptDismissedSubject = PassthroughSubject<(DefaultBrowserAndDockPromptPresentationType, PromoResult), Never>()
    private(set) var tryToShowPromptCallCount = 0
    private(set) var allPromptsDismissed = false
    private(set) var dismissedPromptType: DefaultBrowserAndDockPromptPresentationType?

    var bannerDismissedPublisher: AnyPublisher<Void, Never> {
        bannerSubject.eraseToAnyPublisher()
    }

    var promptDismissedPublisher: AnyPublisher<(DefaultBrowserAndDockPromptPresentationType, PromoResult), Never> {
        promptDismissedSubject.eraseToAnyPublisher()
    }

    func dismissPrompt(_ type: DefaultBrowserAndDockPromptPresentationType) async {
        dismissedPromptType = type
    }

    func dismissPrompts() {
        allPromptsDismissed = true
    }

    /// When true, invokes `onNoShow` immediately to simulate the presenter returning early without showing.
    var shouldCallOnNoShow = false

    func tryToShowPrompt(popoverAnchorProvider: @escaping () -> NSView?,
                         bannerViewHandler: @escaping (BannerMessageViewController) -> Void,
                         inactiveUserModalWindowProvider: @escaping () -> NSWindow?,
                         expectedType: DefaultBrowserAndDockPromptPresentationType? = nil,
                         forceShow: Bool = false,
                         onNoShow: (() -> Void)? = nil) {
        tryToShowPromptCallCount += 1
        if shouldCallOnNoShow {
            onNoShow?()
        }
    }
}
