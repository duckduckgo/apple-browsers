//
//  FreshChatSuggestionsView.swift
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

import UIKit

@MainActor
final class FreshChatSuggestionsView: UIView {
    enum Welcome {
        case local
        case privateChat

        var title: String {
            self == .local ? "All chats are local" : "All chats are private"
        }
    }

    struct Action {
        let title: String
        let select: () -> Void
    }

    enum State {
        case loading
        case ready([Action])
        case unavailable
    }

    private let actions = SuggestionChipFlowView()
    private let status = UILabel()
    private var displayedTitles: [String]?
    private var lastAnimatedTitles: [String]?

    init(welcome: Welcome) {
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        let image = UIImageView(image: UIImage(resource: .duckAIDefault))
        image.contentMode = .scaleAspectFit
        image.isAccessibilityElement = false
        image.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let title = UILabel()
        title.text = welcome.title
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.numberOfLines = 0
        title.accessibilityTraits = .header
        let welcomeContent = UIStackView(arrangedSubviews: [image, title])
        welcomeContent.axis = .vertical
        welcomeContent.spacing = 16
        status.font = .preferredFont(forTextStyle: .footnote)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = .secondaryLabel
        status.textAlignment = .center
        status.numberOfLines = 0
        let suggestions = UIStackView(arrangedSubviews: [status, actions])
        suggestions.axis = .vertical
        suggestions.spacing = 10
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = false
        let content = UIView()
        let welcomeArea = UILayoutGuide()
        [scroll, content, welcomeContent, suggestions].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(scroll)
        scroll.addSubview(content)
        content.addSubview(welcomeContent)
        content.addSubview(suggestions)
        content.addLayoutGuide(welcomeArea)
        let preferredHeight = content.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        preferredHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
            preferredHeight,
            welcomeArea.topAnchor.constraint(equalTo: content.topAnchor),
            welcomeArea.bottomAnchor.constraint(equalTo: suggestions.topAnchor),
            welcomeContent.centerYAnchor.constraint(equalTo: welcomeArea.centerYAnchor),
            welcomeContent.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 24),
            welcomeContent.bottomAnchor.constraint(lessThanOrEqualTo: suggestions.topAnchor, constant: -24),
            welcomeContent.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            welcomeContent.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48),
            suggestions.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            suggestions.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            suggestions.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: FreshChatSuggestionsView, _) in
            view.actions.invalidateIntrinsicContentSize()
            view.actions.setNeedsLayout()
        }
        render(.loading)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(_ state: State) {
        switch state {
        case .loading, .unavailable:
            actions.isHidden = true
            status.text = nil
        case .ready(let suggestions):
            let titles = suggestions.map(\.title)
            status.text = suggestions.isEmpty ? nil : "From your recent tabs"
            actions.isHidden = suggestions.isEmpty
            if displayedTitles != titles {
                actions.setActions(suggestions)
                displayedTitles = titles
            } else {
                actions.updateActions(suggestions)
            }
            guard !suggestions.isEmpty, lastAnimatedTitles != titles else { return }
            lastAnimatedTitles = titles
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            actions.alpha = 0
            actions.transform = CGAffineTransform(translationX: 0, y: 6)
            UIView.animate(withDuration: 0.2) {
                self.actions.alpha = 1
                self.actions.transform = .identity
            }
        }
    }
}

@MainActor
private final class SuggestionChipFlowView: UIView {
    private var buttons: [UIButton] = []
    private var selections: [() -> Void] = []
    private var measuredWidth: CGFloat = 0
    private let spacing: CGFloat = 8

    func setActions(_ actions: [FreshChatSuggestionsView.Action]) {
        buttons.forEach { $0.removeFromSuperview() }
        selections = actions.map(\.select)
        buttons = actions.enumerated().map { index, action in
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = action.title
            configuration.baseForegroundColor = .label
            configuration.background.strokeColor = .separator
            configuration.background.strokeWidth = 1
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            configuration.titleLineBreakMode = .byWordWrapping
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
                return attributes
            }
            button.configuration = configuration
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.accessibilityHint = "Sends this prompt with the referenced tabs."
            button.addAction(UIAction { [weak self] _ in self?.selections[index]() }, for: .touchUpInside)
            addSubview(button)
            return button
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func updateActions(_ actions: [FreshChatSuggestionsView.Action]) {
        selections = actions.map(\.select)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: arrange(width: bounds.width, apply: false))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if measuredWidth != bounds.width {
            measuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        _ = arrange(width: bounds.width, apply: true)
    }

    private func arrange(width: CGFloat, apply: Bool) -> CGFloat {
        guard width > 0, !buttons.isEmpty else { return 0 }
        var rows: [[(button: UIButton, size: CGSize)]] = []
        var row: [(button: UIButton, size: CGSize)] = []
        var rowWidth: CGFloat = 0
        for button in buttons {
            let ideal = button.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            let buttonWidth = min(width, ideal.width)
            let fitting = button.systemLayoutSizeFitting(CGSize(width: buttonWidth, height: 0),
                                                         withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            let size = CGSize(width: buttonWidth, height: max(44, fitting.height))
            if !row.isEmpty, rowWidth + spacing + size.width > width {
                rows.append(row)
                row = []
                rowWidth = 0
            }
            rowWidth += (row.isEmpty ? 0 : spacing) + size.width
            row.append((button, size))
        }
        if !row.isEmpty { rows.append(row) }
        var y: CGFloat = 0
        for row in rows {
            let rowWidth = row.reduce(CGFloat.zero) { $0 + $1.size.width } + CGFloat(row.count - 1) * spacing
            let rowHeight = row.map { $0.size.height }.max() ?? 0
            var x = (width - rowWidth) / 2
            for item in row {
                if apply {
                    let originX = effectiveUserInterfaceLayoutDirection == .rightToLeft ? width - x - item.size.width : x
                    item.button.frame = CGRect(x: originX, y: y, width: item.size.width, height: rowHeight)
                }
                x += item.size.width + spacing
            }
            y += rowHeight + spacing
        }
        return y - spacing
    }
}
