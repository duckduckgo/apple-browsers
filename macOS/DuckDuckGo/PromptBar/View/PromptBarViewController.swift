//
//  PromptBarViewController.swift
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

import AppKit
import DesignResourcesKit
import DesignResourcesKitIcons

/// Prompt Bar content: a single prompt field that hands what the user types to Duck.ai.
///
/// Intentionally minimal. The Duck.ai controls from the address bar panel (attach, tools, model and
/// reasoning pickers, voice) replace this field's surroundings once they are extracted into a
/// component both surfaces can share.
@MainActor
final class PromptBarViewController: NSViewController {

    private enum Constants {
        static let contentHeight: CGFloat = 56
        static let cornerRadius: CGFloat = 12
        static let horizontalInset: CGFloat = 16
        static let iconSize: CGFloat = 16
        static let iconTrailingSpacing: CGFloat = 12
        static let promptFontSize: CGFloat = 16
    }

    private let aiChatTabOpener: AIChatTabOpening

    private lazy var panelView = ColorView(frame: .zero,
                                           backgroundColor: NSColor(designSystemColor: .surfacePrimary),
                                           cornerRadius: Constants.cornerRadius,
                                           borderColor: NSColor(designSystemColor: .lines),
                                           borderWidth: 1)

    private let iconView = NSImageView()
    private let promptField = NSTextField()

    var onPreferredWindowContentSizeChanged: ((NSSize) -> Void)?
    var onSubmit: (() -> Void)?

    init(aiChatTabOpener: AIChatTabOpening) {
        self.aiChatTabOpener = aiChatTabOpener
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("PromptBarViewController: Bad initializer")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: PromptBarPlacement.preferredWidth, height: Constants.contentHeight))
        setUpUI()
    }

    private func setUpUI() {
        panelView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = DesignSystemImages.Glyphs.Size16.duckAi
        iconView.image?.isTemplate = true
        iconView.contentTintColor = NSColor(designSystemColor: .iconsPrimary)
        panelView.addSubview(iconView)

        promptField.translatesAutoresizingMaskIntoConstraints = false
        promptField.isBordered = false
        promptField.drawsBackground = false
        promptField.focusRingType = .none
        promptField.font = .systemFont(ofSize: Constants.promptFontSize)
        promptField.textColor = NSColor(designSystemColor: .textPrimary)
        promptField.placeholderString = UserText.aiChatOmnibarPlaceholder
        promptField.cell?.usesSingleLineMode = true
        promptField.lineBreakMode = .byTruncatingTail
        promptField.delegate = self
        promptField.setAccessibilityIdentifier("PromptBar.promptField")
        panelView.addSubview(promptField)

        NSLayoutConstraint.activate([
            panelView.topAnchor.constraint(equalTo: view.topAnchor),
            panelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panelView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: Constants.horizontalInset),
            iconView.centerYAnchor.constraint(equalTo: panelView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            promptField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Constants.iconTrailingSpacing),
            promptField.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -Constants.horizontalInset),
            promptField.centerYAnchor.constraint(equalTo: panelView.centerYAnchor)
        ])
    }

    /// Opens the prompt in a new selected Duck.ai tab, matching the address bar's hand-off. Blank
    /// input is ignored so Enter on an empty bar does nothing rather than opening an empty chat.
    private func submitPrompt() {
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        promptField.stringValue = ""
        aiChatTabOpener.openAIChatTab(with: .query(prompt, shouldAutoSubmit: true), behavior: .newTab(selected: true))
        onSubmit?()
    }
}

// MARK: - PromptBarContentHosting

extension PromptBarViewController: PromptBarContentHosting {

    var viewController: NSViewController { self }

    /// No menus or pickers in the MVP, so nothing ever suppresses dismissal.
    var isPresentingAuxiliaryUI: Bool { false }

    var preferredWindowContentSize: NSSize {
        NSSize(width: PromptBarPlacement.preferredWidth, height: Constants.contentHeight)
    }

    func prepareForPresentation() {
        promptField.stringValue = ""
    }

    func focusPromptEditor() {
        view.window?.makeFirstResponder(promptField)
    }

    func resetAfterDismissal() {
        promptField.stringValue = ""
    }
}

// MARK: - NSTextFieldDelegate

extension PromptBarViewController: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            submitPrompt()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // The field editor would otherwise swallow Escape to revert its own editing.
            view.window?.cancelOperation(nil)
            return true
        default:
            return false
        }
    }
}
