//
//  ChatControls.swift
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

typealias ChatTypography = DuckAIChatTokens.Typography

@MainActor
func chatLabel(_ text: String, style: ChatTypography.Style = ChatTypography.body) -> UILabel {
    let label = UILabel()
    label.numberOfLines = 0
    label.text = text
    label.font = style.font
    label.textColor = DuckAIChatTokens.Color.textPrimary
    return label
}

@MainActor
func chatButton(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.image = symbol.flatMap { UIImage(systemName: $0) }
    configuration.imagePadding = 6
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var attributes = incoming
        attributes.font = ChatTypography.subtitle.font
        return attributes
    }
    configuration.baseForegroundColor = DuckAIChatTokens.Color.textSecondary
    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    button.accessibilityIdentifier = "NativeChat." + title.replacingOccurrences(of: " ", with: "")
    button.accessibilityLabel = title
    button.titleLabel?.numberOfLines = 1
    button.titleLabel?.lineBreakMode = .byTruncatingTail
    button.titleLabel?.font = ChatTypography.subtitle.font
    return button
}

@MainActor
func chatIconButton(_ title: String, symbol: String, action: @escaping () -> Void) -> UIButton {
    let button = chatButton(title, action: action)
    var configuration = button.configuration
    configuration?.title = nil
    configuration?.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16))
    configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16)
    configuration?.contentInsets = .zero
    configuration?.cornerStyle = .capsule
    button.configuration = configuration
    button.configurationUpdateHandler = { button in
        var configuration = button.configuration
        configuration?.background.backgroundColor = button.isHighlighted ? DuckAIChatTokens.Color.controlSecondary : .clear
        button.configuration = configuration
    }
    button.widthAnchor.constraint(equalToConstant: 36).isActive = true
    button.heightAnchor.constraint(equalToConstant: 36).isActive = true
    return button
}

final class ChatHeadingView: UIStackView {
    private let icon = UIImageView(image: UIImage(systemName: "sparkles"))
    private let label = chatLabel("", style: ChatTypography.modelName)
    private let spinner = UIActivityIndicatorView(style: .medium)

    init() {
        super.init(frame: .zero)
        alignment = .center
        spacing = 12
        let anchor = UIView()
        anchor.widthAnchor.constraint(equalToConstant: 16).isActive = true
        anchor.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let views: [UIView] = [icon, spinner]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            anchor.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: anchor.centerXAnchor), view.centerYAnchor.constraint(equalTo: anchor.centerYAnchor),
                view.widthAnchor.constraint(equalToConstant: 16), view.heightAnchor.constraint(equalToConstant: 16)
            ])
        }
        icon.contentMode = .scaleAspectFit
        addArrangedSubview(anchor)
        addArrangedSubview(label)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(title: String, active: Bool = true, loading: Bool = false) {
        label.text = title
        label.textColor = active ? DuckAIChatTokens.Color.textPrimary : DuckAIChatTokens.Color.textSecondary
        icon.tintColor = active ? DuckAIChatTokens.Color.modelIconActive : DuckAIChatTokens.Color.modelIconPrevious
        let animates = loading && !UIAccessibility.isReduceMotionEnabled
        icon.isHidden = animates
        spinner.isHidden = !animates
        if animates { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}

final class ChatProgressView: UIStackView {
    init(stage: LoadingStage, availability: ProviderAvailability, download: @escaping () -> Void) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 8
        accessibilityIdentifier = "NativeChat.Status"
        let title: String
        var fraction: Double?
        switch (stage, availability) {
        case (.waitingForModel, .needsDownload(let bytes)):
            title = "Download model (" + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + ")"
            addArrangedSubview(chatButton("Download", action: download))
        case (.waitingForModel, .downloading(let value)):
            title = "Downloading model"
            fraction = value
        case (.provider(.loadingModel(let value)), _): title = "Loading model"; fraction = value
        case (.provider(.readingInput(let tokens, let value)), _): title = "Reading \(tokens) tokens"; fraction = value
        default: title = "Thinking"
        }
        let heading = ChatHeadingView()
        heading.update(title: "Thinking", loading: true)
        insertArrangedSubview(heading, at: 0)
        if title != "Thinking" { addArrangedSubview(chatLabel(title, style: ChatTypography.subtitle)) }
        if let fraction {
            let progress = UIProgressView(progressViewStyle: .default)
            progress.progress = Float(fraction)
            addArrangedSubview(progress)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension ChatError {
    var chatDescription: String {
        switch self {
        case .modelNotDownloaded: "The model isn't downloaded."
        case .modelUnavailable(let reason): reason
        case .inputTooLong: "That's too much text for this model."
        case .conversationTooLong: "This chat is too long. Start a new chat."
        case .emptyResponse: "No response was generated."
        case .network: "Check your connection and try again."
        case .rateLimited: "Too many requests. Try again later."
        case .unknown: "Something went wrong."
        }
    }
}
#endif
