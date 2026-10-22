//
//  NativeChatInputBinding.swift
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
import DuckAINative
import Observation

/// Demo branch: makes a UTI drive a native chat session. Every prompt and Stop go to the session, and the input shows
/// the session's status, so it offers Stop while a reply is generating.
@MainActor
final class NativeChatInputBinding {
    let session: ChatSession
    private let host: AIChatContextualUTIHost

    init(host: AIChatContextualUTIHost, session: ChatSession) {
        self.host = host
        self.session = session
        host.setNativeSession(session)
        host.nativeChatPromptSink = { [weak session] prompt, attachments in
            guard let session else { return }
            NativeChatContextFactory.send(prompt, attachments: attachments, to: session)
        }
        host.nativeChatStopHandler = { [weak session] in session?.stop() }
        observeStatus()
    }

    func unbind() {
        host.setNativeSession(nil)
        host.nativeChatPromptSink = nil
        host.nativeChatStopHandler = nil
        host.setNativeChatStatus(.ready)
    }

    private func observeStatus() {
        let status = withObservationTracking {
            session.state.status
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStatus() }
        }
        host.setNativeChatStatus(Self.inputStatus(for: status))
    }

    private static func inputStatus(for status: ChatStatus) -> AIChatStatusValue {
        switch status {
        case .ready: .ready
        case .loading: .loading
        case .streaming: .streaming
        case .error: .error
        }
    }
}
