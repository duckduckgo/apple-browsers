//
//  MessageViews.swift
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

final class UserMessageView: UIStackView {
    init(message: UserMessage) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 4
        let bubble = UIStackView()
        bubble.axis = .vertical
        bubble.spacing = 8
        bubble.backgroundColor = DuckAIChatTokens.Color.userBubble
        bubble.layer.cornerRadius = 24
        bubble.isLayoutMarginsRelativeArrangement = true
        bubble.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        var copyText: [String] = []
        for part in message.parts {
            let text: String
            switch part {
            case .text(let value): text = value
            case .context(let context):
                switch context {
                case .page(let page): text = "Page content from [\(page.title)](\(page.url?.absoluteString ?? ""))"
                case .selection(let selection): text = "Selected text from [\(selection.title)](\(selection.url?.absoluteString ?? ""))\n\n\(selection.content)"
                case .pastedText(let value): text = value
                case .request(let request):
                    switch request {
                    case .summarize: text = "Summarize"
                    case .translate: text = "Translate"
                    }
                }
            case .attachment(let attachment):
                switch attachment.kind {
                case .image: text = "Image"
                case .file(let name, _): text = name
                }
            }
            copyText.append(text)
            let view = InlineTextView()
            view.update(text, markdown: { if case .context = part { true } else { false } }())
            bubble.addArrangedSubview(view)
        }
        addArrangedSubview(bubble)
        let copy = chatButton("Copy", symbol: "doc.on.doc") { UIPasteboard.general.string = copyText.joined(separator: "\n") }
        copy.accessibilityIdentifier = "NativeChat.UserCopy"
        let actions = UIStackView(arrangedSubviews: [UIView(), copy])
        addArrangedSubview(actions)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class AssistantMessageView: UIStackView {
    private let heading = chatLabel("", style: ChatTypography.modelName)
    private let content = UIStackView()
    private let controls = UIStackView()
    private var blocks: [String: MarkdownBlockView] = [:]
    private var otherParts: [Int: UIStackView] = [:]
    private var previous = PresentedReply()
    private var previousLatest = false
    private var previousCanRedo = false
    private var expandedReasoning = Set<Int>()

    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 12
        content.axis = .vertical
        content.spacing = 12
        controls.spacing = 4
        addArrangedSubview(heading)
        addArrangedSubview(content)
        addArrangedSubview(controls)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ reply: PresentedReply, metadata: ChatDisplayMetadata, latest: Bool, canRedo: Bool,
               actions: ChatActions, context: ChatContext) {
        guard reply != previous || latest != previousLatest || canRedo != previousCanRedo else { return }
        heading.text = reply.isRevealing ? "Generating response" : metadata.title
        heading.isHidden = reply.parts.isEmpty
        var ordered: [UIView] = []
        var keys = Set<String>()
        for (index, part) in reply.parts.enumerated() {
            if case .text = part {
                for block in reply.documents[index] ?? [] {
                    let key = "\(index):\(block.id)"
                    keys.insert(key)
                    let view = blocks[key] ?? MarkdownBlockView()
                    blocks[key] = view
                    view.update(block.block)
                    ordered.append(view)
                }
            } else {
                let container = otherParts[index] ?? UIStackView()
                container.axis = .vertical
                container.spacing = 8
                otherParts[index] = container
                if !previous.parts.indices.contains(index) || previous.parts[index] != part {
                    updatePart(part, index: index, container: container)
                }
                ordered.append(container)
            }
        }
        for key in Array(blocks.keys) where !keys.contains(key) { blocks.removeValue(forKey: key)?.removeFromSuperview() }
        for view in content.arrangedSubviews where !ordered.contains(where: { $0 === view }) { view.removeFromSuperview() }
        for (index, view) in ordered.enumerated() {
            if content.arrangedSubviews.indices.contains(index), content.arrangedSubviews[index] === view { continue }
            content.removeArrangedSubview(view)
            content.insertArrangedSubview(view, at: index)
        }
        updateControls(reply, latest: latest, canRedo: canRedo, actions: actions, context: context)
        previous = reply
        previousLatest = latest
        previousCanRedo = canRedo
    }

    private func updateControls(_ reply: PresentedReply, latest: Bool, canRedo: Bool, actions: ChatActions, context: ChatContext) {
        if reply.isRevealing != previous.isRevealing || latest != previousLatest || canRedo != previousCanRedo {
            controls.arrangedSubviews.forEach { $0.removeFromSuperview() }
            if latest, !reply.isRevealing {
                let text = reply.parts.compactMap { if case .text(let value) = $0 { value } else { nil } }.joined(separator: "\n\n")
                controls.addArrangedSubview(chatButton("Copy", symbol: "doc.on.doc") { UIPasteboard.general.string = text })
                if canRedo { controls.addArrangedSubview(chatButton("Redo", symbol: "arrow.clockwise", action: actions.redo)) }
                controls.addArrangedSubview(chatButton("Continue in Duck.ai") { actions.continueInWeb(context) })
            }
        }
        controls.isHidden = controls.arrangedSubviews.isEmpty
    }

    private func updatePart(_ part: AssistantPart, index: Int, container: UIStackView) {
        container.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch part {
        case .reasoning(let reasoning):
            let text = InlineTextView()
            text.update(reasoning.text, style: ChatTypography.subtitle)
            text.isHidden = reasoning.displaySeconds != nil && !expandedReasoning.contains(index)
            let title = reasoning.displaySeconds.map { "Reasoning (\($0)s)" } ?? "Reasoning"
            container.addArrangedSubview(chatButton(title, symbol: "chevron.down") { [weak self, weak text] in
                guard let self, let text else { return }
                if expandedReasoning.contains(index) { expandedReasoning.remove(index) } else { expandedReasoning.insert(index) }
                text.isHidden.toggle()
            })
            container.addArrangedSubview(text)
        case .source(let source):
            container.addArrangedSubview(chatButton(source.title, symbol: "link") { UIApplication.shared.open(source.url) })
        case .refusal: container.addArrangedSubview(chatLabel("This model can't help with this request."))
        case .toolCall(let call): container.addArrangedSubview(chatLabel("Using \(call.name)", style: ChatTypography.subtitle))
        case .toolResult(let result):
            let text = InlineTextView()
            text.update(result.result, style: ChatTypography.subtitle)
            container.addArrangedSubview(text)
        case .text: break
        }
    }
}
#endif
