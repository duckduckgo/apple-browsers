//
//  DuckAINative.swift
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

@_exported import DuckAIChatCore
@_exported import DuckAIChatUI
#if canImport(UIKit)
import SwiftUI
import UIKit

public protocol NativeChatDelegate: AnyObject {
    func nativeChatDidRequestClose()
    func nativeChatDidRequestContinueInWeb(_ context: ChatContext)
}

public enum DuckAINative {

    /// The only entry point the app uses. The chat preloads the model and sends the session's opening when it appears.
    /// Pass `showsComposer: false` when the app's own input drives `session`.
    @MainActor
    public static func makeChatViewController(session: ChatSession,
                                              surface: ChatSurface,
                                              showsComposer: Bool = true,
                                              emptyState: ChatEmptyState? = nil,
                                              delegate: NativeChatDelegate) -> UIViewController {
        let actions = ChatActions(close: { [weak delegate] in delegate?.nativeChatDidRequestClose() },
                                  continueInWeb: { [weak delegate] in delegate?.nativeChatDidRequestContinueInWeb($0) })
        let view = ChatView(session: session, surface: surface, actions: actions, showsComposer: showsComposer,
                            emptyState: emptyState)
        return NativeChatHostingController(session: session, rootView: view)
    }
}

private final class NativeChatHostingController: UIHostingController<ChatView> {
    private let session: ChatSession

    init(session: ChatSession, rootView: ChatView) {
        self.session = session
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        session.open()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent || parent == nil {
            session.close()
        }
    }
}
#endif
