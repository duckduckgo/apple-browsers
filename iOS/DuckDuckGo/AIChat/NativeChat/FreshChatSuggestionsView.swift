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

/// The same start actions appear in the native transcript and fresh web welcome area.
@MainActor
final class FreshChatSuggestionsView: UIView {
    struct Action {
        let title: String
        let select: () -> Void
    }

    enum State {
        case loading
        case ready([Action])
        case unavailable
    }

    var onRetry: (() -> Void)?
    private let content = UIStackView()
    private let actions = UIStackView()
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retry = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        let image = UIImageView(image: UIImage(resource: .duckAIDefault))
        image.contentMode = .scaleAspectFit
        image.isAccessibilityElement = false
        image.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let title = UILabel()
        title.text = "Start with your open tabs"
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.numberOfLines = 0
        title.accessibilityTraits = .header
        status.font = .preferredFont(forTextStyle: .subheadline)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = .secondaryLabel
        status.textAlignment = .center
        status.numberOfLines = 0
        actions.axis = .vertical
        actions.spacing = 10
        retry.setTitle("Try again", for: .normal)
        retry.titleLabel?.font = .preferredFont(forTextStyle: .body)
        retry.titleLabel?.adjustsFontForContentSizeCategory = true
        retry.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        content.axis = .vertical
        content.spacing = 16
        [image, title, status, spinner, actions, retry].forEach(content.addArrangedSubview)
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        render(.loading)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(_ state: State) {
        actions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actions.alpha = 1
        actions.transform = .identity
        spinner.stopAnimating()
        retry.isHidden = true
        switch state {
        case .loading:
            status.text = "Finding ideas on this device…"
            spinner.startAnimating()
        case .unavailable:
            status.text = "Suggestions aren't available. You can still ask anything."
            retry.isHidden = false
        case .ready(let suggestions):
            status.text = suggestions.isEmpty ? "Ask anything to get started." : "Ideas from your open tabs, created on this device."
            for suggestion in suggestions {
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.tinted()
                configuration.title = suggestion.title
                configuration.baseForegroundColor = .label
                configuration.baseBackgroundColor = .secondarySystemBackground
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
                configuration.cornerStyle = .large
                button.configuration = configuration
                button.titleLabel?.numberOfLines = 0
                button.titleLabel?.adjustsFontForContentSizeCategory = true
                button.contentHorizontalAlignment = .leading
                button.accessibilityHint = "Sends this prompt with the referenced tabs."
                button.addAction(UIAction { _ in suggestion.select() }, for: .touchUpInside)
                actions.addArrangedSubview(button)
            }
            guard !UIAccessibility.isReduceMotionEnabled, !suggestions.isEmpty else { return }
            actions.alpha = 0
            actions.transform = CGAffineTransform(translationX: 0, y: 8)
            UIView.animate(withDuration: 0.25) {
                self.actions.alpha = 1
                self.actions.transform = .identity
            }
        }
    }
}
