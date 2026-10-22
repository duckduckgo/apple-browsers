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
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 12)
        let contexts = message.parts.compactMap { part -> ContextPart? in
            guard case .context(let context) = part else { return nil }
            if case .request = context { return nil }
            return context
        }
        let bubble = UserBubbleView(hasContext: !contexts.isEmpty)
        let prompt = Self.prompt(message)
        if !prompt.isEmpty {
            let text = InlineTextView()
            text.dataDetectorTypes = .link
            text.update(prompt, markdown: false)
            bubble.addArrangedSubview(text)
        }
        for context in contexts { bubble.addArrangedSubview(ContextSummaryView(context: context)) }
        for part in message.parts {
            guard case .attachment(let attachment) = part else { continue }
            let name: String
            switch attachment.kind {
            case .image: name = "Image"
            case .file(let filename, _): name = filename
            }
            bubble.addArrangedSubview(chatLabel(name, style: ChatTypography.subtitle))
        }
        addArrangedSubview(bubble)
        let copy = chatIconButton("Copy", symbol: "doc.on.doc") { UIPasteboard.general.string = prompt }
        copy.accessibilityIdentifier = "NativeChat.UserCopy"
        addArrangedSubview(UIStackView(arrangedSubviews: [UIView(), copy]))
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func prompt(_ message: UserMessage) -> String {
        let text = message.parts.compactMap { if case .text(let value) = $0 { value } else { nil } }.joined(separator: "\n")
        if !text.isEmpty { return text }
        for part in message.parts {
            if case .context(.request(let request)) = part {
                switch request {
                case .summarize: return "Summarize"
                case .translate: return "Translate"
                }
            }
        }
        return ""
    }
}

private final class UserBubbleView: UIStackView {
    private let tail: BubbleTailView?

    init(hasContext: Bool) {
        tail = hasContext ? nil : BubbleTailView()
        super.init(frame: .zero)
        axis = .vertical
        spacing = 4
        backgroundColor = DuckAIChatTokens.Color.userBubble
        layer.cornerRadius = 24
        if !hasContext { layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] }
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        if let tail { addSubview(tail) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        tail?.frame = CGRect(x: bounds.width, y: 0, width: 12, height: 21)
    }
}

private final class BubbleTailView: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: BubbleTailView, _: UITraitCollection) in
            view.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 3.072, y: 9.154))
        path.addCurve(to: CGPoint(x: 12, y: 21), controlPoint1: CGPoint(x: 12, y: 10.127), controlPoint2: CGPoint(x: 12, y: 15.564))
        path.addLine(to: CGPoint(x: 12, y: 0))
        path.addCurve(to: CGPoint(x: 1.465, y: 6.297), controlPoint1: CGPoint(x: 7.219, y: 0), controlPoint2: CGPoint(x: 3.707, y: 2.859))
        path.addCurve(to: CGPoint(x: 3.072, y: 9.154), controlPoint1: CGPoint(x: 0.675, y: 7.51), controlPoint2: CGPoint(x: 1.634, y: 8.997))
        path.close()
        path.apply(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 12, ty: 0))
        DuckAIChatTokens.Color.userBubble.setFill()
        path.fill()
    }
}

private final class ContextSummaryView: UIStackView {
    init(context: ContextPart) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 4
        let prefix: String
        let title: String
        let url: URL?
        let selection: String?
        let symbol: String
        switch context {
        case .page(let page):
            prefix = "Page content from "
            title = page.title
            url = page.url
            selection = nil
            symbol = "globe"
        case .selection(let value):
            prefix = "Selected text from "
            title = value.title
            url = value.url
            selection = value.content
            symbol = "text.quote"
        case .pastedText(let text):
            prefix = "Pasted text"
            title = ""
            url = nil
            selection = text
            symbol = "doc.on.clipboard"
        case .request: return
        }
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12)))
        icon.tintColor = DuckAIChatTokens.Color.textSecondary
        icon.contentMode = .center
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let caption = InlineTextView()
        let text = NSMutableAttributedString(string: prefix, attributes: [.font: ChatTypography.caption.font,
                                                                         .foregroundColor: DuckAIChatTokens.Color.textSecondary])
        var attributes: [NSAttributedString.Key: Any] = [.font: ChatTypography.caption.font,
                                                         .foregroundColor: DuckAIChatTokens.Color.textPrimary,
                                                         .underlineStyle: NSUnderlineStyle.single.rawValue]
        if let url { attributes[.link] = url }
        text.append(NSAttributedString(string: title, attributes: attributes))
        caption.attributedText = text
        caption.linkTextAttributes = [.foregroundColor: DuckAIChatTokens.Color.textPrimary, .underlineStyle: NSUnderlineStyle.single.rawValue]
        let row = UIStackView(arrangedSubviews: [icon, caption])
        row.spacing = 4
        row.alignment = .top
        addArrangedSubview(row)
        if let selection {
            let quote = MarkdownBlockView()
            quote.update(.blockquote([.paragraph(selection)]))
            quote.isHidden = true
            var configuration = UIButton.Configuration.plain()
            configuration.title = "Show more"
            let toggle = UIButton(configuration: configuration)
            toggle.accessibilityIdentifier = "NativeChat.Showmore"
            toggle.contentHorizontalAlignment = .leading
            toggle.configuration?.baseForegroundColor = DuckAIChatTokens.Color.accent
            toggle.addAction(UIAction { [weak toggle, weak quote] _ in
                guard let quote else { return }
                quote.isHidden.toggle()
                toggle?.configuration?.title = quote.isHidden ? "Show more" : "Show less"
            }, for: .touchUpInside)
            addArrangedSubview(toggle)
            addArrangedSubview(quote)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class AssistantMessageView: UIStackView {
    private let heading = ChatHeadingView()
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
        spacing = 2
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 4, left: 12, bottom: 0, right: 12)
        content.axis = .vertical
        content.spacing = 8
        controls.spacing = 4
        addArrangedSubview(heading)
        addArrangedSubview(content)
        setCustomSpacing(12, after: content)
        addArrangedSubview(controls)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ reply: PresentedReply, metadata: ChatDisplayMetadata, latest: Bool, canRedo: Bool,
               actions: ChatActions, context: ChatContext) {
        guard reply != previous || latest != previousLatest || canRedo != previousCanRedo else { return }
        heading.update(title: reply.isRevealing ? "Generating response" : metadata.title, active: latest, loading: reply.isRevealing)
        heading.isHidden = reply.parts.isEmpty
        var ordered: [UIView] = []
        var keys = Set<String>()
        var markdown: [ObjectIdentifier: MarkdownBlock] = [:]
        for (index, part) in reply.parts.enumerated() {
            if case .text = part {
                for block in reply.documents[index] ?? [] {
                    let key = "\(index):\(block.id)"
                    keys.insert(key)
                    let view = blocks[key] ?? MarkdownBlockView()
                    blocks[key] = view
                    view.update(block.block)
                    markdown[ObjectIdentifier(view)] = block.block
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
        for (index, view) in ordered.enumerated() {
            let current = markdown[ObjectIdentifier(view)]
            let next = index + 1 < ordered.count ? markdown[ObjectIdentifier(ordered[index + 1])] : nil
            content.setCustomSpacing(Self.gap(after: current, before: next), after: view)
        }
        updateControls(reply, latest: latest, canRedo: canRedo, actions: actions, context: context)
        previous = reply
        previousLatest = latest
        previousCanRedo = canRedo
    }

    private static func gap(after current: MarkdownBlock?, before next: MarkdownBlock?) -> CGFloat {
        if case .thematicBreak = current { return 32 }
        if case .thematicBreak = next { return 32 }
        if case .heading = next {
            switch current {
            case .paragraph, .list: return 40
            case .heading: return 24
            default: return 16
            }
        }
        if case .heading = current { return 12 }
        switch current {
        case .codeBlock, .blockquote, .table: return 16
        default: break
        }
        switch next {
        case .blockquote, .table: return 16
        default: return 8
        }
    }

    private func updateControls(_ reply: PresentedReply, latest: Bool, canRedo: Bool, actions: ChatActions, context: ChatContext) {
        if reply.isRevealing != previous.isRevealing || latest != previousLatest || canRedo != previousCanRedo {
            controls.arrangedSubviews.forEach { $0.removeFromSuperview() }
            if latest, !reply.isRevealing {
                let text = reply.parts.compactMap { if case .text(let value) = $0 { value } else { nil } }.joined(separator: "\n\n")
                controls.addArrangedSubview(chatIconButton("Copy", symbol: "doc.on.doc") { UIPasteboard.general.string = text })
                if canRedo { controls.addArrangedSubview(chatIconButton("Redo", symbol: "arrow.clockwise", action: actions.redo)) }
                controls.addArrangedSubview(UIView())
                let continuation = chatButton("Continue in Duck.ai") { actions.continueInWeb(context) }
                continuation.setContentCompressionResistancePriority(.required, for: .horizontal)
                controls.addArrangedSubview(continuation)
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
