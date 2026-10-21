//
//  NativeChatPresenter.swift
//  DuckDuckGo
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

import DuckAINative
import UIKit

/// Presents the native chat full screen in place of a new Duck.ai web chat.
@MainActor
final class NativeChatPresenter: NativeChatDelegate {
    private weak var presented: UIViewController?
    private var continueInWeb: (() -> Void)?

    /// Returns false when native mode is off or the request needs the web frontend.
    func present(_ request: AIChatOpeningRequest, from host: UIViewController, continueInWeb: @escaping () -> Void) -> Bool {
        guard DuckAINativeSettings.shared.opensNewChatsNatively,
              let context = NativeChatContextFactory.context(for: request) else { return false }
        present(context, from: host)
        self.continueInWeb = continueInWeb
        return true
    }

    func present(_ context: ChatContext, from host: UIViewController) {
        let session = ChatSession(context: context, provider: NativeChatProviderFactory.makeProvider())
        let chat = DuckAINative.makeChatViewController(session: session, surface: .fullScreen, delegate: self)
        chat.modalPresentationStyle = .fullScreen
        continueInWeb = nil
        presented = chat
        host.present(chat, animated: true)
    }

    func nativeChatDidRequestClose() {
        presented?.dismiss(animated: true)
    }

    func nativeChatDidRequestContinueInWeb(_ context: ChatContext) {
        let continueInWeb = continueInWeb
        presented?.dismiss(animated: true) {
            continueInWeb?()
        }
    }
}
