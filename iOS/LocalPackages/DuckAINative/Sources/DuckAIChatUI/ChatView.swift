//
//  ChatView.swift
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

#if canImport(UIKit)
import DuckAIChatCore
import UIKit

public enum ChatSurface: Sendable {
    case contextualSheet
    case fullScreen
    case tab
}

public struct ChatEmptyState {
    public var image: UIImage
    public var title: String

    public init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }
}

/// Display metadata belongs to the host, independently of the provider transport.
public struct ChatDisplayMetadata {
    public var title: String
    public var subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
}

public struct ChatActions {
    public var close: () -> Void
    public var continueInWeb: (ChatContext) -> Void
    public var redo: () -> Void
    public var download: () -> Void

    public init(close: @escaping () -> Void, continueInWeb: @escaping (ChatContext) -> Void,
                redo: @escaping () -> Void, download: @escaping () -> Void) {
        self.close = close
        self.continueInWeb = continueInWeb
        self.redo = redo
        self.download = download
    }
}

/// A transcript renderer. The host supplies state; this controller never loads a model or sends a request.
public final class ChatViewController: UIViewController, UIScrollViewDelegate {
    private let surface: ChatSurface
    private let metadata: ChatDisplayMetadata
    private let emptyState: ChatEmptyState?
    private let actions: ChatActions
    private let scrollView = UIScrollView()
    private let transcript = UIStackView()
    private let status = UIStackView()
    private var welcome: UIView?
    private var state: ChatState?
    private var pendingState: ChatState?
    private var rows: [MessageID: UIView] = [:]
    private var replies: [MessageID: ReplyPresentation] = [:]
    private var followsBottom = true
    private var lastUserID: MessageID?
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval = 0

    public init(surface: ChatSurface, metadata: ChatDisplayMetadata, emptyState: ChatEmptyState? = nil, actions: ChatActions) {
        self.surface = surface
        self.metadata = metadata
        self.emptyState = emptyState
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DuckAIChatTokens.Color.pageBackground
        scrollView.delegate = self
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "NativeChat.Transcript"
        let layout = UIStackView()
        layout.axis = .vertical
        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: view.leadingAnchor), layout.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layout.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), layout.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if surface == .fullScreen {
            let header = UIStackView(arrangedSubviews: [chatButton("Close", symbol: "xmark", action: actions.close), chatLabel("Duck.ai")])
            header.spacing = 12
            layout.addArrangedSubview(header)
        }
        layout.addArrangedSubview(scrollView)
        transcript.axis = .vertical
        transcript.spacing = 12
        transcript.isLayoutMarginsRelativeArrangement = true
        transcript.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 57, right: 12)
        transcript.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(transcript)
        NSLayoutConstraint.activate([
            transcript.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            transcript.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            transcript.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            transcript.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            transcript.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        status.axis = .vertical
        status.spacing = 8
        status.isLayoutMarginsRelativeArrangement = true
        status.layoutMargins = UIEdgeInsets(top: 4, left: 12, bottom: 0, right: 12)
        transcript.addArrangedSubview(status)
    }

    public func apply(snapshot: ChatState) {
        guard snapshot != pendingState, snapshot != state else { return }
        pendingState = snapshot
        loadViewIfNeeded()
        if view.window == nil {
            consumePendingState(settle: true)
            renderReplies()
        } else {
            startClock()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startClock()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = 0
        consumePendingState(settle: true)
        for id in Array(replies.keys) { replies[id]?.flush() }
        renderReplies()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        followBottom()
    }

    private func startClock() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: ChatDisplayLinkTarget(controller: self), selector: #selector(ChatDisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let elapsed = previousTimestamp == 0 ? 1.0 / 60 : link.timestamp - previousTimestamp
        previousTimestamp = link.timestamp
        consumePendingState(settle: UIAccessibility.isReduceMotionEnabled)
        for id in Array(replies.keys) { replies[id]?.advance(by: elapsed) }
        renderReplies()
        view.layoutIfNeeded()
        followBottom()
        if pendingState == nil && !replies.values.contains(where: \.needsFrame) {
            displayLink?.invalidate()
            displayLink = nil
            previousTimestamp = 0
        }
    }

    private func consumePendingState(settle: Bool) {
        guard let snapshot = pendingState else { return }
        pendingState = nil
        state = snapshot
        let userID = snapshot.messages.last { if case .user = $0 { true } else { false } }?.id
        if userID != lastUserID { followsBottom = true; lastUserID = userID }
        var ids = snapshot.messages.map(\.id)
        if let live = snapshot.liveReply { ids.append(live.id) }
        for id in Array(rows.keys) where !ids.contains(id) {
            rows.removeValue(forKey: id)?.removeFromSuperview()
            replies.removeValue(forKey: id)
        }
        for message in snapshot.messages {
            switch message {
            case .user(let user):
                if rows[user.id] == nil { insert(UserMessageView(message: user), id: user.id) }
            case .assistant(let reply):
                receive(AssistantReplySnapshot(id: reply.id, parts: reply.parts, phase: .ended(reply.ending)),
                        settle: settle || reply.id != ids.last)
            }
        }
        if let live = snapshot.liveReply {
            receive(AssistantReplySnapshot(id: live.id, parts: live.parts, phase: .receiving(live.stage)), settle: settle)
        }
        updateStatus(snapshot)
        updateWelcome(isEmpty: ids.isEmpty)
    }

    private func insert(_ row: UIView, id: MessageID) {
        rows[id] = row
        transcript.insertArrangedSubview(row, at: max(0, transcript.arrangedSubviews.count - 1))
    }

    private func receive(_ reply: AssistantReplySnapshot, settle: Bool) {
        if replies[reply.id] == nil {
            replies[reply.id] = ReplyPresentation(reply)
            insert(AssistantMessageView(), id: reply.id)
        }
        replies[reply.id]?.receive(reply, settle: settle)
    }

    private func renderReplies() {
        guard let state else { return }
        let latest = state.liveReply?.id ?? state.messages.last?.id
        for (id, reply) in replies {
            (rows[id] as? AssistantMessageView)?.apply(reply.rendered, metadata: metadata, latest: id == latest,
                                                     canRedo: state.canRedo, actions: actions, context: state.context)
        }
    }

    private func updateWelcome(isEmpty: Bool) {
        if isEmpty, welcome != nil { return }
        welcome?.removeFromSuperview()
        welcome = nil
        guard isEmpty, let emptyState else { return }
        let image = UIImageView(image: emptyState.image)
        image.contentMode = .scaleAspectFit
        image.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let stack = UIStackView(arrangedSubviews: [image, chatLabel(emptyState.title, style: ChatTypography.h3)])
        stack.axis = .vertical
        stack.spacing = 12
        if let subtitle = metadata.subtitle { stack.addArrangedSubview(chatLabel(subtitle, style: ChatTypography.subtitle)) }
        stack.accessibilityIdentifier = "NativeChat.Welcome"
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
        welcome = stack
    }

    private func followBottom() {
        guard followsBottom, !scrollView.isDragging, !scrollView.isDecelerating else { return }
        let bottom = max(-scrollView.adjustedContentInset.top,
                         scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        if abs(scrollView.contentOffset.y - bottom) > 0.5 { scrollView.contentOffset.y = bottom }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { followsBottom = false }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        let distance = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
            + scrollView.adjustedContentInset.bottom
        followsBottom = distance < 24
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { followBottom() }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { followBottom() }

    private func updateStatus(_ state: ChatState) {
        status.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if case .error(let error) = state.status {
            status.addArrangedSubview(chatLabel(error.chatDescription))
            if state.canRedo { status.addArrangedSubview(chatButton("Redo", symbol: "arrow.clockwise", action: actions.redo)) }
        } else if let live = state.liveReply, live.parts.isEmpty {
            let progress = ChatProgressView(stage: live.stage, availability: state.availability, download: actions.download)
            status.addArrangedSubview(progress)
        }
        status.isHidden = status.arrangedSubviews.isEmpty
    }
}

@MainActor
private final class ChatDisplayLinkTarget {
    weak var controller: ChatViewController?
    init(controller: ChatViewController) { self.controller = controller }
    @objc func tick(_ link: CADisplayLink) {
        guard let controller else { link.invalidate(); return }
        controller.tick(link)
    }
}
#endif
