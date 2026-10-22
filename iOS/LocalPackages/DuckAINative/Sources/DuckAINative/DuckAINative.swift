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
import Observation
import UIKit

public protocol NativeChatDelegate: AnyObject {
    func nativeChatDidRequestClose()
    func nativeChatDidRequestContinueInWeb(_ context: ChatContext)
}

public enum DuckAINative {
    @MainActor
    public static func makeChatViewController(session: ChatSession,
                                              surface: ChatSurface,
                                              emptyState: ChatEmptyState? = nil,
                                              delegate: NativeChatDelegate) -> UIViewController {
        let actions = ChatActions(close: { [weak delegate] in delegate?.nativeChatDidRequestClose() },
                                  continueInWeb: { [weak delegate] in delegate?.nativeChatDidRequestContinueInWeb($0) },
                                  redo: { session.redo() }, download: { session.download() })
        let name = session.descriptor.modelName.isEmpty ? session.descriptor.displayName : session.descriptor.modelName
        let transcript = ChatViewController(surface: surface, metadata: ChatDisplayMetadata(title: name),
                                            emptyState: emptyState, actions: actions)
        return NativeChatSessionController(session: session, transcript: transcript)
    }
}

private final class NativeChatSessionController: UIViewController {
    private let session: ChatSession
    private let transcript: ChatViewController

    init(session: ChatSession, transcript: ChatViewController) {
        self.session = session
        self.transcript = transcript
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(transcript)
        view.addSubview(transcript.view)
        transcript.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            transcript.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transcript.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transcript.view.topAnchor.constraint(equalTo: view.topAnchor),
            transcript.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        transcript.didMove(toParent: self)
        observeSession()
    }

    private func observeSession() {
        withObservationTracking {
            transcript.apply(snapshot: session.state)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeSession() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        session.open()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent || parent == nil { session.close() }
    }
}
#endif
