//
//  NativeFullScreenChatViewController.swift
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

import AIChat
import Combine
import DuckAINative
import UIKit

/// Demo branch: the full-screen native chat with a UTI as its input, like the contextual sheet.
@MainActor
final class NativeFullScreenChatViewController: UIViewController {
    private let chat: UIViewController
    private let host: AIChatContextualUTIHost
    private let binding: NativeChatInputBinding

    init(session: ChatSession, delegate: NativeChatDelegate) {
        chat = DuckAINative.makeChatViewController(session: session, surface: .fullScreen, showsComposer: false, delegate: delegate)
        host = AIChatContextualUTIHost(originatingURLPublisher: Just(nil).eraseToAnyPublisher(),
                                       initialAttachedContext: nil,
                                       hasActiveChat: { true },
                                       isAutoAttachEnabled: { false },
                                       isCurrentPageAttachable: { false },
                                       isFireTab: false,
                                       start: .collapsedOnExistingChat)
        binding = NativeChatInputBinding(host: host, session: session)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        addChild(chat)
        chat.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chat.view)
        let input = host.mount(in: self)
        NSLayoutConstraint.activate([
            chat.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chat.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chat.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chat.view.bottomAnchor.constraint(equalTo: input.topAnchor)
        ])
        chat.didMove(toParent: self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            binding.unbind()
            host.unmount(from: self)
        }
    }
}
